;;; init-workspace.el --- Per-project window and tab sessions -*- lexical-binding: t; -*-

;;; Commentary:
;; Each frame works on one project, like a JetBrains project window.  Its
;; window layout, the tab-line tabs of every window and the position in each
;; file are saved under var/workspaces/ (never inside the repository) and
;; restored when the project is opened again.
;;
;; Tabs are the window's previous and next buffers, which tab-line displays
;; as (reverse prev) current next.  Files are stored relative to the project
;; root so that a moved project keeps its workspace.

;;; Code:

(require 'cl-lib)
(require 'project)
(require 'seq)
(require 'subr-x)
(require 'xref)
(require 'init-session)

(declare-function my/dirvish-show "init-dirvish")
(declare-function my/dirvish-empty-buffer "init-dirvish")
(declare-function dirvish-side--session-visible-p "dirvish-side")
(declare-function dirvish-quit "dirvish")
(declare-function my/welcome-show "init-welcome")
(declare-function my/frame-title-directory "init-frame-title")
(defvar my/frame-title-cache)
(defvar dirvish-side-width)

(defvar my/workspace-directory (my/var-file "workspaces/")
  "Directory holding one saved workspace per project.")
(defvar my/workspace-meta-file (my/var-file "projects-meta.eld")
  "Start page metadata: pinned state, last use, branch and tab count.")
(defconst my/workspace-version 1)
(defvar my/workspace-max-tabs 40 "Most tabs saved per window.")
(defvar my/workspace-max-history 100 "Most entries saved per navigation stack.")
(defvar my/workspace-lazy-restore t
  "Non-nil opens hidden tabs in the background after the visible ones.")

(defvar my/workspace--meta 'unread "Cached metadata alist of (ROOT . PLIST).")
(defvar my/workspace--missing 0 "Files skipped by the restore in progress.")
(defvar my/workspace--queue nil "Pending (WINDOW ROOT KIND ENTRY) background tabs.")
(defvar my/workspace--queue-timer nil)
(defvar my/workspace--save-timer nil)

;;;; Storage

(defun my/workspace-normalize-root (root)
  "Return ROOT as an abbreviated directory name; remote roots are not expanded."
  (file-name-as-directory
   (if (file-remote-p root) root (abbreviate-file-name (expand-file-name root)))))

(defun my/workspace-root-of (directory)
  "Return the project root containing DIRECTORY, or DIRECTORY itself."
  (my/workspace-normalize-root
   (if-let* ((project (project-current nil directory)))
       (project-root project)
     directory)))

(defun my/workspace-root-name (root)
  "Return a short display name for ROOT."
  (file-name-nondirectory (directory-file-name root)))

(defun my/workspace-file (root)
  "Return the file holding ROOT's workspace."
  (expand-file-name
   (format "%s-%s.eld"
           (replace-regexp-in-string "[^[:alnum:]._-]" "_" (my/workspace-root-name root))
           (substring (md5 (my/workspace-normalize-root root)) 0 8))
   my/workspace-directory))

(defun my/workspace-read-data (file)
  "Read one Lisp object from FILE, or nil when it is missing or invalid."
  (when (file-readable-p file)
    (condition-case err
        (with-temp-buffer
          (insert-file-contents file)
          (read (current-buffer)))
      (error (message "无法读取 %s：%s" (abbreviate-file-name file)
                      (error-message-string err))
             nil))))

(defun my/workspace-write-data (file data)
  "Write DATA to FILE atomically: an interrupted save keeps the old file."
  (let ((temp (make-temp-file (expand-file-name ".tmp-" (file-name-directory file))))
        (coding-system-for-write 'utf-8-unix)
        (print-length nil) (print-level nil) (print-circle nil))
    (unwind-protect
        (progn
          (with-temp-file temp
            (insert ";;; -*- mode: lisp-data; coding: utf-8-unix -*-\n")
            (pp data (current-buffer)))
          (rename-file temp file t))
      (when (file-exists-p temp) (delete-file temp)))))

(defun my/workspace-meta ()
  "Return the cached project metadata alist."
  (when (eq my/workspace--meta 'unread)
    (setq my/workspace--meta (my/workspace-read-data my/workspace-meta-file)))
  my/workspace--meta)

(defun my/workspace-meta-get (root)
  "Return the metadata plist of ROOT."
  (alist-get root (my/workspace-meta) nil nil #'equal))

(defun my/workspace-meta-update (root &rest properties)
  "Set PROPERTIES in ROOT's metadata and write the index."
  (let ((meta (my/workspace-meta))
        (plist (copy-sequence (my/workspace-meta-get root))))
    (while properties
      (setq plist (plist-put plist (pop properties) (pop properties))))
    (setf (alist-get root meta nil nil #'equal) plist)
    (setq my/workspace--meta meta)
    (my/workspace-write-data my/workspace-meta-file meta)))

(defun my/workspace-forget (root)
  "Remove ROOT from the start page; its saved workspace file is kept."
  (setq my/workspace--meta
        (seq-remove (lambda (entry) (equal (car entry) root)) (my/workspace-meta)))
  (my/workspace-write-data my/workspace-meta-file my/workspace--meta)
  ;; project.el may store the same root expanded or abbreviated.
  (dolist (known (project-known-project-roots))
    (when (equal (my/workspace-normalize-root known) root)
      (project-forget-project known))))

(defun my/workspace-projects ()
  "Return known project roots, pinned first, then most recently used."
  (let ((roots (delete-dups
                (mapcar #'my/workspace-normalize-root
                        (append (mapcar #'car (my/workspace-meta))
                                (project-known-project-roots))))))
    (cl-sort roots
             (lambda (a b)
               (let ((ma (my/workspace-meta-get a)) (mb (my/workspace-meta-get b)))
                 (if (eq (not (plist-get ma :pinned)) (not (plist-get mb :pinned)))
                     (> (or (plist-get ma :opened) 0) (or (plist-get mb :opened) 0))
                   (plist-get ma :pinned)))))))

(defun my/workspace-seed-from-recentf (&optional limit)
  "Remember the projects of up to LIMIT recent local files.
Used once, when no project is known yet."
  (let ((count 0))
    (dolist (file recentf-list)
      (when (and (< count (or limit 30))
                 (not (file-remote-p file))
                 (file-exists-p file))
        (setq count (1+ count))
        (when-let* ((project (project-current nil (file-name-directory file))))
          (project-remember-project project t))))
    (project--write-project-list)))

;;;; Navigation history

;; A project frame keeps its own xref back/forward stacks, so switching
;; projects never mixes their jump histories.  Other frames share the
;; global history.

(defun my/workspace-xref-history (&optional new-value)
  "Return the selected frame's xref history, replacing it with NEW-VALUE."
  (let ((frame (selected-frame)))
    (if (not (frame-parameter frame 'my/workspace-root))
        (xref-global-history new-value)
      (let ((history (or new-value (frame-parameter frame 'my/xref-history)
                         (cons nil nil))))
        (set-frame-parameter frame 'my/xref-history history)
        history))))

(defun my/workspace--capture-history (frame root)
  "Describe FRAME's xref stacks as (:back ENTRIES :forward ENTRIES)."
  (let ((history (frame-parameter frame 'my/xref-history)))
    (cl-flet ((entries (markers)
                (seq-take (delq nil (mapcar (lambda (marker)
                                              (my/workspace--entry (marker-buffer marker)
                                                                   root nil marker))
                                            markers))
                          my/workspace-max-history)))
      (list :back (entries (car history)) :forward (entries (cdr history))))))

(defun my/workspace--apply-history (frame)
  "Install FRAME's restored history for files that are open now.
Entries for files that were not restored are dropped rather than visited.
Jumps recorded while tabs were still loading stay on top."
  (when-let* ((history (frame-parameter frame 'my/workspace-pending-history))
              (root (frame-parameter frame 'my/workspace-root)))
    (set-frame-parameter frame 'my/workspace-pending-history nil)
    (cl-flet ((markers (entries)
                (delq nil (mapcar
                           (lambda (entry)
                             (when-let* ((buffer (find-buffer-visiting
                                                  (my/workspace--decode-file
                                                   (plist-get entry :file) root))))
                               (with-current-buffer buffer
                                 (copy-marker (max (point-min)
                                                   (min (plist-get entry :point) (point-max)))))))
                           entries))))
      (let ((current (frame-parameter frame 'my/xref-history)))
        (set-frame-parameter
         frame 'my/xref-history
         (cons (append (car current) (markers (plist-get history :back)))
               (append (cdr current) (markers (plist-get history :forward)))))))))

(defun my/workspace--frame-queued-p (frame)
  "Return non-nil while FRAME still has background tabs to open."
  (seq-some (lambda (item) (eq (window-frame (car item)) frame))
            (seq-filter (lambda (item) (window-live-p (car item))) my/workspace--queue)))

(defun my/workspace--apply-ready-histories ()
  "Install restored histories of frames whose tabs have all been opened."
  (dolist (frame (frame-list))
    (when (and (frame-parameter frame 'my/workspace-pending-history)
               (not (my/workspace--frame-queued-p frame)))
      (my/workspace--apply-history frame))))

;;;; Capture

(defun my/workspace--encode-file (file root)
  "Return FILE relative to ROOT when inside it, otherwise abbreviated."
  (let ((file (expand-file-name file))
        (base (expand-file-name root)))
    (if (string-prefix-p base file)
        (substring file (length base))
      (abbreviate-file-name file))))

(defun my/workspace--decode-file (file root)
  "Return the absolute name of saved FILE in ROOT."
  (expand-file-name file (expand-file-name root)))

(defun my/workspace--position (value)
  "Return the integer position of VALUE, a marker or number."
  (cond ((markerp value) (marker-position value))
        ((integerp value) value)))

(defun my/workspace--entry (buffer root &optional start point)
  "Describe BUFFER as a restorable tab, or return nil.
START and POINT default to the buffer's own point."
  (when-let* (((buffer-live-p buffer))
              (file (buffer-local-value 'buffer-file-name buffer))
              ((not (file-remote-p file))))
    (with-current-buffer buffer
      (list :file (my/workspace--encode-file file root)
            :point (or (my/workspace--position point) (point))
            :start (my/workspace--position start)))))

(defun my/workspace--capture-leaf (window root)
  "Describe live WINDOW's tabs and positions."
  (let* ((buffer (window-buffer window))
         (seen (list buffer))
         (current (my/workspace--entry buffer root
                                       (window-start window) (window-point window)))
         (prev (delq nil (mapcar (lambda (entry)
                                   (unless (memq (car entry) seen)
                                     (push (car entry) seen)
                                     (my/workspace--entry (nth 0 entry) root
                                                          (nth 1 entry) (nth 2 entry))))
                                 (window-prev-buffers window))))
         (next (delq nil (mapcar (lambda (next-buffer)
                                   (unless (memq next-buffer seen)
                                     (push next-buffer seen)
                                     (my/workspace--entry next-buffer root)))
                                 (window-next-buffers window)))))
    (append (list :leaf t :buffer current
                  :prev (seq-take prev my/workspace-max-tabs)
                  :next (seq-take next my/workspace-max-tabs))
            (when (eq window (frame-selected-window (window-frame window)))
              (list :selected t)))))

(defun my/workspace--capture-window (window root)
  "Describe WINDOW, a live window or a combination, recursively."
  (if (window-live-p window)
      (my/workspace--capture-leaf window root)
    (let ((horizontal (and (window-left-child window) t))
          children)
      (let ((child (window-child window)))
        (while child
          (push child children)
          (setq child (window-next-sibling child))))
      (setq children (nreverse children))
      (list :split (if horizontal 'right 'below)
            :sizes (mapcar (lambda (child) (window-normal-size child horizontal)) children)
            :children (mapcar (lambda (child) (my/workspace--capture-window child root))
                              children)))))

(defun my/workspace--count (node what)
  "Count the tabs or windows (WHAT is `tabs' or `windows') in layout NODE."
  (if (plist-get node :leaf)
      (if (eq what 'windows) 1
        (+ (if (plist-get node :buffer) 1 0)
           (length (plist-get node :prev))
           (length (plist-get node :next))))
    (apply #'+ (mapcar (lambda (child) (my/workspace--count child what))
                       (plist-get node :children)))))

(defun my/workspace--sidebar-window (&optional frame)
  "Return FRAME's visible Dirvish sidebar window."
  (when (fboundp 'dirvish-side--session-visible-p)
    (with-selected-frame (or frame (selected-frame))
      (dirvish-side--session-visible-p))))

(defun my/workspace--hide-sidebar (&optional frame)
  "Hide FRAME's Dirvish sidebar, if any."
  (when-let* ((window (my/workspace--sidebar-window frame)))
    (with-selected-window window (dirvish-quit))))

(defun my/workspace-branch ()
  "Return the current buffer's branch from the frame-title cache, if known."
  (when-let* (((boundp 'my/frame-title-cache))
              ((fboundp 'my/frame-title-directory))
              (title (cdr (gethash (my/frame-title-directory) my/frame-title-cache)))
              ((string-match "⎇ \\(.+\\)\\'" title)))
    (match-string 1 title)))

(defun my/workspace-capture (&optional frame)
  "Return the workspace state of FRAME, or nil when it has no project."
  (let* ((frame (or frame (selected-frame)))
         (root (frame-parameter frame 'my/workspace-root)))
    (when root
      (with-selected-frame frame
        (let ((sidebar (my/workspace--sidebar-window frame)))
          (list :version my/workspace-version
                :root root
                :frame (when (display-graphic-p frame)
                         (list :width (frame-parameter frame 'width)
                               :height (frame-parameter frame 'height)
                               :left (frame-parameter frame 'left)
                               :top (frame-parameter frame 'top)
                               :fullscreen (frame-parameter frame 'fullscreen)))
                :sidebar (list :visible (and sidebar t)
                               :width (and sidebar (window-total-width sidebar)))
                :layout (my/workspace--capture-window (window-main-window frame) root)
                :history (my/workspace--capture-history frame root)))))))

(defun my/workspace-save (&optional frame force)
  "Save FRAME's workspace when it changed, or always with FORCE.
A layout without any file tab (for example the start page) never overwrites
the saved workspace."
  (let* ((frame (or frame (selected-frame)))
         (state (progn (my/workspace--flush-queue frame)
                       (my/workspace-capture frame))))
    (when (and state
               (> (my/workspace--count (plist-get state :layout) 'tabs) 0)
               (or force (not (equal state (frame-parameter frame 'my/workspace-saved)))))
      (let* ((root (plist-get state :root))
             (branch (with-selected-frame frame
                       (with-current-buffer (window-buffer (frame-selected-window frame))
                         (my/workspace-branch)))))
        (make-directory my/workspace-directory t)
        (my/workspace-write-data (my/workspace-file root)
                                 (append state (list :saved-at (float-time))))
        (set-frame-parameter frame 'my/workspace-saved state)
        (my/workspace-meta-update
         root :name (my/workspace-root-name root)
         :branch (or branch (plist-get (my/workspace-meta-get root) :branch)))))))

(defun my/workspace-save-all ()
  "Save the workspace of every project frame; errors never block the caller."
  (dolist (frame (frame-list))
    (when (and (frame-live-p frame) (frame-parameter frame 'my/workspace-root))
      (condition-case err
          (my/workspace-save frame)
        (error (message "保存工作区失败：%s" (error-message-string err)))))))

;;;; Restore

(defun my/workspace-empty-buffer (directory)
  "Return an empty editor buffer whose default directory is DIRECTORY."
  (if (fboundp 'my/dirvish-empty-buffer)
      (my/dirvish-empty-buffer directory)
    (let ((buffer (get-scratch-buffer-create)))
      (with-current-buffer buffer
        (setq-local default-directory (file-name-as-directory directory)))
      buffer)))

(defun my/workspace--open (entry root)
  "Visit ENTRY's file; return (BUFFER START POINT) or nil when it is gone."
  (when-let* ((entry)
              (file (my/workspace--decode-file (plist-get entry :file) root)))
    (if (not (file-exists-p file))
        (progn (setq my/workspace--missing (1+ my/workspace--missing)) nil)
      (condition-case err
          (let ((buffer (find-file-noselect file t)))
            (with-current-buffer buffer
              (cl-flet ((clamp (position)
                          (and position (max (point-min) (min position (point-max))))))
                (list buffer
                      (clamp (plist-get entry :start))
                      (clamp (plist-get entry :point))))))
        (error (message "无法恢复 %s：%s" file (error-message-string err))
               nil)))))

(defun my/workspace--append-tab (window kind opened)
  "Append OPENED, a (BUFFER START POINT), to WINDOW's tabs on side KIND.
KIND `prev' extends the strip to the left, `next' to the right.  Buffers
already shown in the window keep their place."
  (pcase-let ((`(,buffer ,start ,point) opened))
    (unless (or (eq buffer (window-buffer window))
                (assq buffer (window-prev-buffers window))
                (memq buffer (window-next-buffers window)))
      (if (eq kind 'prev)
          (set-window-prev-buffers
           window (append (window-prev-buffers window)
                          (list (list buffer
                                      (set-marker (make-marker) (or start point 1) buffer)
                                      (set-marker (make-marker) (or point 1) buffer)))))
        (unless (get-buffer-window buffer t)
          (with-current-buffer buffer (goto-char (or point 1))))
        (set-window-next-buffers window (append (window-next-buffers window)
                                                (list buffer)))))))

(defun my/workspace--refresh-tabs ()
  "Redraw tab lines after their buffer lists changed outside a command."
  (when (fboundp 'tab-line-force-update)
    (tab-line-force-update t)))

(defun my/workspace--cancel-queue (&optional frame)
  "Stop restoring background tabs of FRAME, or of every frame."
  (setq my/workspace--queue
        (and frame (seq-remove (lambda (item)
                                 (or (not (window-live-p (car item)))
                                     (eq (window-frame (car item)) frame)))
                               my/workspace--queue)))
  (when (and (null my/workspace--queue) (timerp my/workspace--queue-timer))
    (cancel-timer my/workspace--queue-timer)
    (setq my/workspace--queue-timer nil)))

(defun my/workspace--process-queue ()
  "Open queued tabs for at most 50ms, yielding whenever input is pending."
  (setq my/workspace--queue-timer nil)
  (let ((deadline (+ (float-time) 0.05)))
    (while (and my/workspace--queue
                (not (input-pending-p))
                (< (float-time) deadline))
      (pcase-let ((`(,window ,root ,kind ,entry) (pop my/workspace--queue)))
        (when (window-live-p window)
          (when-let* ((opened (my/workspace--open entry root)))
            (my/workspace--append-tab window kind opened))))))
  (my/workspace--refresh-tabs)
  (my/workspace--apply-ready-histories)
  (when my/workspace--queue
    (setq my/workspace--queue-timer
          (run-with-timer 0.05 nil #'my/workspace--process-queue))))

(defun my/workspace--flush-queue (frame)
  "Open FRAME's pending background tabs now, so a save sees all of them."
  (let (rest)
    (dolist (item my/workspace--queue)
      (pcase-let ((`(,window ,root ,kind ,entry) item))
        (cond ((not (window-live-p window)))
              ((eq (window-frame window) frame)
               (when-let* ((opened (my/workspace--open entry root)))
                 (my/workspace--append-tab window kind opened)))
              (t (push item rest)))))
    (setq my/workspace--queue (nreverse rest))
    (my/workspace--apply-history frame)))

(defun my/workspace--restore-leaf (node window root)
  "Show NODE's tabs in WINDOW; return WINDOW when NODE was selected."
  (let ((current (my/workspace--open (plist-get node :buffer) root))
        (prev (plist-get node :prev))
        (next (plist-get node :next)))
    (while (and (not current) prev)
      (setq current (my/workspace--open (pop prev) root)))
    (my/workspace--show-only window (if current (car current) (my/workspace-empty-buffer root)))
    (when current
      (when (nth 1 current) (set-window-start window (nth 1 current) t))
      (when (nth 2 current) (set-window-point window (nth 2 current))))
    (let ((pending (append (mapcar (lambda (entry) (list window root 'prev entry)) prev)
                           (mapcar (lambda (entry) (list window root 'next entry)) next))))
      (if my/workspace-lazy-restore
          (setq my/workspace--queue (append my/workspace--queue pending))
        (dolist (item pending)
          (pcase-let ((`(,_ ,_ ,kind ,entry) item))
            (when-let* ((opened (my/workspace--open entry root)))
              (my/workspace--append-tab window kind opened))))))
    (and (plist-get node :selected) window)))

(defun my/workspace--split (window size side)
  "Split WINDOW on SIDE giving the new window SIZE pixels when it fits."
  (or (and size (ignore-errors (split-window window (- size) side t)))
      (ignore-errors (split-window window nil side))))

(defun my/workspace--build (node window root)
  "Recreate layout NODE inside live WINDOW; return the window to select."
  (if (plist-get node :leaf)
      (my/workspace--restore-leaf node window root)
    (let* ((side (plist-get node :split))
           (horizontal (eq side 'right))
           (children (plist-get node :children))
           (sizes (or (plist-get node :sizes)
                      (make-list (length children) 1.0)))
           (windows (list window))
           (rest window))
      ;; Split off the remaining children first, then fill each part.
      (cl-loop for index from 1 below (length children)
               for total = (apply #'+ (nthcdr (1- index) sizes))
               for remaining = (apply #'+ (nthcdr index sizes))
               for pixels = (if horizontal (window-pixel-width rest) (window-pixel-height rest))
               for new = (my/workspace--split
                          rest (and (> total 0) (round (* pixels (/ remaining total))))
                          side)
               while new
               do (push new windows) (setq rest new))
      (let (selected)
        (cl-loop for child in children
                 for part in (nreverse windows)
                 do (let ((result (my/workspace--build child part root)))
                      (setq selected (or selected result))))
        selected))))

(defun my/workspace--show-only (window buffer)
  "Show BUFFER in WINDOW as its single tab.
`set-window-buffer' records the outgoing buffer as a tab, so clear after it."
  (set-window-buffer window buffer)
  (set-window-prev-buffers window nil)
  (set-window-next-buffers window nil))

(defun my/workspace--reset-frame (frame &optional directory)
  "Leave FRAME with one empty editor window in DIRECTORY, no sidebar or tabs."
  (my/workspace--hide-sidebar frame)
  (let ((window (seq-find (lambda (window) (not (window-parameter window 'window-side)))
                          (window-list frame 'no-minibuffer))))
    (delete-other-windows window)
    (my/workspace--show-only window (my/workspace-empty-buffer (or directory "~/")))
    window))

(defun my/workspace--apply-geometry (frame geometry)
  "Restore FRAME's saved size and position from GEOMETRY."
  (when (and geometry (display-graphic-p frame))
    (modify-frame-parameters
     frame (seq-filter #'cdr
                       (list (cons 'width (plist-get geometry :width))
                             (cons 'height (plist-get geometry :height))
                             (cons 'left (plist-get geometry :left))
                             (cons 'top (plist-get geometry :top)))))
    (set-frame-parameter frame 'fullscreen (plist-get geometry :fullscreen))))

(defun my/workspace--restore (frame root &optional files geometry)
  "Replace FRAME's windows with ROOT's saved workspace.
FILES are opened afterwards, the first one selected.  GEOMETRY non-nil also
restores the frame size and position."
  (my/workspace--cancel-queue frame)
  (unless (eq frame (selected-frame)) (select-frame frame))
  (let* ((state (my/workspace-read-data (my/workspace-file root)))
         (layout (plist-get state :layout))
         (sidebar (plist-get state :sidebar))
         (my/workspace--missing 0)
         (window (my/workspace--reset-frame frame root))
         selected)
    (set-frame-parameter frame 'my/workspace-root root)
    (set-frame-parameter frame 'my/workspace-saved nil)
    (set-frame-parameter frame 'my/xref-history (cons nil nil))
    (set-frame-parameter frame 'my/workspace-pending-history (plist-get state :history))
    (when geometry (my/workspace--apply-geometry frame (plist-get state :frame)))
    (if layout
        (setq selected (my/workspace--build layout window root))
      (my/workspace--show-only window (my/workspace-empty-buffer root)))
    (select-window (if (window-live-p selected) selected window))
    (my/workspace--refresh-tabs)
    (dolist (file (reverse files))
      (switch-to-buffer (find-file-noselect file)))
    (when (and (fboundp 'my/dirvish-show)
               (or (null state) (plist-get sidebar :visible)))
      (let ((dirvish-side-width (or (plist-get sidebar :width) dirvish-side-width)))
        (my/dirvish-show root)))
    (when-let* ((project (project-current nil root)))
      (project-remember-project project))
    (my/workspace-meta-update root :name (my/workspace-root-name root)
                              :opened (float-time))
    (if (my/workspace--frame-queued-p frame)
        (unless (timerp my/workspace--queue-timer)
          (setq my/workspace--queue-timer
                (run-with-timer 0.05 nil #'my/workspace--process-queue)))
      (my/workspace--apply-history frame))
    (message "%s"
             (if layout
                 (concat (format "已恢复 %s：%d 个窗口 · %d 个标签"
                                 (my/workspace-root-name root)
                                 (my/workspace--count layout 'windows)
                                 (my/workspace--count layout 'tabs))
                         (if (> my/workspace--missing 0)
                             (format "（%d 个文件已不存在，已跳过）" my/workspace--missing)
                           ""))
               (format "已打开 %s" (my/workspace-root-name root))))))

;;;; Commands

(defun my/workspace-frame-of (root)
  "Return a live frame already working on ROOT."
  (seq-find (lambda (frame) (equal (frame-parameter frame 'my/workspace-root) root))
            (frame-list)))

(defun my/workspace-open (root &optional files new-frame geometry)
  "Open project ROOT and restore its saved workspace.
FILES are opened afterwards, the first one selected.  With NEW-FRAME
\(interactively, a prefix argument) use a new frame.  A project already
open in another frame is focused instead.  GEOMETRY non-nil restores the
frame's saved size and position."
  (interactive (list (funcall project-prompter) nil current-prefix-arg))
  (setq root (my/workspace-normalize-root root))
  (let ((existing (my/workspace-frame-of root)))
    (if (and existing (not (eq existing (selected-frame))) (not new-frame))
        (progn
          (select-frame-set-input-focus existing)
          (dolist (file (reverse files))
            (switch-to-buffer (find-file-noselect file))))
      (let ((frame (if new-frame (make-frame) (selected-frame))))
        (my/workspace-save (selected-frame))
        (select-frame-set-input-focus frame)
        (my/workspace--restore frame root files (or geometry new-frame))))))

(defun my/workspace-switch-command ()
  "Open the project chosen by `project-switch-project' as a workspace."
  (interactive)
  (my/workspace-open project-current-directory-override))

(defun my/workspace-current-root ()
  "Return the selected frame's project root or signal a user error."
  (or (frame-parameter nil 'my/workspace-root)
      (user-error "当前窗口没有打开项目")))

(defun my/workspace-revert ()
  "Discard the current layout and return to the last saved workspace."
  (interactive)
  (my/workspace--restore (selected-frame) (my/workspace-current-root)))

(defun my/workspace-close ()
  "Save the project, kill its buffers and return to the start page."
  (interactive)
  (let* ((root (my/workspace-current-root))
         (project (project-current nil root)))
    (my/workspace-save nil t)
    (my/workspace--cancel-queue (selected-frame))
    (my/workspace--reset-frame (selected-frame))
    (dolist (parameter '(my/workspace-root my/workspace-saved
                         my/xref-history my/workspace-pending-history))
      (set-frame-parameter nil parameter nil))
    (when project (project-kill-buffers t project))
    (if (fboundp 'my/welcome-show)
        (my/welcome-show)
      (switch-to-buffer (my/workspace-empty-buffer "~/")))))

(defun my/workspace-save-before-kill (&optional _no-confirm project)
  "Save frames working on PROJECT before `project-kill-buffers' runs."
  (when-let* ((project (or project (project-current nil)))
              (root (my/workspace-normalize-root (project-root project))))
    (dolist (frame (frame-list))
      (when (equal (frame-parameter frame 'my/workspace-root) root)
        (my/workspace-save frame)))))

;;;; Startup

(defun my/workspace-startup ()
  "Open the project of command-line arguments, or show the start page.
A directory argument restores its project.  A file argument restores the
file's project and selects the file.  Without arguments the start page
fills the placeholder buffer init.el shows while loading."
  (let* ((directory (and (fboundp 'my/dirvish-take-startup-directory)
                         (my/dirvish-take-startup-directory)))
         (files (delete-dups
                 (delq nil (mapcar (lambda (window)
                                     (buffer-file-name (window-buffer window)))
                                   (cons (selected-window)
                                         (window-list nil 'no-minibuffer)))))))
    (cond
     (directory
      (my/workspace-open (my/workspace-root-of directory) nil nil t))
     (files
      (when-let* ((project (project-current nil (file-name-directory (car files)))))
        (my/workspace-open (project-root project) files nil t)))
     ((and (fboundp 'my/welcome-show)
           (member (buffer-name (window-buffer (selected-window)))
                   '("*Welcome*" "*scratch*")))
      (my/welcome-show)))))

;;;; Wiring

(setq project-switch-commands #'my/workspace-switch-command)
;; Replaces init-navigation's global storage; frames without a project
;; still use the global history.
(setq xref-history-storage #'my/workspace-xref-history)
(advice-add 'project-kill-buffers :before #'my/workspace-save-before-kill)

(when (timerp my/workspace--save-timer)
  (cancel-timer my/workspace--save-timer))
(setq my/workspace--save-timer (run-with-idle-timer 30 t #'my/workspace-save-all))
(add-hook 'kill-emacs-hook #'my/workspace-save-all)
(add-hook 'delete-frame-functions #'my/workspace-save)
(add-hook 'emacs-startup-hook #'my/workspace-startup)

(keymap-set project-prefix-map "k" #'my/workspace-close)
(keymap-set project-prefix-map "R" #'my/workspace-revert)

(provide 'init-workspace)
;;; init-workspace.el ends here
