;;; init-git.el --- Git tool windows on top of Magit -*- lexical-binding: t; -*-

;;; Commentary:
;; IntelliJ's Git tools, from the git-islands package and driven by Magit:
;; the Commit tool window (s-0), the Git log (s-9), the branches popup
;; (C-~, or the branch in the status bar), file colors in the project
;; sidebar and change markers in the editor's fringe.  Magit itself loads
;; only when a tool window first opens or a command changes a repository.

;;; Code:

;;;; The tool windows in this configuration

;; The package is the submodule lisp/git-islands, on the load path with
;; the other packages under lisp.
(require 'git-islands)

;; The tool windows ask the editor around them through git-islands-env.el;
;; this configuration answers with its sidebar, islands, palette and status bar.

(declare-function my/sidebar-status-line "init-sidebar" ())
(declare-function my/keys-remember "init-keys" (symbol))
(declare-function my/sidebar-width "init-sidebar" ())
(declare-function my/sidebar-hide "init-sidebar" (&optional frame))
(declare-function my/status--item "init-status" (text &optional action help))
(declare-function git-islands-widget-current "git-islands-branches" ())
(declare-function git-islands-widget-label "git-islands-branches" (status))
(declare-function git-islands-branches-popup "git-islands-branches" (&optional root))
(defvar palette-islands-placement)
(defvar palette-islands-anchor)
(defvar my/status-right-functions)

(defun my/git-palette-below (anchor read)
  "Call READ with the minibuffer panel dropped down from ANCHOR."
  (let ((palette-islands-placement 'point)
        (palette-islands-anchor anchor))
    (funcall read)))

(defun my/git-sidebar-directory ()
  "Return the project the frame's sidebar shows, or nil."
  (frame-parameter nil 'my/sidebar-directory))

(setq git-islands-mode-line-format '(:eval (my/sidebar-status-line))
      git-islands-with-anchor-function #'my/git-palette-below
      git-islands-fallback-directory-function #'my/git-sidebar-directory
      git-islands-side-window-width #'my/sidebar-width)
;; The Commit tool window takes the project sidebar's place.
(add-hook 'git-islands-side-window-hook #'my/sidebar-hide)

;; Rows, pills, headers and buttons come from tool-islands, styled for
;; every tool window in init-tool-islands.el.

(defun my/git-status-label (status)
  "Render STATUS with aligned Expui icons in the personal status bar."
  (if (not (expui-icons-svg-p))
      (git-islands-widget-label status)
    (let ((gap (propertize " " 'display '(space :width (4))))
          (branch (or (git-islands-status-branch status)
                      (let ((head (or (git-islands-status-head status) "")))
                        (substring head 0 (min 7 (length head)))))))
      (concat
       (expui-icons-icon "general/vcs" :height 16 :ascent 'center) gap branch
       (when (> (git-islands-status-ahead status) 0)
         (concat gap (expui-icons-icon "vcs/push" :height 16 :ascent 'center)
                 gap (number-to-string (git-islands-status-ahead status))))
       (when (> (git-islands-status-behind status) 0)
         (concat gap (expui-icons-icon "vcs/update" :height 16 :ascent 'center)
                 gap (number-to-string (git-islands-status-behind status))))))))

(defun my/git-status-widget (_window)
  "Return the status bar's branch widget for the current buffer, or nil."
  (when-let* ((current (git-islands-widget-current)))
    (let ((root (car current)))
      (my/status--item (propertize (my/git-status-label (cdr current)) 'face 'my/status)
                       (lambda (_event) (git-islands-branches-popup root))
                       "Git Branches (C-~)"))))

(with-eval-after-load 'init-status
  (add-to-list 'my/status-right-functions #'my/git-status-widget))

;;;; Commit tool window

;; As in IntelliJ: Cmd-0 is the Commit tool window, Cmd-K commits.
(global-set-key (kbd "s-0") #'git-islands-commit-toggle)
(global-set-key (kbd "s-k") #'git-islands-message-focus)
(autoload 'magit-status "magit-status" nil t)
(global-set-key (kbd "C-x g") #'magit-status)

(declare-function magit-display-buffer-same-window-except-diff-v1 "magit-mode" (buffer))
(defvar magit-display-buffer-function)
(defvar magit-save-repository-buffers)
(with-eval-after-load 'magit
  ;; Magit buffers open in the editor area, never over a tool window.
  (setq magit-display-buffer-function #'magit-display-buffer-same-window-except-diff-v1
        magit-save-repository-buffers 'dontask))

;;;; Git tool window

;; As in IntelliJ: Cmd-9 is the Git tool window.
(global-set-key (kbd "s-9") #'git-islands-log-toggle)

;;;; Annotate and conflicts

(global-set-key [remap vc-annotate] #'git-islands-annotate)

;;;; Branches and file colors

(require 'git-sidebar)
(require 'git-islands-branches)
(global-set-key (kbd "C-~") #'git-islands-branches-popup)

;;;; Change markers

;; Changed lines get a thin bar in the fringe, unsaved changes included;
;; clicking one shows the hunk with Rollback and Stage, as in IntelliJ.
(require 'diff-hl)
(require 'diff-hl-flydiff)
(require 'diff-hl-show-hunk)
(require 'diff-hl-show-hunk-inline)
(require 'diff-hl-show-hunk-posframe)
;; The shortcut reference (init-keys.el) lists only the keys added below.
(my/keys-remember 'diff-hl-mode-map)

;; The hunk popup's buffers are internal: a leading space keeps them out of
;; the editor's tabs, where diff-hl's buffer switching would leave them.
(setq diff-hl-show-hunk-buffer-name " *diff-hl-show-hunk*"
      diff-hl-show-hunk-diff-buffer-name " *diff-hl-show-hunk-diff*"
      diff-hl-show-hunk-posframe-internal-border-width 1)

(defun my/diff-hl-popup-border (&rest _)
  "Draw the hunk popup's border in the theme's muted color."
  (setq diff-hl-show-hunk-posframe-internal-border-color
        (let ((color (face-attribute 'shadow :foreground nil t)))
          (if (stringp color) color "gray60"))))
(my/diff-hl-popup-border)
(add-hook 'enable-theme-functions #'my/diff-hl-popup-border)

(setq diff-hl-draw-borders nil
      diff-hl-update-async t
      diff-hl-show-staged-changes t
      diff-hl-show-hunk-function
      (if (display-graphic-p) #'diff-hl-show-hunk-posframe #'diff-hl-show-hunk-inline))

(define-fringe-bitmap 'my/diff-hl-bar (make-vector 1 #b11100000) nil nil '(center t))

(defun my/diff-hl-bitmap (_type _position)
  "Draw every change marker as the same thin bar; its face tells the kind."
  'my/diff-hl-bar)
(setq diff-hl-fringe-bmp-function #'my/diff-hl-bitmap)

(with-eval-after-load 'magit
  (add-hook 'magit-post-refresh-hook #'diff-hl-magit-post-refresh))

(global-diff-hl-mode 1)
(diff-hl-flydiff-mode 1)
(global-diff-hl-show-hunk-mouse-mode 1)

(define-key diff-hl-mode-map (kbd "C-M-s-<up>") #'diff-hl-previous-hunk)
(define-key diff-hl-mode-map (kbd "C-M-s-<down>") #'diff-hl-next-hunk)
(define-key diff-hl-mode-map (kbd "s-M-z") #'diff-hl-revert-hunk)

(provide 'init-git)
;;; init-git.el ends here
