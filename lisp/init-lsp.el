;; -*- lexical-binding: t; -*-
(require 'yasnippet)
(yas-global-mode 1)

(setq lsp-bridge-python-command (concat (global/load-file-path) "../.venv/bin/python"))

(require 'lsp-bridge)

;; Keep local language-server settings outside the vendored lsp-bridge tree.
(setq lsp-bridge-user-langserver-dir
      (expand-file-name "langserver" (file-name-directory
                                     (or load-file-name buffer-file-name))))

;; Cmd-click: peek at a definition, otherwise jump to the definition.
;; macOS maps Command to Super by default.
(defvar my/lsp-click-context nil)

(defun my/lsp-click-clear-context ()
  (setq my/lsp-click-context nil))

(defun my/lsp-click (event)
  "Find the clicked symbol's definition, or peek if already there."
  (interactive "e")
  (mouse-set-point event)
  (my/lsp-click-clear-context)
  (let ((bounds (bounds-of-thing-at-point 'symbol)))
    (when bounds
      (when (and buffer-file-name (lsp-bridge-has-lsp-server-p))
        ;; Sync the click BEFORE find_define.  Otherwise post-command-hook
        ;; sends change_cursor afterwards and invalidates its response.
        (unless (equal lsp-bridge-last-cursor-position (point))
          (lsp-bridge-call-file-api "change_cursor" (lsp-bridge--position))
          (setq-local lsp-bridge-last-cursor-position (point)))
        (setq my/lsp-click-context
              (list (current-buffer) (point) (buffer-chars-modified-tick)
                    bounds)))
      (lsp-bridge-find-def))))

(defun my/lsp-click-maybe-peek (original filename filehost position)
  "Turn a definition response at the clicked symbol into Peek."
  (let ((context my/lsp-click-context))
    (my/lsp-click-clear-context)
    (if (and context
             (eq (current-buffer) (nth 0 context))
             (= (point) (nth 1 context))
             (= (buffer-chars-modified-tick) (nth 2 context))
             ;; Only compare local file positions here.
             (equal filehost "")
             buffer-file-name
             (not (file-remote-p buffer-file-name))
             (file-equal-p filename buffer-file-name)
             (let ((target (acm-backend-lsp-position-to-point position))
                   (bounds (nth 3 context)))
               (and (<= (car bounds) target) (< target (cdr bounds)))))
        (lsp-bridge-peek)
      (funcall original filename filehost position))))

;; A later user command must not reuse an earlier click's context.
(add-hook 'pre-command-hook #'my/lsp-click-clear-context)
(advice-add 'lsp-bridge-define--jump :around #'my/lsp-click-maybe-peek)
(define-key lsp-bridge-mode-map (kbd "<s-down-mouse-1>") #'ignore)
(define-key lsp-bridge-mode-map (kbd "<s-mouse-1>") #'my/lsp-click)

(global-lsp-bridge-mode)
;;(setq lsp-bridge-enable-hover-diagnostic t)

;; python
(setq lsp-bridge-python-lsp-server "ruff")
(setq lsp-bridge-python-multi-lsp-server "basedpyright_ruff")

;; java
(require 'lsp-bridge-jdtls) ;; 根据项目自动生成自定义配置，添加必要的启动参数
(setq lsp-bridge-enable-auto-import t) ;; 开启自动导入依赖，目前没有code action。补全时可以通过这个导入相应的依赖，建议开启。

;; haskell
(require 'haskell-mode-autoloads)

;; markdown
(require 'markdown-ts-mode)
(setq lsp-bridge-markdown-lsp-server "marksman")
(setq markdown-command "pandoc")


(provide 'init-lsp)
