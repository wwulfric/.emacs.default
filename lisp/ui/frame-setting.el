;;; frame-setting.el --- Frame and window appearance -*- lexical-binding: t; -*-

(defconst my/ui-space-small 6 "Small UI spacing unit, in pixels.")
(defconst my/ui-editor-padding (* 4 my/ui-space-small)
  "Shared 24-pixel text padding for code and prose windows.")

(dolist (parameter `((width . 100) (height . 50)
                     (vertical-scroll-bars . nil)
                     (internal-border-width . 0)
                     (font . "PT Mono 14")))
  (setf (alist-get (car parameter) default-frame-alist) (cdr parameter)))

;; Window chrome reaches the frame edges; each content area owns its padding.
;; Completion and input-method child frames keep their own borders.
(defun my/frame-apply-spacing (frame)
  "Remove the outer border of GUI FRAME, leaving popup geometry alone."
  (when (and (display-graphic-p frame) (not (frame-parent frame)))
    (set-frame-parameter frame 'internal-border-width 0)))
(add-hook 'after-make-frame-functions #'my/frame-apply-spacing)
(dolist (frame (frame-list))
  (my/frame-apply-spacing frame))

(require 'init-typography)

;; Restore the native title bar and macOS traffic-light buttons on reload.
(when (eq system-type 'darwin)
  (add-to-list 'default-frame-alist '(undecorated-round . nil))
  (add-to-list 'default-frame-alist '(undecorated . nil))
  (dolist (frame (frame-list))
    (when (and (eq (window-system frame) 'ns)
               (not (frame-parent frame)))
      (modify-frame-parameters frame '((undecorated-round . nil)
                                       (undecorated . nil))))))

(require 'init-frame-title)

;; A real window divider spans header/tab lines as well as buffer text.
(setq window-divider-default-places 'right-only
      window-divider-default-right-width 1)
(window-divider-mode 1)

;; Number code buffers only; reading and utility buffers stay uncluttered.
;; Remove the previous global policy when this file is reloaded.
(remove-hook 'display-line-numbers-mode-hook #'my/line-numbers-exclude-dired)
(global-display-line-numbers-mode -1)

(defun my/prog-line-numbers ()
  "Enable line numbers in programming buffers."
  (display-line-numbers-mode 1))
(add-hook 'prog-mode-hook #'my/prog-line-numbers)

;; Apply the policy to buffers which are already open during a reload.
(dolist (buffer (buffer-list))
  (with-current-buffer buffer
    (display-line-numbers-mode (if (derived-mode-p 'prog-mode) 1 -1))))
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

(menu-bar-mode -1)     ; 隐藏菜单栏
(tool-bar-mode -1)
(scroll-bar-mode -1)

;; Shared header metrics for buffer tabs and the Dirvish sidebar.
(defvar my/ui-header-height 1.4
  "Shared height of buffer tabs and the Dirvish sidebar title, in font units.")

(defun my/ui-header-space (width)
  "Return a spacer display specification with WIDTH and shared header height."
  `(space :width ,width :height ,my/ui-header-height :ascent 75))

(defvar my/ui-mode-line-height 1.4
  "Minimum status-bar height in fixed-pitch font units.")

(defun my/ui-mode-line-space (width)
  "Return a WIDTH-column spacer keeping status bars level across windows."
  (propertize " " 'face 'fixed-pitch
              'display `(space :width ,width
                               :height ,my/ui-mode-line-height :ascent 80)))

;; Reserve the same height even when only one status bar contains CJK text.
(setq mode-line-front-space
      '(:eval (if (display-graphic-p) (my/ui-mode-line-space 1) "-")))

;; Line spacing, can be 0 for code and 1 or 2 for text
;; (setq-default line-spacing nil)
;; (setq-default default-text-properties '(line-spacing 0.25 line-height 1.25))


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



;; Dirvish owns its compact fringes; editor windows get their own text padding.
(fringe-mode '(0 . 0))

(defun my/frame-apply-window-padding (frame)
  "Pad editor text on GUI FRAME independently of sidebars and splits.
Fringes reserve the same space at exterior and interior edges, so opening
or closing Dirvish cannot remove or double it.  Tabs stay flush and optional
reading margins remain independent."
  (when (and (display-graphic-p frame) (not (frame-parent frame)))
    (dolist (window (window-list frame 'no-minibuffer))
      (with-current-buffer (window-buffer window)
        ;; Dirvish and other side windows manage their own fringes.
        (unless (or (window-parameter window 'window-side)
                    (derived-mode-p 'dired-mode)
                    (string-prefix-p " " (buffer-name)))
          (let* (;; Use buffer/frame defaults, never inherited split-window
                 ;; fringes, to avoid accumulating padding across changes.
                 (left (max (or left-fringe-width
                                (frame-parameter frame 'left-fringe) 0)
                            my/ui-editor-padding))
                 (right (max (or right-fringe-width
                                 (frame-parameter frame 'right-fringe) 0)
                             my/ui-editor-padding))
                 (desired (list left right t nil)))
            (unless (equal (window-fringes window) desired)
              (apply #'set-window-fringes window desired))))))))

(add-hook 'window-state-change-functions #'my/frame-apply-window-padding -10)
(dolist (frame (frame-list))
  (my/frame-apply-window-padding frame))

(defface fallback '((t :family "Fira Code"
                       :inherit shadow))
  "Fallback")

(set-display-table-slot standard-display-table 'truncation
                        (make-glyph-code ?… 'fallback))
(set-display-table-slot standard-display-table 'wrap
                        (make-glyph-code ?↩ 'fallback))
(set-display-table-slot standard-display-table 'selective-display
                        (string-to-vector " …"))

;; 以16进制显示字节数
(setq display-raw-bytes-as-hex t)


(provide 'frame-setting)
