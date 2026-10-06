;; -*- lexical-binding: t; -*-

(setq gc-cons-threshold (* 100 1024 1024))

;; (message (file-truename load-file-name)) ;; debug

(defun global/load-file-path ()
  "获取当前 load 的 file 的 path"
  (file-name-directory (file-truename load-file-name)))

;; load 插件 path
(defvar emacs-root-dir (concat (global/load-file-path) "lisp/"))

(defun add-subdirs-to-load-path (dir)
  "Recursive add directories to `load-path'."
  (let ((default-directory (file-name-as-directory dir)))
    (add-to-list 'load-path dir)
    (normal-top-level-add-subdirs-to-load-path)))
(add-subdirs-to-load-path emacs-root-dir)
;; Personal display configuration lives together; vendor paths stay unchanged.
(add-to-list 'load-path (expand-file-name "ui" emacs-root-dir))


;; smex
(require 'smex)
(global-set-key (kbd "M-x") 'smex)
(global-set-key (kbd "M-X") 'smex-major-mode-commands)
;; This is your old M-x.
(global-set-key (kbd "C-c C-c M-x") 'execute-extended-command)
;; ibuffer
(global-set-key (kbd "C-x C-b") 'ibuffer)


(require 'global-shortkeys)
;; Editing defaults and completion are independent of the visual theme.
(setq-default indent-tabs-mode nil)
(setq original-y-or-n-p 'y-or-n-p)
(fset 'yes-or-no-p 'y-or-n-p)

(require 'flx-ido)
(ido-mode 1)
(ido-everywhere 1)
(flx-ido-mode 1)
(setq ido-enable-flex-matching t
      ido-use-faces nil)

(require 'auto-save)
(auto-save-enable)
(setq auto-save-silent t)

;; Frames, typography, tabs and sidebar.
(require 'frame-setting)
(require 'init-tab-line)
(require 'init-dirvish)
(require 'edit-up)
(require 'init-fingertip)
(require 'init-treesit)
(require 'init-writing)
(require 'init-emacs-rime)
;; Ink owns face styling; component configs own layout and interaction.
(add-to-list 'custom-theme-load-path (expand-file-name "ui" emacs-root-dir))
(load-theme 'ink t)
(require 'init-jieba-word)
(require 'init-lsp)
(require 'init-navigation)

(require 'exec-path-from-shell)
(dolist (var '("SSH_AUTH_SOCK" "SSH_AGENT_PID" "GPG_AGENT_INFO" "LANG" "LC_CTYPE" "NIX_SSL_CERT_FILE" "NIX_PATH"))
  (add-to-list 'exec-path-from-shell-variables var))
(when (memq window-system '(mac ns x))
  (exec-path-from-shell-initialize))
