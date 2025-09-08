;; -*- lexical-binding: t; -*-


(setq default-frame-alist
      (append (list '(width  . 100) '(height . 50)
                    '(vertical-scroll-bars . nil)
                    '(internal-border-width . 0)
                    '(font . "PT Mono 14"))))
;; 全局显示行号
(global-display-line-numbers-mode 1)
;; 列号
(column-number-mode t)


;; 鼠标滚动
(setq scroll-preserve-screen-position 'always)


;; 禁止鼠标拖拽行为
(setq mouse-drag-and-drop-region nil)
(global-unset-key [S-drag-mouse-1])
(global-unset-key [S-mouse-1])

(setq inhibit-startup-screen t) ;; 禁止emacs启动时显示欢迎屏幕
(setq inhibit-startup-echo-area-message t) ;; 禁止emacs启动时在echo区域显示信息
(setq inhibit-startup-message t) ;; 禁止emacs启动时显示启动信息
(setq initial-scratch-message nil) ;; 设置初始暂存区(scratch buffer)的消息为空

;; 像素级滚动
(pixel-scroll-precision-mode 1)

;; 会将新窗口弹出到当前窗口的上面
;; (setq pop-up-windows nil)

;; uniquify 库可以帮助 Emacs 给缓冲区设置唯一的名字，以避免同名缓冲区的冲突。uniquify-buffer-name-style 变量控制了唯一化缓冲区名字的方式。在这里，将其设置为 forward，表示在缓冲区名前缀重复的情况下，将添加目录路径来唯一标识缓冲区名字
;; (require 'uniquify)
;; (setq uniquify-buffer-name-style 'forward)

;; 退出时自动保存当前光标的位置，并在下次打开相应文件时自动将光标定位到上一次的位置
;; (save-place-mode 1)

;; 进行缩进时不使用制表符（Tab）字符，而是使用空格字符进行缩进
(setq-default indent-tabs-mode nil)

(menu-bar-mode -1)     ; 隐藏菜单栏
(tool-bar-mode -1)
(scroll-bar-mode -1)

;;(set-frame-parameter (selected-frame)
;;                     'internal-border-width 0)

;; Line spacing, can be 0 for code and 1 or 2 for text
(setq-default line-spacing 2)

;; Underline line at descent position, not baseline position
;; x-underline-at-descent-line 是 Emacs 中一个用于定制下划线绘制位置的变量。当它的值为 t 时，Emacs 会将下划线绘制在当前字符的下缘线位置，而不是字符底部的基线位置。这通常用于改善下划线在一些字体中的呈现效果，因为一些字体的下沉线比基线更粗或更加突出，使得下划线在字符底部看起来可能会有些偏离或不对齐。
;; 需要注意的是，在使用 x-underline-at-descent-line 时，下划线的位置可能会影响到其他字符和行间距的位置，因此可能需要进行一些微调以达到最佳的显示效果。
(setq x-underline-at-descent-line t)


;; Line cursor and no blink
(set-default 'cursor-type  '(bar . 2))
;;(blink-cursor-mode 0)

;; No sound
(setq visible-bell t)
(setq ring-bell-function 'ignore)



;; 去除两侧边缘条（展示换行符等）No fringe but nice glyphs for truncated and wrapped lines
(fringe-mode '(0 . 0))

(defface fallback '((t :family "Fira Code"
                       :inherit 'face-faded))
  "Fallback")

(set-display-table-slot standard-display-table 'truncation
                        (make-glyph-code ?… 'fallback))
(set-display-table-slot standard-display-table 'wrap
                        (make-glyph-code ?↩ 'fallback))
(set-display-table-slot standard-display-table 'selective-display
                        (string-to-vector " …"))

;; yes or no
(setq original-y-or-n-p 'y-or-n-p)


;; 以16进制显示字节数
(setq display-raw-bytes-as-hex t)


;; ido mode
(require 'flx-ido)
(ido-mode 1)
(ido-everywhere 1)
(flx-ido-mode 1)
;; disable ido faces to see flx highlights.
(setq ido-enable-flex-matching t)
(setq ido-use-faces nil)

;; auto save
(require 'auto-save)
(auto-save-enable)
(setq auto-save-silent t)


(provide 'frame-setting)
