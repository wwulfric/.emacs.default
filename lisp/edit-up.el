;; mark macro 键盘宏
;;(require 'markmacro)
;; 先C+SPC标记起点，然后按住Shift点选范围内的文字。下面2行 设为ignore是为了防止一些可能的副作用
(define-key global-map (kbd "<S-down-mouse-1>") 'mouse-save-then-kill)
(define-key global-map (kbd "<S-mouse-1>") 'ignore)
(define-key global-map (kbd "<S-drag-mouse-1>") 'ignore)

;; indent
(setq tab-always-indent 'complete)
;; comment
;;(setq comment-style 'plain)
;;(setq comment-style 'indent)

;; delsel 提供的功能，选中之后的修改是删除再修改，而不是默认的insert
(delete-selection-mode 1)


;; C-x 剪切，C-c, C-v 等支持；按中 shift 选择
(cua-mode -1)


;; 关闭普通删除操作与系统剪切板的关联
(setq x-select-enable-clipboard nil)

;; 只让显式的剪切命令(C-w, M-w等)使用系统剪切板
(setq select-enable-clipboard t)
(setq select-enable-primary nil)

;; 在光标处而非鼠标所在位置粘贴
(setq mouse-yank-at-point t)

(provide 'edit-up)

