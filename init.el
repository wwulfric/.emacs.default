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

;; The initial frame exists before this file loads.  Show the start page's
;; empty buffer during startup so *scratch* never flashes; file arguments
;; replace it as usual (see `my/workspace-startup').
(unless (or noninteractive (daemonp))
  (with-current-buffer (get-buffer-create "*Welcome*")
    (setq-local mode-line-format nil
                tab-line-exclude t
                cursor-type nil))
  (switch-to-buffer "*Welcome*")
  ;; Nor should the initial *scratch* linger as a tab.
  (set-window-prev-buffers nil nil))

;; State files under var/; must precede project.el.
(require 'init-session)

;; ibuffer
(global-set-key (kbd "C-x C-b") 'ibuffer)


(require 'global-shortkeys)
;; Editing defaults and completion are independent of the visual theme.
(setq-default indent-tabs-mode nil)
(setq original-y-or-n-p 'y-or-n-p)
(fset 'yes-or-no-p 'y-or-n-p)

(require 'auto-save)
(auto-save-enable)
(setq auto-save-silent t)

;; Frames, typography, tabs and sidebar.
(require 'frame-setting)
;; Minibuffer completion, shown in a floating panel.
(require 'init-completion)
(require 'init-palette)
(require 'init-tab-line)
;; The sidebar is moving from Dirvish to plain Dired; switching needs a restart.
(defvar my/sidebar-use-dired t
  "Non-nil loads the Dired sidebar (init-sidebar.el) instead of Dirvish's.")
(require (if my/sidebar-use-dired 'init-sidebar 'init-dirvish))
(require 'edit-up)
(require 'init-fingertip)
(require 'init-treesit)
(require 'init-writing)
(require 'init-emacs-rime)
;; Ink owns face styling; component configs own layout and interaction.
(add-to-list 'custom-theme-load-path (expand-file-name "ui" emacs-root-dir))
(load-theme 'ink t)
;; Windows as rounded cards on a gray canvas, after the theme it repaints.
(require 'init-islands)
(my/islands-mode 1)
;; One status bar in the echo area, under the cards; mode lines keep their edge.
(require 'init-status)
(my/status-mode 1)
(require 'init-jieba-word)
(require 'init-lsp)
(require 'init-search)
(require 'init-navigation)
;; Per-project workspaces and the start page shown without file arguments.
(require 'init-workspace)
(require 'init-welcome)

(require 'exec-path-from-shell)
(dolist (var '("SSH_AUTH_SOCK" "SSH_AGENT_PID" "GPG_AGENT_INFO" "LANG" "LC_CTYPE" "NIX_SSL_CERT_FILE" "NIX_PATH"))
  (add-to-list 'exec-path-from-shell-variables var))
(when (memq window-system '(mac ns x))
  (exec-path-from-shell-initialize))
