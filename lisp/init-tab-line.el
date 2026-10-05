;;; init-tab-line.el --- Buffer tab appearance and interaction -*- lexical-binding: t; -*-

;; Loaded after frame-setting, which defines the shared UI header spacing.
(require 'seq)
(require 'tab-line)

(defun my/tab-line-buffer-visible-p (buffer)
  "Return non-nil when BUFFER belongs in an editor tab strip."
  (with-current-buffer buffer
    (not (or (string-prefix-p " " (buffer-name))
             tab-line-exclude
             (memq major-mode tab-line-exclude-modes)
             (get major-mode 'tab-line-exclude)))))

(defun my/tab-line-filter-buffers (buffers)
  "Remove internal sidebar and excluded buffers from BUFFERS."
  (seq-filter #'my/tab-line-buffer-visible-p buffers))

(defun my/tab-line-refresh-window-buffers (frame)
  "Enable tabs in newly displayed process buffers on FRAME.
Process buffers can be created without running a major-mode hook."
  (when global-tab-line-mode
    (dolist (window (window-list frame 'no-minibuffer))
      (with-current-buffer (window-buffer window)
        (if (my/tab-line-buffer-visible-p (current-buffer))
            (unless tab-line-mode (tab-line-mode--turn-on))
          (when tab-line-mode (tab-line-mode -1)))))))

(advice-add 'tab-line-tabs-window-buffers :filter-return #'my/tab-line-filter-buffers)
(add-hook 'window-buffer-change-functions #'my/tab-line-refresh-window-buffers)

(defvar my/tab-line-hover-target nil
  "Window and tab currently under the mouse.")
(defvar my/tab-line-hover-timer nil)

(defun my/tab-line-update-hover ()
  "Refresh tab buttons only when the mouse enters or leaves a tab."
  (let* ((mouse (mouse-pixel-position))
         (frame (car mouse))
         (xy (cdr mouse))
         (position (when (and (frame-live-p frame)
                              (integerp (car xy)) (integerp (cdr xy))
                              (<= 0 (car xy)) (<= 0 (cdr xy))
                              (< (car xy) (frame-pixel-width frame))
                              (< (cdr xy) (frame-pixel-height frame)))
                     (posn-at-x-y (car xy) (cdr xy) frame)))
         (string (and position (posn-string position)))
         (tab (and position (eq (posn-area position) 'tab-line) string
                   (get-text-property (cdr string) 'tab (car string))))
         (target (and tab (cons (posn-window position) tab))))
    (unless (equal target my/tab-line-hover-target)
      (setq my/tab-line-hover-target target)
      (tab-line-force-update t))))

(defun my/tab-line-manage-hover-timer ()
  "Track hover while at least one buffer uses Tab-Line mode."
  (let ((enabled (seq-some
                  (lambda (buffer) (buffer-local-value 'tab-line-mode buffer))
                  (buffer-list))))
    (cond
     ((and enabled (not (timerp my/tab-line-hover-timer)))
      (setq my/tab-line-hover-timer
            (run-with-timer 0 0.1 #'my/tab-line-update-hover)))
     ((not enabled)
      (when (timerp my/tab-line-hover-timer)
        (cancel-timer my/tab-line-hover-timer))
      (setq my/tab-line-hover-timer nil
            my/tab-line-hover-target nil)))))

(defface my/tab-line-source
  '((t (:inherit tab-line-tab)))
  "External source tab; colors are supplied by the active theme."
  :group 'tab-line)

(defface my/tab-line-source-current
  '((t (:inherit tab-line-tab-current)))
  "Selected external source tab; colors are supplied by the active theme."
  :group 'tab-line)

(defun my/tab-line-format-with-padding (tab tabs)
  "Add clickable padding around the standard TAB label and close button."
  (let* ((selected (if (bufferp tab) (eq tab (window-buffer))
                     (alist-get 'selected tab)))
         (show-close (or (and selected (mode-line-window-selected-p))
                         (equal my/tab-line-hover-target
                                (cons (selected-window) tab))))
         ;; Reserve a slot so showing the close button does not shift tabs.
         ;; The hidden slot selects the tab; it must never close it.
         (tab-line-close-button-show t)
         (tab-line-close-button
          (propertize (if show-close " × " "   ")
                      'keymap (if show-close tab-line-tab-close-map tab-line-tab-map)
                      'help-echo (if show-close "Click to close tab" "Click to select tab")
                      'follow-link 'ignore))
         (label (tab-line-tab-name-format-default tab tabs))
         padding)
    (when (and (bufferp tab)
               (fboundp 'lsp-bridge-source-buffer-p)
               (lsp-bridge-source-buffer-p tab))
      ;; Decorate after the standard formatter, which overwrites name faces
      ;; and help text.  Leave the close button's tooltip/keymap intact.
      (let ((end (- (length label) (length tab-line-close-button))))
        (with-current-buffer tab
          (put-text-property
           0 end 'help-echo
           (format "依赖源码（只读）\n来源：%s\n文件：%s"
                   (or (lsp-bridge-source-origin-directory) "未知项目")
                   buffer-file-name)
           label))
        (add-face-text-property
         0 (length label)
         (if (and selected (mode-line-window-selected-p))
             'my/tab-line-source-current
           'my/tab-line-source)
         nil label)))
    (setq padding (apply #'propertize " " (text-properties-at 0 label)))
    ;; Share the vertical strut with Dirvish; keep the label font unchanged.
    (put-text-property 0 1 'display
                       (my/ui-header-space 1.2) padding)
    (concat padding label padding)))

(defun my/tab-line-source-refresh ()
  "Refresh source tab appearance and origin tooltips in all windows."
  (tab-line-force-update t))

(with-eval-after-load 'lsp-bridge-source
  (add-hook 'lsp-bridge-source-context-update-hook #'my/tab-line-source-refresh)
  (add-hook 'lsp-bridge-source-mode-hook #'my/tab-line-source-refresh))

(with-eval-after-load 'tab-line
  (setq tab-line-tab-name-function #'tab-line-tab-name-buffer)
  (setq tab-line-tab-name-format-function #'my/tab-line-format-with-padding)
  (add-hook 'tab-line-mode-hook #'my/tab-line-manage-hover-timer)
  (add-hook 'global-tab-line-mode-hook #'my/tab-line-manage-hover-timer)
  (my/tab-line-manage-hover-timer)
  (tab-line-force-update t))

(global-tab-line-mode 1)

(provide 'init-tab-line)
;;; init-tab-line.el ends here
