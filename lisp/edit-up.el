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


;; C-x 剪切，C-c, C-v 等支持；按中 shift 选择
(cua-mode -1)
(provide 'edit-up)

