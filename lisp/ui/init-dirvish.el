;;; init-dirvish.el --- Project file sidebar -*- lexical-binding: t; -*-

;;; Commentary:
;; Dirvish and compat are vendored as Git submodules under lisp/.
;; Keep project navigation separate from lsp-bridge's language server roots.

;;; Code:

(require 'project)
(require 'mwheel)
(require 'dirvish)
(require 'dirvish-side)
(require 'expui-icons)
(require 'ui-layout)

;; Dirvish sorts with GNU ls options such as --sort, and only GNU ls lists
;; folders first.  macOS ships BSD ls, so use coreutils' gls when it is
;; installed (brew install coreutils).  The shell's PATH is imported after
;; this file loads, hence the Homebrew locations.
(defvar my/dirvish-gnu-ls nil
  "Non-nil when `insert-directory-program' accepts GNU ls options.")
(setq my/dirvish-gnu-ls
      (pcase system-type
        ('gnu/linux t)
        ('darwin
         (when-let* ((gls (or (executable-find "gls")
                              (seq-find #'file-executable-p
                                        '("/opt/homebrew/bin/gls"
                                          "/usr/local/bin/gls")))))
           (setq insert-directory-program gls)
           t))))
;; BSD ls also lacks --dired.
(setq dired-use-ls-dired my/dirvish-gnu-ls)

;; Show dotfiles, but omit the synthetic . and .. entries.
(setq dired-listing-switches
      (if my/dirvish-gnu-ls "-lA --group-directories-first" "-lA"))

;; Skip the mode/header-line spacer image so font metrics set the height.
;; A width of 0 merely hides the image and still reserves its fixed height.
(setq dirvish-mode-line-bar-image-width nil)

(defun my/dirvish-side-bars (dv)
  "Give side session DV the New UI tool window header and status bar.
The status bar is empty: it only continues the editor's along the frame's
bottom edge.  Dirvish's composer measures each icon as one column, so it
cannot right-align the header's toolbar."
  (when (eq (dv-type dv) 'side)
    (setf (dv-size-fixed dv) nil
          (dv-mode-line dv) '(:eval (when (display-graphic-p)
                                      (my/ui-mode-line-space 0)))
          (dv-header-line dv) '(:eval (my/dirvish-side-header)))))
;; Sessions recompose their bars on creation and on every revert.
(advice-add 'dirvish--check-dependencies :after #'my/dirvish-side-bars)

;; Share tab-line's font metrics and vertical padding, only in the sidebar.
(require 'face-remap)
(defvar-local my/dirvish-header-face-cookie nil)
(defvar-local my/dirvish-font-face-cookie nil)

(defconst my/dirvish-state-width 16
  "Pixel width of the sidebar's disclosure column, matching the chevrons.")

(defvar my/dirvish-row-map
  (let ((map (make-sparse-keymap)))
    (define-key map [down-mouse-1] #'my/dirvish-mouse-press)
    (define-key map [mouse-1] #'my/dirvish-mouse-open)
    (define-key map [mouse-2] #'my/dirvish-mouse-open)
    map)
  "Mouse actions shared by sidebar names, icons and disclosure arrows.")

(defun my/dirvish-clickable (text &optional name)
  "Give sidebar TEXT a hand pointer, mouse actions and tooltip NAME."
  (propertize text 'pointer 'hand 'mouse-face nil
              'local-map my/dirvish-row-map 'help-echo name))

(defun my/dirvish-align-subtree-state (result)
  "Draw RESULT's disclosure state as a New UI chevron of fixed width.
PT Mono lacks ▸ and ▾; their fallback font (Arial Unicode MS) makes
directory rows taller and renders wider than Emacs measures."
  ;; Don't wait for `my/dirvish-setup': restored sidebars render before it.
  (when (and (display-images-p) (eq (car-safe result) 'ov))
    (when-let* ((ov (cdr result))
                (text (overlay-get ov 'after-string)))
      (let ((row-face (get-text-property 0 'face text))
            (state (pcase (substring-no-properties text)
                     ("▾" 'expanded) ("▸" 'collapsed))))
        ;; Keep only the row highlight; the state face's font sets height.
        (setq row-face (if (listp row-face)
                           (remq 'dirvish-subtree-state row-face)
                         (unless (eq row-face 'dirvish-subtree-state) row-face)))
        (overlay-put ov 'after-string
                     (my/dirvish-clickable
                      (propertize " "
                                  'face (cons 'my/dirvish-neutral-icon
                                              (ensure-list row-face))
                                  'display
                                  (pcase state
                                    ('expanded (expui-icons-image "general/chevronDown"))
                                    ('collapsed (expui-icons-image "general/chevronRight"))
                                    (_ `(space :width (,my/dirvish-state-width)))))
                      (save-excursion
                        (goto-char (overlay-end ov))
                        (dired-get-filename 'no-dir t)))))))
  result)

(with-eval-after-load 'dirvish-subtree
  ;; The ▸/▾ strings only mark the state; the advice draws chevrons.
  (customize-set-variable 'dirvish-subtree-state-style 'arrow)
  ;; As in the New UI, indentation alone shows depth; no guide lines.
  ;; Set it globally: the sidebar expands to the opened file before
  ;; `my/dirvish-setup' could set a buffer-local prefix.
  (customize-set-variable 'dirvish-subtree-prefix "  ")
  (advice-add 'dirvish-attribute-subtree-state-rd :filter-return
              #'my/dirvish-align-subtree-state))

(defface my/dirvish-file-name
  '((t (:inherit my/ui-font :height 1.0)))
  "Proportional sidebar text." :group 'dirvish)
(defface my/dirvish-project-title '((t (:inherit default)))
  "Sidebar project title." :group 'dirvish)
(defface my/dirvish-neutral-icon '((t (:inherit shadow)))
  "Folder and ordinary file icons." :group 'dirvish)
(defface my/dirvish-source-icon '((t (:inherit link)))
  "Source file icons." :group 'dirvish)

(defvar my/dirvish-source-icons
  '("xml" "c" "h" "cpp" "Csharp" "java" "kotlin" "kotlinScript" "groovy"
    "language/scala" "language/php" "python" "perl" "javaScript" "typeScript"
    "swiftLang")
  "Icons drawn in the accent color when `expui-icons-style' is `mono'.")

(dirvish-define-attribute my-sidebar-icon
  "New UI file icons; source files use the accent in `mono' style."
  :when (expui-icons-svg-p)
  :width 3
  (let* ((name (expui-icons-name-for-file f-str (eq (car f-type) 'dir)))
         (face (if (member name my/dirvish-source-icons)
                   'my/dirvish-source-icon
                 'my/dirvish-neutral-icon))
         (ov (make-overlay (1- f-beg) f-beg)))
    ;; On the selected row the highlight supplies only the background.
    (overlay-put ov 'after-string
                 (my/dirvish-clickable
                  (concat (expui-icons-icon name :face (if hl-face
                                                          (list face hl-face)
                                                        face))
                         (propertize " " 'display '(space :width (6))
                                     'face hl-face)) f-str))
    `(ov . ,ov)))

(defvar-local my/dirvish-name-cache nil)
(defvar-local my/dirvish-name-metrics nil)

(defun my/dirvish-fit-name (name depth)
  "Fit NAME at subtree DEPTH, reusing pixel measurements while scrolling."
  (let ((context (list (window-body-width nil t)
                       (copy-tree face-remapping-alist)
                       (face-attribute 'default :font)
                       (face-attribute 'my/dirvish-file-name :height)
                       expui-icons-height dirvish-subtree-prefix)))
    (unless (equal context (car my/dirvish-name-metrics))
      (setq my/dirvish-name-metrics
            (list context
                  (string-pixel-width
                   (propertize dirvish-subtree-prefix 'face 'dirvish-subtree-guide))
                  (string-pixel-width "  "))
            my/dirvish-name-cache (make-hash-table :test #'equal)))
    (let ((key (cons name depth)))
      (or (gethash key my/dirvish-name-cache)
          (let* ((width (max 0 (- (car context)
                                 (* depth (nth 1 my/dirvish-name-metrics))
                                 my/dirvish-state-width expui-icons-height 6
                                 (nth 2 my/dirvish-name-metrics) 12)))
                 (text (truncate-string-pixelwise name width (current-buffer) "…")))
            (when (> (hash-table-count my/dirvish-name-cache) 2048)
              (clrhash my/dirvish-name-cache))
            (puthash key text my/dirvish-name-cache))))))

(dirvish-define-attribute my-sidebar-name
  "Fit proportional filenames inside the sidebar before native clipping."
  :when (display-graphic-p)
  (let* ((depth (save-excursion
                  (goto-char f-beg)
                  (dirvish-subtree--depth)))
         (text (my/dirvish-fit-name f-str depth))
         (ov (make-overlay f-beg f-end)))
    ;; Tooltip properties must also be on the replacement display string.
    (unless (equal text f-str)
      (overlay-put ov 'display (my/dirvish-clickable text f-str)))
    (overlay-put ov 'pointer 'hand)
    ;; Suppress Dired's own text hover too; selection owns the row background.
    (overlay-put ov 'mouse-face '(:inherit nil))
    (overlay-put ov 'help-echo f-str)
    `(ov . ,ov)))

(defun my/dirvish-render-if-changed (render window &optional selected)
  "Call RENDER for WINDOW only when its sidebar rows need updating.
Pixel scrolling within a row should reuse its icons and measured names."
  (with-current-buffer (window-buffer window)
    (if (not (when-let* ((session (dirvish-curr)))
               (eq (dv-type session) 'side)))
        (funcall render window selected)
      (let ((state (list (current-buffer) (buffer-chars-modified-tick)
                         (window-start window) (window-point window)
                         (window-body-width window t) (window-body-height window t)
                         (eq window (or selected (frame-selected-window)))
                         (copy-tree face-remapping-alist)
                         (face-attribute 'default :font)
                         (face-attribute 'my/dirvish-file-name :height)
                         expui-icons-style expui-icons-height
                         (face-attribute 'my/dirvish-source-icon :foreground)
                         (face-attribute 'my/dirvish-neutral-icon :foreground)
                         (frame-parameter nil 'background-color)
                         (dirvish-prop :attrs))))
        (unless (equal state (window-parameter window 'my/dirvish-render-state))
          (funcall render window selected)
          (set-window-parameter window 'my/dirvish-render-state state))))))

(advice-add 'dirvish--render-attrs :around #'my/dirvish-render-if-changed)

;;;; Sidebar header: the toolbar appears only while the sidebar is in use

;; Emacs reports no mouse enter or leave events for windows, so poll the
;; pointer and redraw a sidebar's header only when it enters or leaves one.
(defvar my/dirvish-side-hovered nil "The sidebar window under the mouse.")
(defvar my/dirvish-side-hover-timer nil)

(defun my/dirvish-side-track-hover ()
  "Note which sidebar the mouse is over and redraw the bars that change."
  (let* ((position (mouse-pixel-position))
         (window (and (frame-live-p (car position)) (cadr position)
                      (window-at-x-y (cadr position) (cddr position)
                                     (car position))))
         (hovered (and window
                       (with-current-buffer (window-buffer window)
                         (when-let* ((session (dirvish-curr)))
                           (eq (dv-type session) 'side)))
                       window)))
    (unless (eq hovered my/dirvish-side-hovered)
      (dolist (changed (list my/dirvish-side-hovered hovered))
        (when (window-live-p changed)
          (with-current-buffer (window-buffer changed)
            (force-mode-line-update))))
      (setq my/dirvish-side-hovered hovered))))

(when (timerp my/dirvish-side-hover-timer)
  (cancel-timer my/dirvish-side-hover-timer))
(setq my/dirvish-side-hover-timer
      (when (display-graphic-p)
        (run-with-timer 0.15 0.15 #'my/dirvish-side-track-hover)))

(defun my/dirvish-side-active-p ()
  "Return non-nil if the sidebar whose header is drawn is focused or hovered.
Headers are drawn with their window temporarily selected."
  (or (mode-line-window-selected-p)
      (eq (selected-window) my/dirvish-side-hovered)))

(defface my/dirvish-toolbar-hover '((t (:inherit highlight)))
  "Sidebar header button under the mouse." :group 'dirvish)

(defconst my/dirvish-toolbar-padding 4
  "Pixels on each side of a toolbar icon.")

(defconst my/dirvish-toolbar-margin 6
  "Pixels between the toolbar and the sidebar's right edge.")

(defvar my/dirvish-side-buttons
  '(("general/add" my/dirvish-side-new-menu "New")
    ("general/locate" my/dirvish-side-locate "Select Opened File")
    ("general/expandAll" my/dirvish-side-expand-selected "Expand Selected")
    ("general/collapseAll" dirvish-subtree-clear "Collapse All")
    ("general/moreVertical" my/dirvish-side-options-menu "Options")
    ("general/hide" dirvish-quit "Hide"))
  "Sidebar toolbar buttons as (ICON ACTION HELP).
ACTION is a command, or a function called with the click event.")

(defun my/dirvish-side-button (action help &rest strings)
  "Return STRINGS as a header button running ACTION, with tooltip HELP.
ACTION runs in the clicked sidebar; see `my/dirvish-side-buttons'."
  (let ((map (make-sparse-keymap)))
    ;; Act on press, like the status bar's menu; this also keeps the press
    ;; from starting a header-line window resize.
    (define-key map [header-line down-mouse-1]
      (lambda (event)
        (interactive "e")
        (select-window (posn-window (event-start event)))
        (if (commandp action)
            (call-interactively action)
          (funcall action event))))
    (define-key map [header-line mouse-1] #'ignore)
    (propertize (apply #'concat strings)
                'local-map map 'help-echo help 'pointer 'hand
                'mouse-face 'my/dirvish-toolbar-hover)))

(defun my/dirvish-side-toolbar ()
  "Return the sidebar's toolbar buttons."
  (let ((pad (propertize " " 'display
                         `(space :width (,my/dirvish-toolbar-padding)))))
    (mapconcat (pcase-lambda (`(,icon ,action ,help))
                 (my/dirvish-side-button
                  action help pad
                  (expui-icons-icon icon :face 'my/dirvish-neutral-icon) pad))
               my/dirvish-side-buttons "")))

(defun my/dirvish-side-header ()
  "Return the sidebar's view title, and its toolbar while in use.
As in a New UI tool window, the toolbar shows when focused or hovered."
  (let* ((toolbar (when (my/dirvish-side-active-p)
                    (concat (my/dirvish-side-toolbar)
                            (propertize " " 'display
                                        `(space :width (,my/dirvish-toolbar-margin))))))
         (toolbar-width (if toolbar (string-pixel-width toolbar) 0))
         (chevron (concat (propertize " " 'display '(space :width (2)))
                          (expui-icons-icon "general/chevronDown"
                                            :face 'my/dirvish-neutral-icon)))
         ;; As in JetBrains, the title bar names the project; this is the
         ;; Project view, whose menu switches between projects.
         (name (propertize " Project" 'face 'my/dirvish-project-title))
         ;; Shorten the title rather than let the window clip the toolbar.
         (room (- (window-body-width nil t) toolbar-width
                  (string-pixel-width chevron) 8 (my/ui-line-end-inset))))
    (concat (propertize " " 'face 'header-line 'display (my/ui-header-space 0))
            (my/dirvish-side-button
             #'my/dirvish-side-project-menu "Switch Project"
             (truncate-string-pixelwise name room (current-buffer) "…")
             chevron)
            (when toolbar
              (my/ui-at-right toolbar (my/ui-line-end))))))

(defun my/dirvish-side-in-editor (function &rest args)
  "Call FUNCTION with ARGS, or interactively, from the last editor window.
The sidebar's window is dedicated, so it cannot show other buffers."
  (when-let* ((window (get-mru-window nil nil t)))
    (select-window window))
  (if args (apply function args) (call-interactively function)))

(declare-function my/workspace-root-name "init-workspace" (root))

(defun my/dirvish-side-project-menu (event)
  "Pop up recent projects at EVENT, marking the frame's current one."
  (let ((current (frame-parameter nil 'my/workspace-root))
        (projects (and (fboundp 'my/workspace-projects)
                       (seq-take (my/workspace-projects) 10))))
    (popup-menu
     `("Projects"
       ,@(mapcar (lambda (root)
                   (vector (my/workspace-root-name root)
                           `(my/dirvish-side-in-editor #'my/workspace-open ,root)
                           :style 'radio :selected (equal root current)))
                 projects)
       ,@(and projects '("---"))
       ["Open Directory…" (my/dirvish-side-in-editor #'my/dirvish-open-directory)])
     event)))

(defun my/dirvish-side-new-menu (event)
  "Pop up commands at EVENT creating entries in the directory at point."
  (popup-menu '("New"
                ["File…" dired-create-empty-file]
                ["Directory…" dired-create-directory])
              event))

(defun my/dirvish-side-locate ()
  "Select the last editor window's file in the sidebar."
  (interactive)
  (let ((file (when-let* ((window (get-mru-window nil nil t)))
                (buffer-file-name (window-buffer window)))))
    (cond ((not file) (message "No file is open in the editor"))
          ((not (file-in-directory-p file default-directory))
           (message "%s is not in %s" (file-name-nondirectory file)
                    (abbreviate-file-name default-directory)))
          (t (dirvish-subtree-expand-to file)))))

(defvar my/dirvish-side-expand-limit 30
  "Most directories one Expand Selected lists; each starts a process.")

(defun my/dirvish-side-expand-selected ()
  "Expand the directory at point and its subdirectories, up to a limit."
  (interactive)
  (let ((budget my/dirvish-side-expand-limit))
    (cl-labels
        ((directory-p ()
           (when-let* ((file (dired-get-filename nil t)))
             ;; A symlink may lead back into the tree being expanded.
             (and (file-directory-p file) (not (file-symlink-p file)))))
         (expand ()
           (let ((depth (dirvish-subtree--depth)))
             (unless (dirvish-subtree--expanded-p)
               (condition-case nil
                   (progn (dirvish-subtree--insert) (cl-decf budget))
                 (error nil)))
             (save-excursion
               (while (and (> budget 0)
                           (zerop (forward-line 1))
                           (> (dirvish-subtree--depth) depth))
                 (when (and (= (dirvish-subtree--depth) (1+ depth))
                            (directory-p))
                   (expand)))))))
      (if (directory-p) (expand) (message "Select a directory first")))
    (when (<= budget 0)
      (message "Expanded %d directories; deeper ones stay collapsed"
               my/dirvish-side-expand-limit))))

(defun my/dirvish-side-relist (remove &optional add)
  "Relist the sidebar without switches matching REMOVE, then with ADD."
  (setq dired-actual-switches
        (string-join (append (seq-remove (lambda (switch)
                                           (string-match-p remove switch))
                                         (split-string dired-actual-switches))
                             (and add (list add)))
                     " "))
  (revert-buffer))

(defconst my/dirvish-side-sorts
  '(("Name" nil) ("Modification Time" "--sort=time") ("Size" "--sort=size")
    ("Type" "--sort=extension"))
  "Sidebar sort orders as (LABEL SWITCH); GNU ls sorts by name by default.")

(defun my/dirvish-side-options-menu (event)
  "Pop up the sidebar's sort and listing options at EVENT."
  (let* ((switches (split-string dired-actual-switches))
         (sort (seq-find (lambda (switch) (string-prefix-p "--sort=" switch))
                         switches))
         (toggle (lambda (label switch)
                   (let ((on (member switch switches)))
                     (vector label
                             `(my/dirvish-side-relist
                               ,(concat "\\`" (regexp-quote switch) "\\'")
                               ,(unless on switch))
                             :style 'toggle :selected (and on t)
                             :active my/dirvish-gnu-ls))))
         (count (length (directory-files default-directory nil
                                         directory-files-no-dot-files-regexp t))))
    (popup-menu
     `("Options"
       ,@(mapcar (pcase-lambda (`(,label ,switch))
                   (vector (concat "Sort by " label)
                           `(my/dirvish-side-relist "\\`--\\(sort\\|time\\)=" ,switch)
                           :style 'radio :selected (equal switch sort)
                           :active my/dirvish-gnu-ls))
                 my/dirvish-side-sorts)
       "---"
       ,(funcall toggle "Descending" "--reverse")
       ,(funcall toggle "Folders First" "--group-directories-first")
       "---"
       ,(vector (format "%d item%s" count (if (= count 1) "" "s")) nil :active nil))
     event)))

;;;; Sidebar width

(defvar my/dirvish-side-width-ratio 0.22
  "Share of the frame's width a sidebar opens with, within the limits.")

(defvar my/dirvish-side-width-limits '(220 . 300)
  "Narrowest and widest width, in pixels, that a sidebar opens with.
The narrowest still fits most names two levels deep; the widest is about
a New UI tool window's.")

(defun my/dirvish-side-width ()
  "Return the selected frame's sidebar width in columns."
  (let ((pixels (* my/dirvish-side-width-ratio (frame-pixel-width))))
    (round (max (car my/dirvish-side-width-limits)
                (min (cdr my/dirvish-side-width-limits) pixels))
           (frame-char-width))))

(defun my/dirvish-side-fit-width (create dv)
  "CREATE the root window of side session DV as wide as the frame suits."
  (let ((dirvish-side-width (my/dirvish-side-width)))
    (funcall create dv)))
;; Every way of opening the sidebar creates its window here.
(advice-add 'dirvish-side-root-window-fn :around #'my/dirvish-side-fit-width)

;; Selection colors are supplied by ink-theme.el.
(setq dirvish-side-attributes '(subtree-state my-sidebar-icon my-sidebar-name)
      dirvish-side-auto-expand t)

(dirvish-override-dired-mode 1)
(define-key dirvish-mode-map (kbd "TAB") #'dirvish-subtree-toggle)

(defun my/dirvish-mouse-open (event)
  "Expand sidebar directories in place, or open the clicked file.
Outside the sidebar, preserve Dired's usual mouse behavior."
  (interactive "e")
  (let* ((position (event-end event))
         (window (posn-window position)))
    (if (and (windowp window)
             (with-current-buffer (window-buffer window)
               (when-let* ((session (dirvish-curr)))
                 (eq (dv-type session) 'side))))
        (let ((point (posn-point position)))
          (select-window window)
          ;; Blank space below the listing maps to point-max.  Do not move
          ;; there: Dirvish's post-command hook moves eobp to the last file.
          (when-let* ((file (and (integer-or-marker-p point)
                                (< point (point-max))
                                (save-excursion
                                  (goto-char point)
                                  (dired-get-filename nil t)))))
            (goto-char point)
            (if (file-directory-p file)
                (dirvish-subtree-toggle)
              (dired-find-file))))
      (dired-mouse-find-file-other-window event))))

(defun my/dirvish-mouse-press (event)
  "Focus the sidebar without moving point before the click is handled."
  (interactive "e")
  (let ((window (posn-window (event-start event))))
    (if (and (windowp window)
             (with-current-buffer (window-buffer window)
               (when-let* ((session (dirvish-curr)))
                 (eq (dv-type session) 'side))))
        (select-window window)
      (mouse-drag-region event))))

;; Dired's follow-link translates a left click on a filename to mouse-2.
(define-key dirvish-mode-map [mouse-2] #'my/dirvish-mouse-open)
(define-key dirvish-mode-map [down-mouse-1] #'my/dirvish-mouse-press)
(define-key dirvish-mode-map [mouse-1] #'my/dirvish-mouse-open)
;; Islands paints a few fringe pixels beside the one-pixel divider.
;; Treat that visible gap as part of the resize handle as well.
(defun my/dirvish-drag-divider (event)
  "Resize the sidebar using positions from mouse EVENTs, including its fringe."
  (interactive "e")
  (let* ((window (posn-window (event-start event)))
         (x-position
          (lambda (position)
            (let ((win (posn-window position)))
              (+ (car (posn-x-y position))
                 (if (windowp win) (car (window-inside-pixel-edges win)) 0)))))
         (last-x (funcall x-position (event-start event)))
         (track-mouse t)
         done)
    (while (not done)
      (let ((next (read-event)))
        (cond
         ((and (mouse-event-p next)
               (memq (event-basic-type next) '(mouse-movement mouse-1)))
          (let* ((x (funcall x-position (event-end next)))
                 (delta (- x last-x)))
            (unless (zerop delta)
              (adjust-window-trailing-edge window delta t t)
              (setq last-x x)
              ;; `read-event' runs inside this command, before the usual
              ;; window-change hooks.  Recompose rows and header right now.
              (dirvish--render-attrs window)
              (force-mode-line-update t)
              (redisplay t)))
          (when (eq (event-basic-type next) 'mouse-1) (setq done t)))
         (t (setq unread-command-events (cons next unread-command-events)
                  done t)))))))

(define-key dirvish-mode-map [right-fringe down-mouse-1] #'my/dirvish-drag-divider)
(define-key dirvish-mode-map [right-divider down-mouse-1] #'my/dirvish-drag-divider)
(define-key dirvish-mode-map [right-fringe mouse-1] #'ignore)
(define-key dirvish-mode-map [right-fringe drag-mouse-1] #'ignore)

(defvar-local my/dirvish-scroll-remainder 0)

(defun my/dirvish-scroll (event)
  "Scroll sidebar rows with EVENT, accumulating small touchpad deltas.
Avoid repeatedly relaying out SVGs at fractional row offsets."
  (interactive "e")
  (let ((window (mwheel-event-window event)))
    (when (framep window) (setq window (frame-selected-window window)))
    (if (not (and (window-live-p window)
                  (with-current-buffer (window-buffer window)
                    (when-let* ((session (dirvish-curr)))
                      (eq (dv-type session) 'side)))))
        (pixel-scroll-precision event)
      (with-selected-window window
        (set-window-vscroll window 0 t)
        (if-let* ((raw-delta (cdr-safe (nth 4 event))))
            ;; The wheel event already reflects the system's scroll direction;
            ;; its raw pixel delta does not necessarily use the same sign.
            (let* ((delta (if (mwheel--is-dir-p down (event-basic-type event))
                              (- (abs raw-delta)) (abs raw-delta)))
                   (height (max 1 (line-pixel-height)))
                   (old my/dirvish-scroll-remainder))
              (setq my/dirvish-scroll-remainder
                    (+ delta (if (< (* delta old) 0) 0 old)))
              (let ((lines (truncate (/ my/dirvish-scroll-remainder
                                        (float height)))))
                (unless (zerop lines)
                  (setq my/dirvish-scroll-remainder
                        (- my/dirvish-scroll-remainder (* lines height)))
                  (condition-case nil
                      (if (> lines 0) (scroll-up lines) (scroll-down (- lines)))
                    ((beginning-of-buffer end-of-buffer) nil))
                  (dirvish--render-attrs window))))
          (let ((mwheel-scroll-amount '(2 ((shift) . 1)))
                (mwheel-progressive-speed nil))
            (mwheel-scroll event))
          (dirvish--render-attrs window))))))

(define-key dirvish-mode-map [remap pixel-scroll-precision] #'my/dirvish-scroll)
(put 'my/dirvish-scroll 'scroll-command t)

(defun my/dirvish-setup ()
  "Disable line numbers before a directory buffer is first displayed."
  (display-line-numbers-mode -1)
  (when-let* ((session (dirvish-curr))
              ((eq (dv-type session) 'side)))
    ;; Follow the buffer's normal text face, including after theme changes.
    (face-remap-set-base 'dired-directory 'default)
    (unless my/dirvish-font-face-cookie
      (setq my/dirvish-font-face-cookie
            (face-remap-add-relative 'default 'my/dirvish-file-name)))
    ;; Keep rows airy even when the SVG determines their minimum height.
    (setq-local line-spacing 0.35)
    (setq my/dirvish-name-cache nil my/dirvish-name-metrics nil)
    ;; Side windows are initially sized above, but remain draggable afterward.
    (setq-local window-size-fixed nil)
    (setq-local scroll-preserve-screen-position nil)
    ;; Keep direct touchpad pixel scrolling; avoid queued wheel animations.
    (setq-local pixel-scroll-precision-interpolate-mice nil
                pixel-scroll-precision-large-scroll-height nil
                pixel-scroll-precision-use-momentum nil)
    (dolist (window (get-buffer-window-list (current-buffer) nil t))
      (set-window-parameter window 'my/dirvish-render-state nil))
    ;; The sidebar already has its project header; its internal buffer is no tab.
    (setq-local tab-line-exclude t)
    (when (bound-and-true-p tab-line-mode) (tab-line-mode -1))
    (unless my/dirvish-header-face-cookie
      (setq my/dirvish-header-face-cookie
            (face-remap-add-relative 'header-line
                                    :inherit 'tab-line :height 1.0 :box nil)))))
(add-hook 'dired-mode-hook #'my/dirvish-setup)
(add-hook 'dirvish-setup-hook #'my/dirvish-setup)

(defun my/dirvish-side-hide-tabs (buffer)
  "Hide tabs after Dirvish renames BUFFER into its internal sidebar."
  (with-current-buffer buffer
    (setq-local tab-line-exclude t)
    (when (bound-and-true-p tab-line-mode) (tab-line-mode -1))))
(advice-add 'dirvish-side-root-conf :after #'my/dirvish-side-hide-tabs)

;; Also update sidebars which were open when this configuration was reloaded.
(dolist (buffer (buffer-list))
  (with-current-buffer buffer
    (when (derived-mode-p 'dired-mode)
      (my/dirvish-setup)
      (when-let* ((session (dirvish-curr))
                  ((eq (dv-type session) 'side)))
        ;; Sessions cache their attributes and bars; refresh them on reload.
        (setf (dv-attributes session)
              (dirvish--attrs-expand dirvish-side-attributes))
        (dirvish-prop :attrs (dv-attributes session))
        (my/dirvish-side-bars session)
        (dirvish--setup-mode-line session)))))
(force-mode-line-update t)

(defun my/dirvish-refresh-focus (frame)
  "Render FRAME's sidebars and their selection faces.
Run when FRAME's selected window or a window's buffer changes."
  (let ((selected (frame-selected-window frame)))
    (dolist (window (window-list frame 'no-minibuffer))
      (with-current-buffer (window-buffer window)
        (when-let* ((session (dirvish-curr))
                    ((eq (dv-type session) 'side))
                    ((not (derived-mode-p 'wdired-mode))))
          ;; Pass the real selection explicitly: rendering temporarily selects
          ;; the sidebar, which must not make it appear focused again.
          (dirvish--render-attrs window selected))))))

(add-hook 'window-selection-change-functions #'my/dirvish-refresh-focus)
;; Dirvish renders only the selected window before redisplay.  A command
;; that opens the sidebar and then selects another window (or never selects
;; it) leaves no redisplay with the sidebar selected, and no selection change
;; either, so its rows would stay raw Dired text.
(add-hook 'window-buffer-change-functions #'my/dirvish-refresh-focus)

(defun my/dirvish-root ()
  "Return the current project root, or the current directory."
  (if-let* ((project (project-current nil)))
      (project-root project)
    default-directory))

(defun my/dirvish-show (&optional directory)
  "Ensure the sidebar shows DIRECTORY, preserving the selected window."
  (let ((directory (file-name-as-directory
                    (expand-file-name (or directory (my/dirvish-root))))))
    (save-selected-window
      (if-let* ((window (dirvish-side--session-visible-p)))
          (with-selected-window window
            (unless (equal directory default-directory)
              (dirvish--find-entry 'find-alternate-file directory)))
        ;; Dirvish automatically expands the calling buffer's file.  An
        ;; external dependency source cannot be located in this project tree.
        (let ((buffer-file-name
               (and buffer-file-name
                    (string-prefix-p directory (expand-file-name buffer-file-name))
                    buffer-file-name)))
          (dirvish-side directory))))
    ;; Dirvish's pre-redisplay hook only renders the selected window.  This
    ;; helper leaves focus in the editor, so paint the sidebar explicitly.
    (my/dirvish-refresh-focus (selected-frame))
    (set-frame-parameter nil 'my/dirvish-directory directory)))

(defun my/dirvish-toggle ()
  "Focus the sidebar from the editor; hide it when already focused."
  (interactive)
  (if-let* ((window (dirvish-side--session-visible-p)))
      (if (eq window (selected-window))
          (dirvish-quit)
        (select-window window))
    (my/dirvish-show (frame-parameter nil 'my/dirvish-directory))
    (when-let* ((window (dirvish-side--session-visible-p)))
      (select-window window))))

(global-set-key (kbd "s-1") #'my/dirvish-toggle)
(global-set-key (kbd "C-c e") #'my/dirvish-toggle)

(defun my/dirvish-empty-buffer (directory)
  "Return an empty scratch buffer for DIRECTORY, preserving existing text."
  (let ((buffer (get-buffer-create "*scratch*")))
    (unless (zerop (buffer-size buffer))
      (setq buffer (generate-new-buffer "*scratch*")))
    (with-current-buffer buffer
      (unless (derived-mode-p 'lisp-interaction-mode)
        (lisp-interaction-mode))
      (setq-local default-directory (file-name-as-directory directory)))
    buffer))

(defun my/dirvish-open-directory (directory)
  "Open DIRECTORY in the sidebar with an empty editor buffer."
  (interactive "DOpen directory: ")
  (setq directory (expand-file-name directory))
  (switch-to-buffer (my/dirvish-empty-buffer directory))
  (my/dirvish-show directory))

(defun my/dirvish-project-dired ()
  "Open the selected project as a sidebar and empty editor buffer."
  (interactive)
  (my/dirvish-open-directory (project-root (project-current t))))

(defun my/dirvish-after-project-find-file (&rest _)
  "Show the current project after opening a project file."
  (my/dirvish-show))

(advice-add 'project-dired :override #'my/dirvish-project-dired)
;; Project switching and startup are owned by init-workspace.el.
;; Dirvish's async metadata buffers look like ordinary project buffers;
;; killing one mid-fetch makes its sentinel fail when a project is closed.
(setq project-kill-buffer-conditions
      (mapcar (lambda (condition)
                (if (equal condition '(and (major-mode . fundamental-mode) "\\`[^ ]"))
                    (append condition '((not "\\`\\*dirvish-batch\\*")))
                  condition))
              project-kill-buffer-conditions))
(advice-remove 'project-switch-project #'my/dirvish-after-project-switch)
(remove-hook 'emacs-startup-hook #'my/dirvish-startup)
(advice-add 'project-find-file :after #'my/dirvish-after-project-find-file)

(defun my/dirvish-take-startup-directory ()
  "Replace command-line directory windows with empty editors; return the first.
Run after Emacs has processed file arguments, including relative paths and
paths following --.  Explicit file buffers remain in their editor windows.
The caller decides what to show for the returned directory."
  (let (directory)
    (dolist (window (window-list))
      (with-current-buffer (window-buffer window)
        (when (and (derived-mode-p 'dired-mode)
                   (not (window-parameter window 'window-side)))
          (setq directory (or directory default-directory))
          (let ((directory-buffer (current-buffer)))
            (set-window-buffer window
                               (my/dirvish-empty-buffer default-directory))
            ;; Keep the Dired buffer alive, but remove the startup placeholder
            ;; from this editor's navigation history and tab strip.
            (set-window-prev-buffers
             window (seq-remove (lambda (entry) (eq (car entry) directory-buffer))
                                (window-prev-buffers window)))
            (set-window-next-buffers
             window (delq directory-buffer (window-next-buffers window)))))))
    directory))

(provide 'init-dirvish)
;;; init-dirvish.el ends here
