;; -*- lexical-binding: t; -*-
(tool-bar-mode -1)
(scroll-bar-mode -1)

;; 下方新增一行
(global-set-key (kbd "<S-return>") (lambda ()
				     (interactive)
				     (end-of-line)
				     (newline-and-indent)))
;; 上方新增一行
(global-set-key (kbd "<C-return>") (lambda ()
				     (interactive)
				     (previous-line)
				     (end-of-line)
				     (newline-and-indent)))
;; 删除整行
(global-set-key (kbd "<s-backspace>") (lambda ()
				  (interactive)
				  (kill-whole-line)))

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

(require 'init-fingertip)
(require 'init-treesit)
(require 'init-emacs-rime)
