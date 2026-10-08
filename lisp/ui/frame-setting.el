;;; frame-setting.el --- Frame and window appearance -*- lexical-binding: t; -*-

(defconst my/ui-space-small 4 "Small UI spacing unit, in pixels.")
(defconst my/ui-editor-padding (* 4 my/ui-space-small)
  "Shared text padding for code and prose windows, in pixels.")

(defconst my/ui-status-padding my/ui-editor-padding
  "Horizontal padding at both edges of editor status bars, in pixels.")

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
(remove-hook 'display-line-numbers-mode-hook 'my/line-numbers-exclude-dired)
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

(require 'subr-x)

;; Compact status: native mode menus, contextual flags and cursor position.
(defvar lsp-bridge-diagnostic-records)
(defvar lsp-bridge-diagnostic-count)
(defvar-local my/ui-diagnostic-summary nil)

(defun my/ui-update-diagnostics ()
  "Cache diagnostic counts when the language server publishes an update."
  (setq my/ui-diagnostic-summary
        (when (and (boundp 'lsp-bridge-diagnostic-count)
                   (numberp lsp-bridge-diagnostic-count)
                   (> lsp-bridge-diagnostic-count 0))
          (if (/= lsp-bridge-diagnostic-count
                  (length (bound-and-true-p lsp-bridge-diagnostic-records)))
              ;; Records can be capped or filtered: don't mislabel the total.
              (format "诊断 %d" lsp-bridge-diagnostic-count)
            (let ((errors 0) (warnings 0))
              (dolist (record lsp-bridge-diagnostic-records)
                (pcase (plist-get record :severity)
                  (1 (setq errors (1+ errors)))
                  (2 (setq warnings (1+ warnings)))))
              (string-join
               (delq nil (list
                          (when (> errors 0)
                            (propertize (format "E%d" errors) 'face 'error))
                          (when (> warnings 0)
                            (propertize (format "W%d" warnings) 'face 'warning))))
               " ")))))
  (force-mode-line-update))

(with-eval-after-load 'lsp-bridge-diagnostic
  (add-hook 'lsp-bridge-diagnostic-update-hook #'my/ui-update-diagnostics)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (bound-and-true-p lsp-bridge-mode) (my/ui-update-diagnostics)))))

(defun my/ui-enabled-minor-modes ()
  "Return enabled registered minor modes, including modes with no lighter."
  (sort (delete-dups
         (seq-filter
          (lambda (mode) (and (symbolp mode) (boundp mode) (symbol-value mode)))
          (append minor-mode-list (mapcar #'car minor-mode-alist)
                  (mapcar #'car minor-mode-map-alist))))
        (lambda (a b) (string-lessp (symbol-name a) (symbol-name b)))))

(defun my/ui-mode-menu-action (buffer function &optional disable)
  "Make a menu command running FUNCTION in BUFFER.
When DISABLE is non-nil, explicitly turn the mode off rather than toggle it."
  (lambda ()
    (interactive)
    (unless (buffer-live-p buffer) (user-error "原缓冲区已关闭"))
    (with-current-buffer buffer
      (if disable
          (let ((current-prefix-arg -1)) (call-interactively function))
        (funcall function)))))

(defun my/ui-minor-mode-menu (mode menus)
  "Build a submenu for enabled MODE using its native MENUS when available."
  (let* ((buffer (current-buffer))
         (command (or (get mode :minor-mode-function) mode))
         (map (or (cdr (assq mode minor-mode-overriding-map-alist))
                  (cdr (assq mode minor-mode-map-alist))))
         (native (cdr (assq mode menus)))
         (menu (make-sparse-keymap (symbol-name mode))))
    ;; Insert in reverse order: define-key prepends items to a sparse keymap.
    (when (commandp command)
      (define-key menu [disable]
        `(menu-item ,(if (local-variable-p mode) "关闭此模式" "关闭此模式（全局）")
                    ,(my/ui-mode-menu-action buffer command t))))
    (when (keymapp map)
      (define-key menu [bindings]
        `(menu-item "快捷键"
                    ,(my/ui-mode-menu-action
                      buffer (lambda () (describe-keymap map))))))
    (define-key menu [help]
      `(menu-item "帮助"
                  ,(my/ui-mode-menu-action
                    buffer (lambda ()
                             (if (fboundp command) (describe-function command)
                               (describe-variable mode))))))
    (when (keymapp native)
      (define-key menu [native] `(menu-item "模式操作" ,native)))
    menu))

(defun my/ui-visible-mode-lighters ()
  "Return enabled, visible minor modes and their rendered native labels.
Preserve `minor-mode-alist' order and respect Emacs' collapse preference."
  (let ((collapse (bound-and-true-p mode-line-collapse-minor-modes)) result)
    (dolist (entry minor-mode-alist)
      (let ((mode (car entry)))
        (when (and (symbolp mode) (boundp mode) (symbol-value mode)
                   (not (assq mode result))
                   (cond ((not collapse) t)
                         ((eq (car-safe collapse) 'not) (memq mode (cdr collapse)))
                         ((listp collapse) (not (memq mode collapse)))
                         (t nil)))
          (let ((label (string-trim
                        (substring-no-properties
                         (format-mode-line `("" ,@(cdr entry)))))))
            (unless (string-empty-p label)
              (push (cons mode label) result))))))
    (nreverse result)))

(defun my/ui-build-mode-menu ()
  "Build native visible modes first, with other enabled modes in a submenu."
  (let* ((menu (make-sparse-keymap "模式"))
         (more-menu (make-sparse-keymap "更多已启用模式"))
         (buffer (current-buffer)))
    (run-hooks 'activate-menubar-hook 'menu-bar-update-hook)
    (let* ((visible (my/ui-visible-mode-lighters))
           (others (seq-remove (lambda (mode) (assq mode visible))
                               (my/ui-enabled-minor-modes)))
           (native-menus (minor-mode-key-binding [menu-bar])))
      (define-key menu [help]
        `(menu-item "全部模式帮助" ,(my/ui-mode-menu-action buffer #'describe-mode)))
      (when others
        (dolist (mode (reverse others))
          (define-key more-menu (vector mode)
            `(menu-item ,(concat (symbol-name mode)
                                 (unless (local-variable-p mode) " [全局]"))
                        ,(my/ui-minor-mode-menu mode native-menus))))
        (define-key menu [more]
          `(menu-item ,(format "更多已启用模式 (%d)" (length others)) ,more-menu)))
      (dolist (entry (reverse visible))
        (define-key menu (vector (car entry))
          `(menu-item ,(concat (cdr entry)
                               (unless (local-variable-p (car entry)) " [全局]"))
                      ,(my/ui-minor-mode-menu (car entry) native-menus)))))
    (let* ((major (make-sparse-keymap (symbol-name major-mode)))
           (native (and (current-local-map)
                        (lookup-key (current-local-map) [menu-bar])))
           (map (current-local-map)))
      (define-key major [help]
        `(menu-item "帮助" ,(my/ui-mode-menu-action buffer #'describe-mode)))
      (when (keymapp map)
        (define-key major [bindings]
          `(menu-item "快捷键" ,(my/ui-mode-menu-action
                                 buffer (lambda () (describe-keymap map))))))
      (when (keymapp native)
        (define-key major [native] `(menu-item "模式操作" ,native)))
      (define-key menu [major]
        `(menu-item ,(or (and (stringp mode-name) mode-name) (symbol-name major-mode))
                    ,major)))
    menu))

(defun my/ui-show-mode-menu (&optional event)
  "Show all mode menus for the window clicked in EVENT, or the current buffer."
  (interactive (list (when (mouse-event-p last-input-event) last-input-event)))
  (when event
    (let ((window (posn-window (event-start event))))
      (when (window-live-p window) (select-window window))))
  (popup-menu (my/ui-build-mode-menu) (or event (posn-at-point))))

(defvar my/ui-mode-menu-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mode-line down-mouse-1] #'my/ui-show-mode-menu)
    (define-key map [mode-line down-mouse-3] #'my/ui-show-mode-menu)
    (define-key map [mode-line mouse-2] #'describe-mode)
    map)
  "Unified mode menu on the status button.")

(defun my/ui-status-line ()
  "Return status for the window being rendered, retaining native mode menus.
Window-local point is supplied by Emacs during mode-line redisplay.  Respect
package-owned local mode lines by changing only the default format."
  (let* ((active (mode-line-window-selected-p))
         (width (window-body-width))
         (tabbed (and (bound-and-true-p tab-line-mode) tab-line-format))
         (flags (delq nil
                      (list (when (and (not tabbed) (buffer-modified-p)) "●")
                            (when buffer-read-only "只读")
                            (when (buffer-narrowed-p) "窄域")
                            (when defining-kbd-macro "录制")
                            (when (and active current-input-method)
                              current-input-method-title))))
         (writing (and active (>= width 65)
                       (delq nil
                             (list (when (bound-and-true-p my/writing-layout-mode) "阅读")
                                   (when (bound-and-true-p my/writing-numbering-mode) "编号")))))
         (position (and active
                        (format "%s  %d%%"
                                (format-mode-line "%l:%c")
                                (/ (* 100 (- (point) (point-min)))
                                   (max 1 (- (point-max) (point-min)))))))
         (diagnostics (and active (>= width 45)
                           (bound-and-true-p lsp-bridge-mode)
                           my/ui-diagnostic-summary))
         (right (string-join (delq nil (list diagnostics position)) "  "))
         (identity (when (not tabbed)
                     (truncate-string-to-width (buffer-name) (max 5 (/ width 3)) nil nil "…")))
         (name (when (>= width 55) (format-mode-line mode-name)))
         (left (string-join (append (delq nil (list identity name)) flags writing) " · "))
         (room (max 0 (- width 3
                         (* 2 (ceiling my/ui-status-padding (frame-char-width)))
                         (string-width right))))
         (left (truncate-string-to-width left room nil nil "…")))
    (list
     ;; Emit the spacer directly: mode-line-front-space can be suppressed
     ;; when its nested :eval is reached through an untrusted variable.
     (my/ui-mode-line-space (if (display-graphic-p) (list my/ui-status-padding) 1))
     (propertize "☰" 'local-map my/ui-mode-menu-map
                 'mouse-face 'mode-line-highlight
                 'help-echo "左键/右键：模式操作、已启用的次要模式与快捷键；中键：全部模式帮助")
     " " (string-replace "%" "%%" left)
     (when (not (string-empty-p right))
       (propertize " " 'display
                   (if (display-graphic-p)
                       `(space :align-to (- (+ right right-fringe right-margin)
                                            (,my/ui-status-padding)
                                            (,(string-pixel-width right))))
                     `(space :align-to (- right ,(1+ (string-width right)))))))
     (string-replace "%" "%%" right)
     (propertize " " 'display
                 `(space :width ,(if (display-graphic-p)
                                     (list my/ui-status-padding) 1))))))

(setq-default mode-line-format
              '((:eval (my/ui-status-line))))

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
  "Fallback glyphs for truncation and continuation indicators."
  :group 'faces)

(set-display-table-slot standard-display-table 'truncation
                        (make-glyph-code ?… 'fallback))
(set-display-table-slot standard-display-table 'wrap
                        (make-glyph-code ?↩ 'fallback))
(set-display-table-slot standard-display-table 'selective-display
                        (string-to-vector " …"))

;; 以16进制显示字节数
(setq display-raw-bytes-as-hex t)


(provide 'frame-setting)
