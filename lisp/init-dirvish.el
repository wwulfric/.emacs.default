;;; init-dirvish.el --- Project file sidebar -*- lexical-binding: t; -*-

;;; Commentary:
;; Dirvish and compat are vendored as Git submodules under lisp/.
;; Keep project navigation separate from lsp-bridge's language server roots.

;;; Code:

(require 'project)
(require 'dirvish)
(require 'dirvish-side)

;; Show dotfiles, but omit the synthetic . and .. entries (BSD/GNU ls).
(setq dired-listing-switches "-lA")

;; Skip the mode/header-line spacer image so font metrics set the height.
;; A width of 0 merely hides the image and still reserves its fixed height.
(setq dirvish-mode-line-bar-image-width nil)

;; Subtle selection colors, distinct when focus returns to the editor.
;; Avoid inheriting the theme's stronger highlight/region backgrounds.
(custom-set-faces
 '(dirvish-hl-line
   ((((class color) (background light))
     (:inherit nil :background "#E3ECFA" :extend t))
    (((class color) (background dark))
     (:inherit nil :background "#303D50" :extend t))))
 '(dirvish-hl-line-inactive
   ((((class color) (background light))
     (:inherit nil :background "#ECEDEF" :extend t))
    (((class color) (background dark))
     (:inherit nil :background "#303236" :extend t)))))

(setq dirvish-side-width 30
      dirvish-side-attributes '(subtree-state)
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
  (display-line-numbers-mode -1))
(add-hook 'dired-mode-hook #'my/dirvish-setup)
(add-hook 'dirvish-setup-hook #'my/dirvish-setup)

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
        (dirvish-side directory)))
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

(defun my/dirvish-after-project-switch (directory)
  "Ensure DIRECTORY is visible after an explicit project switch."
  (my/dirvish-show directory))

(defun my/dirvish-after-project-find-file (&rest _)
  "Show the current project after opening a project file."
  (my/dirvish-show))

(advice-add 'project-dired :override #'my/dirvish-project-dired)
(advice-add 'project-switch-project :after #'my/dirvish-after-project-switch)
(advice-add 'project-find-file :after #'my/dirvish-after-project-find-file)

(defun my/dirvish-startup ()
  "Turn command-line directory windows into a sidebar and empty editor.
Run after Emacs has processed file arguments, including relative paths and
paths following --.  Explicit file buffers remain in their editor windows.
When several directories are visible, use the first one's root."
  (let (directory)
    (dolist (window (window-list))
      (with-current-buffer (window-buffer window)
        (when (and (derived-mode-p 'dired-mode)
                   (not (window-parameter window 'window-side)))
          (setq directory (or directory default-directory))
          (set-window-buffer window
                             (my/dirvish-empty-buffer default-directory)))))
    (when directory
      (set-buffer (window-buffer (selected-window)))
      (my/dirvish-show directory))))

(add-hook 'emacs-startup-hook #'my/dirvish-startup)

(provide 'init-dirvish)
;;; init-dirvish.el ends here
