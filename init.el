;; -*- lexical-binding: t; -*-

(setq gc-cons-threshold (* 100 1024 1024))

;; 进行缩进时不使用制表符（Tab）字符，而是使用空格字符进行缩进
(setq-default indent-tabs-mode nil)

;; load 插件 path
(defvar emacs-root-dir (file-truename "~/.emacs.d/lisp/"))

(defun add-subdirs-to-load-path (dir)
  "Recursive add directories to `load-path'."
  (let ((default-directory (file-name-as-directory dir)))
    (add-to-list 'load-path dir)
    (normal-top-level-add-subdirs-to-load-path)))
(add-subdirs-to-load-path emacs-root-dir)

;; 像素级滚动
(pixel-scroll-precision-mode 1)

(require 'global-shortkeys)
(require 'init-fingertip)
(require 'init-treesit)
(require 'init-emacs-rime)
(require 'ink-theme)

