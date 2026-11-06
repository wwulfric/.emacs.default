;; -*- lexical-binding: t; -*-
;; 先C+SPC标记起点，然后按住Shift点选范围内的文字。下面2行 设为ignore是为了防止一些可能的副作用
(define-key global-map (kbd "<S-down-mouse-1>") 'mouse-save-then-kill)
(define-key global-map (kbd "<S-mouse-1>") 'ignore)
(define-key global-map (kbd "<S-drag-mouse-1>") 'ignore)

;; indent
(setq tab-always-indent 'complete)

;; delsel 提供的功能，选中之后的修改是删除再修改，而不是默认的insert
(delete-selection-mode 1)


;; 保留 Emacs 的 C-x/C-c 前缀键，不启用 CUA 绑定。
(cua-mode -1)


;; 剪切和复制与系统剪贴板同步；不使用 primary selection。
(setq select-enable-clipboard t)
(setq select-enable-primary nil)

;; 在光标处而非鼠标所在位置粘贴
(setq mouse-yank-at-point t)

(provide 'edit-up)

