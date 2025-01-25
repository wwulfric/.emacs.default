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

;; 像素级滚动
(pixel-scroll-precision-mode 1)


(require 'global-shortkeys)
(require 'frame-setting)
(require 'edit-up)
(require 'init-fingertip)
(require 'init-treesit)
(require 'init-emacs-rime)
;(require 'ink-theme)
(require 'init-jieba-word)
(require 'init-lsp)

