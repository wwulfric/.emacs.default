;;; init-dirvish.el --- Project file sidebar -*- lexical-binding: t; -*-

;;; Commentary:
;; Dirvish and compat are vendored as Git submodules under lisp/.
;; Keep project navigation separate from lsp-bridge's language server roots.

;;; Code:

(require 'project)
(require 'dirvish)
(require 'dirvish-side)

;; macOS BSD ls does not support GNU ls's --dired option.
(when (eq system-type 'darwin)
  (setq dired-use-ls-dired nil))

;; Show dotfiles, but omit the synthetic . and .. entries (BSD/GNU ls).
(setq dired-listing-switches "-lA")

;; Skip the mode/header-line spacer image so font metrics set the height.
;; A width of 0 merely hides the image and still reserves its fixed height.
(setq dirvish-mode-line-bar-image-width nil)

(dirvish-define-mode-line my-height
  "Use the editor's status-bar height without adding horizontal padding."
  (when (display-graphic-p) (my/ui-mode-line-space 0)))

(setq dirvish-side-mode-line-format
      (plist-put (copy-sequence dirvish-side-mode-line-format) :left
                 (cons 'my-height
                       (remq 'my-height
                             (plist-get dirvish-side-mode-line-format :left)))))

;; Share tab-line's font metrics and vertical padding, only in the sidebar.
(require 'face-remap)
(defvar-local my/dirvish-header-face-cookie nil)
(defvar-local my/dirvish-font-face-cookie nil)
(defvar my/dirvish-icon-cache (make-hash-table :test #'equal))

(defun my/dirvish-align-subtree-state (result)
  "Keep RESULT's disclosure column fixed-width in proportional sidebars."
  (when (and my/dirvish-font-face-cookie (eq (car-safe result) 'ov))
    (when-let* ((text (overlay-get (cdr result) 'after-string)))
      (add-face-text-property 0 (length text) 'dirvish-subtree-state t text)))
  result)

(with-eval-after-load 'dirvish-subtree
  (advice-add 'dirvish-attribute-subtree-state-rd :filter-return
              #'my/dirvish-align-subtree-state))

(defface my/dirvish-file-name
  '((t (:family "Helvetica Neue" :height 0.95 :weight normal)))
  "Proportional sidebar text." :group 'dirvish)
(defface my/dirvish-project-title '((t (:inherit default)))
  "Sidebar project title." :group 'dirvish)
(defface my/dirvish-neutral-icon '((t (:inherit shadow)))
  "Folder and ordinary file icons." :group 'dirvish)
(defface my/dirvish-source-icon '((t (:inherit link)))
  "Source file icons." :group 'dirvish)

(defun my/dirvish-file-icon (name directory)
  "Return a small SVG icon for NAME, or a folder when DIRECTORY is non-nil."
  (let* ((source (member (file-name-extension name)
                         '("el" "go" "hs" "py" "js" "jsx" "ts" "tsx"
                           "rs" "c" "h" "cpp" "java" "swift")))
         (color (face-foreground (if (and source (not directory))
                                    'my/dirvish-source-icon
                                  'my/dirvish-neutral-icon) nil t))
         (kind (cond (directory 'folder) (source 'code) (t 'file)))
         (key (list kind color)))
    (or (gethash key my/dirvish-icon-cache)
        (puthash
         key
         (create-image
          (format
           "<svg xmlns='http://www.w3.org/2000/svg' width='16' height='16' viewBox='0 0 16 16'><g fill='none' stroke='%s' stroke-width='1.2' stroke-linecap='round' stroke-linejoin='round'>%s</g></svg>"
           color
           (pcase kind
             ('folder "<path d='M1.5 4V13h13V5H7L5.5 3h-4Z'/>")
             ('code "<path d='m5 4-4 4 4 4m6-8 4 4-4 4M9 3 7 13'/>")
             (_ "<path d='M3 1.5h6l4 4v9H3ZM9 1.5V6h4M5.5 9h5m-5 3h5'/>")))
          'svg t :ascent 'center)
         my/dirvish-icon-cache))))

(dirvish-define-attribute my-sidebar-icon
  "Small outline icons without an external icon-font dependency."
  :when (and (display-graphic-p) (image-type-available-p 'svg))
  :width 3
  (let ((ov (make-overlay (1- f-beg) f-beg)))
    (overlay-put ov 'after-string
                 (concat (propertize " " 'display
                                     (my/dirvish-file-icon
                                      f-str (eq (car f-type) 'dir))
                                     'face hl-face)
                         (propertize " " 'display '(space :width (6))
                                     'face hl-face)))
    `(ov . ,ov)))

(defun my/dirvish-pad-project-title (title)
  "Give the sidebar's TITLE the same vertical padding as buffer tabs."
  (if-let* ((session (dirvish-curr))
            ((eq (dv-type session) 'side)))
      (concat (propertize " " 'face 'header-line
                          'display (my/ui-header-space 0))
              (propertize
               (concat " " (file-name-nondirectory
                             (directory-file-name
                              (or (dirvish--vc-root-dir) default-directory))))
               'face 'my/dirvish-project-title))
    title))

(with-eval-after-load 'dirvish-widgets
  (advice-add 'dirvish-project-ml :filter-return #'my/dirvish-pad-project-title))

;; Selection colors are supplied by ink-theme.el.
(setq dirvish-side-width 30
      dirvish-side-attributes '(subtree-state my-sidebar-icon)
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
    (setq-local line-spacing 0.2)
    (setq-local dirvish-subtree-prefix "  │")
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
        ;; Sessions cache their composed status bar; refresh it on reload too.
        (setf (dv-attributes session)
              (dirvish--attrs-expand dirvish-side-attributes))
        (dirvish-prop :attrs (dv-attributes session))
        (setf (dv-mode-line session)
              (dirvish--mode-line-composer
               (plist-get dirvish-side-mode-line-format :left)
               (plist-get dirvish-side-mode-line-format :right)))
        (dirvish--setup-mode-line session)))))
(force-mode-line-update t)

(defun my/dirvish-refresh-focus (frame)
  "Refresh sidebar selection faces when FRAME's selected window changes."
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
