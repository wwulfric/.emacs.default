;;; bottom-tools.el --- IntelliJ's Find and Problems tool windows -*- lexical-binding: t; -*-

;;; Commentary:
;; Two tool windows along the frame's bottom, drawn with tool-islands as
;; the Git tool windows are:
;;
;;   Find (s-3)      the usages Find Usages (M-<f7>) found, grouped by
;;                   folder and file; M-s-<down> and M-s-<up> step through
;;                   them from the editor.  Show Usages (M-s-<f7>) keeps the
;;                   popup beside the symbol.
;;   Problems (s-6)  the language server's diagnostics of the file being
;;                   edited, or of every open file (a).
;;
;; Like IntelliJ's bottom tool windows they take one place: showing one
;; hides the other, and the Git log.  Showing a tool window is the only
;; layout these write; refreshing their contents never resizes anything.
;;
;; This file loads when one of them is first used; init-find.el binds
;; their keys.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'xref)
(require 'magit-section)
(require 'tool-islands)
(require 'expui-icons)

(declare-function my/sidebar-status-line "init-sidebar" ())
(declare-function git-islands-log-hide "git-islands-log" (&optional frame))
(declare-function git-islands-log-window "git-islands-log" (&optional frame))
(declare-function lsp-bridge-find-references "lsp-bridge-ref" ())
(declare-function lsp-bridge-has-lsp-server-p "lsp-bridge" ())
(declare-function acm-backend-lsp-position-to-point "acm-backend-lsp" (position &optional buffer))
(defvar lsp-bridge-diagnostic-records)
(defvar my/lsp-locations-kind)

;;;; Bottom tool windows

(defcustom my/bottom-tool-height 0.3
  "Height of a bottom tool window, as a fraction of the frame."
  :type 'float
  :group 'tool-islands)

(defvar my/bottom-tool-modes '(my/find-mode my/problems-mode)
  "Modes of the tool windows that share the frame's bottom.")

(defun my/bottom-tool-window (mode &optional frame)
  "Return FRAME's window showing a buffer in MODE, or nil."
  (seq-find (lambda (window)
              (eq (buffer-local-value 'major-mode (window-buffer window)) mode))
            (window-list frame 'no-minibuffer)))

(defun my/bottom-tool-show (buffer)
  "Show BUFFER along the frame's bottom in place of the other tool windows.
Return its window."
  (let ((mode (buffer-local-value 'major-mode buffer)))
    (dolist (other my/bottom-tool-modes)
      (unless (eq other mode)
        (when-let* ((window (my/bottom-tool-window other)))
          (delete-window window))))
    (when (and (fboundp 'git-islands-log-window) (git-islands-log-window))
      (git-islands-log-hide)))
  (let ((window (display-buffer-in-side-window
                 buffer `((side . bottom) (slot . 0) (dedicated . t)
                          (window-height . ,my/bottom-tool-height)
                          (window-parameters (no-delete-other-windows . t))))))
    ;; A pixel of right fringe: without one a selected row, which fills the
    ;; window, would count as cut.  Compared first, so that showing the
    ;; window again writes no layout.
    (unless (equal (seq-take (window-fringes window) 2) '(0 1))
      (set-window-fringes window 0 1))
    window))

;; The Git log takes the same place.
(with-eval-after-load 'git-islands-log
  (advice-add 'git-islands-log-show :before
              (lambda (&rest _)
                (dolist (mode my/bottom-tool-modes)
                  (when-let* ((window (my/bottom-tool-window mode)))
                    (delete-window window))))))

(defun my/bottom-tool-toggle (mode show)
  "Focus the tool window in MODE, hide it when focused, or call SHOW.
SHOW returns the window it showed."
  (if-let* ((window (my/bottom-tool-window mode)))
      (if (eq window (selected-window))
          (progn (delete-window window) (my/bottom-tool-to-editor))
        (select-window window))
    (select-window (funcall show))))

(defun my/bottom-tool-to-editor ()
  "Select the editor window that was used last, as Escape does in IntelliJ."
  (interactive)
  (when-let* ((window (get-mru-window nil nil t)))
    (select-window window)))

(defun my/bottom-tool-hide ()
  "Hide the tool window at point and go back to the editor."
  (interactive)
  (let ((window (selected-window)))
    (my/bottom-tool-to-editor)
    (when (window-live-p window) (delete-window window))))

(defun my/bottom-tool-visit (file line column &optional keep-focus)
  "Show FILE at LINE and COLUMN in the editor; select it unless KEEP-FOCUS."
  (let ((tool (selected-window))
        (editor (or (get-mru-window nil nil t)
                    (user-error "No editor window"))))
    (with-selected-window editor
      (let ((buffer (or (and (bufferp file) file) (find-file-noselect file))))
        (switch-to-buffer buffer nil t)
        (widen)
        (goto-char (point-min))
        (forward-line (1- line))
        (move-to-column (max 0 column))
        (recenter)
        (pulse-momentary-highlight-one-line (point))))
    (select-window (if keep-focus tool editor))))

(defun my/bottom-tool-header (title detail buttons)
  "Return a header with TITLE, DETAIL dimmed, and BUTTONS while focused.
BUTTONS are as `tool-islands-toolbar' takes them."
  (let* ((toolbar (when (mode-line-window-selected-p) (tool-islands-toolbar buttons)))
         (room (- (window-body-width nil t)
                  (if toolbar (string-pixel-width toolbar) 0)
                  8 (tool-islands-line-end-inset)))
         (text (concat (propertize (concat " " title) 'face 'tool-islands-title)
                       (when detail
                         (propertize (concat "  " detail) 'face '(tool-islands-dim tool-islands-text))))))
    (concat (propertize " " 'face 'header-line 'display (tool-islands-header-space 0))
            (truncate-string-pixelwise text (max 0 room) (current-buffer) "…")
            (when toolbar (tool-islands-at-right toolbar (tool-islands-line-end))))))

(defvar-keymap my/bottom-tool-mode-map
  :parent magit-section-mode-map
  "TAB" #'tool-islands-toggle-section
  "<tab>" #'tool-islands-toggle-section
  "n" #'next-line
  "p" #'previous-line
  "q" #'my/bottom-tool-hide
  "<escape>" #'my/bottom-tool-to-editor
  "S-<escape>" #'my/bottom-tool-hide
  "s-=" #'tool-islands-expand-all
  "s--" #'tool-islands-collapse-all)

(define-derived-mode my/bottom-tool-mode magit-section-mode "Tool"
  "Base mode of the bottom tool windows."
  :interactive nil
  (setq-local magit-section-highlight-current nil
              magit-section-highlight-selection nil
              magit-section-visibility-indicators nil
              buffer-undo-list t
              mode-line-format (if (fboundp 'my/sidebar-status-line)
                                   '(:eval (my/sidebar-status-line))
                                 mode-line-format))
  (tool-islands-view-setup))

(defun my/bottom-tool-render (insert)
  "Draw the buffer again with INSERT, keeping point on the same row."
  (let* ((section (magit-current-section))
         (ident (and section (magit-section-ident section)))
         (line (line-number-at-pos))
         (inhibit-read-only t))
    (erase-buffer)
    (setq magit-root-section nil)
    (magit-insert-section (my/tool-root)
      (funcall insert))
    (tool-islands-draw-chevrons)
    (if-let* ((section (and ident (magit-get-section ident))))
        (goto-char (oref section start))
      (goto-char (point-min))
      (forward-line (1- line)))
    (dolist (window (get-buffer-window-list nil nil t))
      (set-window-point window (point)))
    (tool-islands-fit-rows)))

(defun my/bottom-tool-relative (file root)
  "Return FILE relative to ROOT when inside it, else abbreviated."
  (let ((file (expand-file-name file)))
    (if (and root (string-prefix-p (expand-file-name root) file))
        (file-relative-name file root)
      (abbreviate-file-name file))))

(defun my/bottom-tool-file-row (depth file count noun)
  "Insert FILE's row DEPTH deep, with COUNT NOUNs after its name."
  (tool-islands-row
   depth
   (tool-islands-icon (expui-icons-name-for-file (file-name-nondirectory file)))
   (tool-islands-gap)
   (tool-islands-fit
    (concat (file-name-nondirectory file)
            (propertize (format "  %d %s%s" count noun (if (= count 1) "" "s"))
                        'face 'tool-islands-dim))))
  (magit-insert-heading))

(defun my/bottom-tool-folder-row (depth name count noun)
  "Insert folder NAME's row DEPTH deep, with COUNT NOUNs after it."
  (tool-islands-row
   depth (tool-islands-icon "nodes/folder") (tool-islands-gap)
   (tool-islands-fit
    (concat name (propertize (format "  %d %s%s" count noun (if (= count 1) "" "s"))
                             'face 'tool-islands-dim))))
  (magit-insert-heading))

;;;; Find

;; An item is (FILE LINE COLUMN SUMMARY): SUMMARY is the line's code with
;; the match in `xref-match'.

(defvar my/find-title nil "What the Find tool window shows, as \"Usages of foo\".")
(defvar my/find-root nil "Directory the Find tool window's paths are relative to.")
(defvar my/find-items nil "The items the Find tool window lists.")

(defun my/find-buffer ()
  "Return the Find tool window's buffer.
Its name starts with a space, as the Git tool windows' do: it is no
editor buffer, and global Font Lock, which would take its faces away,
leaves it alone."
  (or (get-buffer " *Find*")
      (with-current-buffer (get-buffer-create " *Find*")
        (my/find-mode)
        (current-buffer))))

(defun my/find-header ()
  "Return the Find tool window's header."
  (my/bottom-tool-header
   "Find" my/find-title
   '(("general/up" my/find-previous-occurrence "Previous Occurrence (M-s-<up>)")
     ("general/down" my/find-next-occurrence "Next Occurrence (M-s-<down>)")
     ("general/expandAll" tool-islands-expand-all "Expand All (s-=)")
     ("general/collapseAll" tool-islands-collapse-all "Collapse All (s--)")
     ("general/hide" my/bottom-tool-hide "Hide (S-<escape>)"))))

(defvar-keymap my/find-mode-map
  :parent my/bottom-tool-mode-map
  "RET" #'my/find-visit
  "<f4>" #'my/find-visit
  "<double-mouse-1>" #'my/find-visit
  "SPC" #'my/find-preview
  "M-s-<down>" #'my/find-next-occurrence
  "M-s-<up>" #'my/find-previous-occurrence)

(define-derived-mode my/find-mode my/bottom-tool-mode "Find"
  "The usages a search found, by folder and file."
  :interactive nil
  (setq-local header-line-format '(:eval (tool-islands-header-line (my/find-header)))))

(defun my/find-insert-item (item depth)
  "Insert the row of usage ITEM, DEPTH deep."
  (pcase-let ((`(,file ,line ,_column ,summary) item))
    (magit-insert-section (my/find-usage (list file line (nth 2 item)))
      (tool-islands-row
       depth
       (propertize
        (concat (propertize (format "%d" line) 'face 'tool-islands-dim)
                (tool-islands-space 10)
                (tool-islands-fit (string-trim summary)))
        'my/find-item item)))))

(defun my/find-insert-file (file items depth)
  "Insert FILE's row DEPTH deep, then its usage ITEMS."
  (magit-insert-section (my/find-file file)
    (my/bottom-tool-file-row depth file (length items) "usage")
    (dolist (item items)
      (my/find-insert-item item (1+ depth)))))

(defun my/find-insert-node (node depth by-file)
  "Insert the folders and files of tree NODE, DEPTH deep.
BY-FILE maps a relative file name to its items."
  (dolist (child (nth 1 node))
    (let ((files (tool-islands-tree-items child)))
      (magit-insert-section (my/find-folder (car child))
        (my/bottom-tool-folder-row
         depth (car child)
         (apply #'+ (mapcar (lambda (file) (length (gethash file by-file))) files))
         "usage")
        (my/find-insert-node child (1+ depth) by-file))))
  (dolist (file (nth 2 node))
    (my/find-insert-file file (gethash file by-file) depth)))

(defun my/find-insert ()
  "Insert the Find tool window's rows."
  (if (null my/find-items)
      (tool-islands-row 0 (propertize "Nothing found" 'face 'tool-islands-dim))
    (let ((by-file (make-hash-table :test #'equal))
          (files nil))
      (dolist (item my/find-items)
        (let ((file (my/bottom-tool-relative (car item) my/find-root)))
          (unless (gethash file by-file) (push file files))
          (puthash file (append (gethash file by-file) (list item)) by-file)))
      (dolist (file files)
        (puthash file (sort (gethash file by-file)
                            (lambda (a b) (or (< (nth 1 a) (nth 1 b))
                                              (and (= (nth 1 a) (nth 1 b))
                                                   (< (nth 2 a) (nth 2 b))))))
                 by-file))
      (magit-insert-section (my/find-group 'usages)
        (tool-islands-row
         0 (tool-islands-fit
            (concat (propertize "Usages" 'face 'tool-islands-title)
                    (propertize (format "  %d results" (length my/find-items))
                                'face 'tool-islands-dim))))
        (magit-insert-heading)
        (my/find-insert-node (tool-islands-tree-build files #'identity) 1 by-file)))))

(defun my/find-show (title items &optional root)
  "Show ITEMS in the Find tool window under TITLE; return its window.
ITEMS are (FILE LINE COLUMN SUMMARY); paths show relative to ROOT,
the current project's by default."
  (let ((root (or root (when-let* ((project (project-current))) (project-root project))
                  default-directory))
        (buffer (my/find-buffer)))
    (setq my/find-title title
          my/find-root root
          my/find-items items)
    (with-current-buffer buffer
      (setq default-directory root)
      (my/bottom-tool-render #'my/find-insert)
      (goto-char (point-min))
      ;; The first usage is selected, as IntelliJ selects it.
      (my/find--step 1 t))
    (let ((window (my/bottom-tool-show buffer)))
      (set-window-point window (with-current-buffer buffer (point)))
      window)))

(defun my/find-from-xrefs (xrefs)
  "Return Find items for XREFS, leaving out those not in a file."
  (delq nil
        (mapcar (lambda (xref)
                  (let ((location (xref-item-location xref)))
                    (when (xref-file-location-p location)
                      (list (xref-file-location-file location)
                            (xref-file-location-line location)
                            (xref-file-location-column location)
                            (xref-item-summary xref)))))
                xrefs)))

(defun my/find-item-at-point ()
  "Return the usage item of the row at point, or nil."
  (get-text-property (pos-bol) 'my/find-item))

(defun my/find-visit (&optional keep-focus)
  "Go to the usage at point, or fold or unfold the file or folder there.
KEEP-FOCUS non-nil stays in the Find window."
  (interactive)
  (if-let* ((item (my/find-item-at-point)))
      (pcase-let ((`(,file ,line ,column ,_) item))
        (my/bottom-tool-visit file line column keep-focus))
    (tool-islands-toggle-section)))

(defun my/find-preview ()
  "Show the usage at point in the editor, staying in the Find window."
  (interactive)
  (my/find-visit t))

(defun my/find--step (direction &optional here)
  "Move to the next usage row in DIRECTION, 1 or -1, unfolding as needed.
HERE non-nil accepts the row at point.  Return non-nil if one was found."
  (let ((start (point))
        found)
    (unless here (forward-line direction))
    (while (and (not found) (not (if (> direction 0) (eobp) (bobp))))
      (if (my/find-item-at-point)
          (setq found t)
        (forward-line direction)))
    (unless found
      (setq found (my/find-item-at-point)))
    (if (not found)
        (goto-char start)
      ;; A folded folder hides the row: unfold the sections around it.
      (when-let* ((section (magit-current-section)))
        (let ((parent (oref section parent)))
          (while parent
            (when (oref parent hidden)
              (magit-section-show parent)
              (tool-islands-draw-chevron parent))
            (setq parent (oref parent parent))))))
    found))

(defun my/find-occurrence (direction)
  "Go to the usage after the selected one in DIRECTION, from anywhere."
  (let ((buffer (get-buffer " *Find*")))
    (unless (and buffer (buffer-local-value 'my/find-items buffer))
      (user-error "No usages to go through"))
    (let ((window (or (get-buffer-window buffer)
                      (my/bottom-tool-show buffer)))
          (focus (selected-window)))
      (with-selected-window window
        (unless (my/find--step direction)
          (user-error "No more usages"))
        (tool-islands-highlight))
      (pcase-let ((`(,file ,line ,column ,_)
                   (with-current-buffer buffer (my/find-item-at-point))))
        (with-selected-window window
          (my/bottom-tool-visit file line column t))
        (select-window (if (eq focus window) window
                         (or (get-mru-window nil nil t) focus)))))))

(defun my/find-next-occurrence ()
  "Go to the next usage the Find tool window lists."
  (interactive)
  (my/find-occurrence 1))

(defun my/find-previous-occurrence ()
  "Go to the previous usage the Find tool window lists."
  (interactive)
  (my/find-occurrence -1))

(defun my/find-toggle ()
  "Focus the Find tool window; hide it when already focused."
  (interactive)
  (my/bottom-tool-toggle 'my/find-mode
                         (lambda () (my/bottom-tool-show (my/find-buffer)))))

;;;;; Find Usages

;; Language servers answer through lsp-bridge's reference list, which
;; init-lsp.el turns into xrefs for the popup beside the symbol; Find Usages
;; sends them here instead.  Without a server, xref's own backends answer.

(defvar my/find--usages nil
  "Non-nil while the next locations from lsp-bridge go to the Find window.")

(defun my/find-usages ()
  "List the usages of the symbol at point in the Find tool window."
  (interactive)
  (let ((symbol (or (thing-at-point 'symbol t) "")))
    (if (and (bound-and-true-p lsp-bridge-mode) (lsp-bridge-has-lsp-server-p))
        (progn
          (setq my/find--usages (format "Usages of %s" symbol))
          (lsp-bridge-find-references))
      (let ((xref-show-xrefs-function
             (lambda (fetcher _alist)
               (select-window
                (my/find-show (format "Usages of %s" symbol)
                              (my/find-from-xrefs (funcall fetcher)))))))
        (xref-find-references (or (xref-backend-identifier-at-point (xref-find-backend))
                                  (user-error "No symbol at point")))))))

(defun my/find--popup-usages (original content counter position)
  "Send lsp-bridge's locations to the Find window after Find Usages.
Otherwise call ORIGINAL with CONTENT, COUNTER and POSITION."
  (let ((title my/find--usages))
    (setq my/find--usages nil)
    (if-let* ((items (and title (> counter 0)
                          (my/lsp-locations-parse content))))
        (select-window (my/find-show title (my/find-from-xrefs items)))
      (when title (message "No usages found"))
      (unless title
        (funcall original content counter position)))))

(defun my/find--forget-usages (&rest _)
  "Let locations asked for by any other command go to the popup."
  (unless (eq this-command 'my/find-usages)
    (setq my/find--usages nil)))

(with-eval-after-load 'init-lsp
  (declare-function my/lsp-locations-parse "init-lsp" (content))
  (advice-add 'lsp-bridge-references--popup :around #'my/find--popup-usages)
  (advice-add 'lsp-bridge-find-references :before #'my/find--forget-usages)
  (advice-add 'lsp-bridge-find-impl :before #'my/find--forget-usages))

;;;; Problems

;; A problem is (BUFFER LINE COLUMN SEVERITY MESSAGE SOURCE), LINE from 1.

(defvar my/problems-all nil "Non-nil lists every open file's problems, not the edited one's.")
(defvar my/problems-file nil "Buffer whose problems the Problems window lists.")
(defvar my/problems--timer nil)

(defconst my/problems-severities
  '((1 "status/error" "error") (2 "status/warning" "warning")
    (3 "status/info" "info") (4 "status/info" "hint"))
  "LSP severities: their icons and names.")

(defun my/problems-buffer ()
  "Return the Problems tool window's buffer."
  (or (get-buffer " *Problems*")
      (with-current-buffer (get-buffer-create " *Problems*")
        (my/problems-mode)
        (current-buffer))))

(defun my/problems-of (buffer)
  "Return the problems lsp-bridge reported for BUFFER, in order."
  (with-current-buffer buffer
    (let ((problems
           (mapcar (lambda (diagnostic)
                     (let* ((start (plist-get (plist-get diagnostic :range) :start)))
                       (list buffer
                             (1+ (plist-get start :line))
                             (plist-get start :character)
                             (or (plist-get diagnostic :severity) 1)
                             (car (split-string (or (plist-get diagnostic :message) "") "\n"))
                             (plist-get diagnostic :source))))
                   (bound-and-true-p lsp-bridge-diagnostic-records))))
      (sort problems (lambda (a b) (or (< (nth 3 a) (nth 3 b))
                                       (and (= (nth 3 a) (nth 3 b))
                                            (< (nth 1 a) (nth 1 b)))))))))

(defun my/problems-buffers ()
  "Return the buffers the Problems window lists."
  (if my/problems-all
      (seq-filter (lambda (buffer)
                    (and (buffer-file-name buffer)
                         (buffer-local-value 'lsp-bridge-diagnostic-records buffer)))
                  (buffer-list))
    (and (buffer-live-p my/problems-file) (list my/problems-file))))

(defun my/problems-count (problems)
  "Return a summary of PROBLEMS by severity, as \"2 errors, 1 warning\"."
  (let (parts)
    (pcase-dolist (`(,severity ,_ ,name) (reverse my/problems-severities))
      (let ((count (seq-count (lambda (problem) (= (nth 3 problem) severity)) problems)))
        (when (> count 0)
          (push (format "%d %s%s" count name (if (= count 1) "" "s")) parts))))
    (string-join parts ", ")))

(defun my/problems-header ()
  "Return the Problems tool window's header."
  (my/bottom-tool-header
   "Problems"
   (if my/problems-all "Open Files"
     (if (buffer-live-p my/problems-file) (buffer-name my/problems-file) "File"))
   `((,(if my/problems-all "actions/groupByFile" "general/filter") my/problems-toggle-scope
      ,(if my/problems-all "Show the edited file only (a)" "Show every open file (a)"))
     ("general/expandAll" tool-islands-expand-all "Expand All (s-=)")
     ("general/collapseAll" tool-islands-collapse-all "Collapse All (s--)")
     ("general/hide" my/bottom-tool-hide "Hide (S-<escape>)"))))

(defvar-keymap my/problems-mode-map
  :parent my/bottom-tool-mode-map
  "RET" #'my/problems-visit
  "<f4>" #'my/problems-visit
  "<double-mouse-1>" #'my/problems-visit
  "SPC" #'my/problems-preview
  "a" #'my/problems-toggle-scope
  "g" #'my/problems-refresh)

(define-derived-mode my/problems-mode my/bottom-tool-mode "Problems"
  "The language server's diagnostics, by file."
  :interactive nil
  (setq-local header-line-format '(:eval (tool-islands-header-line (my/problems-header)))))

(defun my/problems-insert ()
  "Insert the Problems tool window's rows."
  (let ((buffers (my/problems-buffers))
        (any nil))
    (dolist (buffer buffers)
      (when-let* ((problems (my/problems-of buffer)))
        (setq any t)
        (magit-insert-section (my/problems-file (buffer-file-name buffer))
          (tool-islands-row
           0
           (tool-islands-icon (expui-icons-name-for-file (buffer-name buffer)))
           (tool-islands-gap)
           (tool-islands-fit
            (concat (file-name-nondirectory (buffer-file-name buffer))
                    (propertize (concat "  " (abbreviate-file-name
                                              (directory-file-name
                                               (file-name-directory (buffer-file-name buffer)))))
                                'face 'tool-islands-dim)
                    (propertize (concat "  " (my/problems-count problems))
                                'face 'tool-islands-dim))))
          (magit-insert-heading)
          (dolist (problem problems)
            (pcase-let ((`(,_ ,line ,column ,severity ,message ,source) problem))
              (magit-insert-section (my/problem (list (buffer-file-name buffer) line column message))
                (tool-islands-row
                 1
                 (propertize
                  (concat (expui-icons-icon (or (nth 1 (assq severity my/problems-severities))
                                                "status/info"))
                          (tool-islands-gap)
                          (tool-islands-fit
                           (concat message
                                   (when source
                                     (propertize (concat "  " source) 'face 'tool-islands-dim))
                                   (propertize (format "  :%d" line) 'face 'tool-islands-dim))))
                  'my/problem problem))))))))
    (unless any
      (tool-islands-row
       0 (propertize (cond ((not buffers) "No file to inspect")
                           (my/problems-all "No problems in open files")
                           (t "No problems in this file"))
                     'face 'tool-islands-dim)))))

(defun my/problems-refresh ()
  "List the problems again."
  (interactive)
  (when-let* ((buffer (get-buffer " *Problems*")))
    (with-current-buffer buffer
      (my/bottom-tool-render #'my/problems-insert))))

(defun my/problems-schedule (&rest _)
  "Draw the Problems window again once Emacs is idle, if it is shown."
  (when (and (get-buffer " *Problems*") (get-buffer-window " *Problems*" t)
             (not (timerp my/problems--timer)))
    (setq my/problems--timer
          (run-with-idle-timer 0.1 nil
                               (lambda ()
                                 (setq my/problems--timer nil)
                                 (my/problems-refresh))))))

(defun my/problems-follow (&rest _)
  "List the problems of the file now being edited."
  (let ((buffer (window-buffer (selected-window))))
    (when (and (buffer-file-name buffer)
               (not (eq buffer my/problems-file)))
      (setq my/problems-file buffer)
      (unless my/problems-all
        (my/problems-schedule)))))

(add-hook 'window-buffer-change-functions #'my/problems-follow)
(add-hook 'window-selection-change-functions #'my/problems-follow)
(add-hook 'lsp-bridge-diagnostic-update-hook #'my/problems-schedule)

(defun my/problems-toggle-scope ()
  "Switch between the edited file's problems and every open file's."
  (interactive)
  (setq my/problems-all (not my/problems-all))
  (my/problems-refresh))

(defun my/problems-visit (&optional keep-focus)
  "Go to the problem at point, or fold or unfold the file there.
KEEP-FOCUS non-nil stays in the Problems window."
  (interactive)
  (if-let* ((problem (get-text-property (pos-bol) 'my/problem)))
      (pcase-let ((`(,buffer ,line ,column . ,_) problem))
        (if (buffer-live-p buffer)
            (my/bottom-tool-visit buffer line column keep-focus)
          (user-error "The file was closed")))
    (tool-islands-toggle-section)))

(defun my/problems-preview ()
  "Show the problem at point in the editor, staying in the Problems window."
  (interactive)
  (my/problems-visit t))

(defun my/problems-toggle ()
  "Focus the Problems tool window; hide it when already focused."
  (interactive)
  (unless (my/bottom-tool-window 'my/problems-mode)
    (let ((buffer (window-buffer (get-mru-window nil nil nil))))
      (when (buffer-file-name buffer)
        (setq my/problems-file buffer))))
  (my/bottom-tool-toggle 'my/problems-mode
                         (lambda ()
                           (let ((buffer (my/problems-buffer)))
                             (with-current-buffer buffer
                               (my/bottom-tool-render #'my/problems-insert))
                             (my/bottom-tool-show buffer)))))

(provide 'bottom-tools)
;;; bottom-tools.el ends here
