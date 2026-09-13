;;; init-tab-line.el --- Buffer tab appearance and interaction -*- lexical-binding: t; -*-

;; Loaded after frame-setting, which defines the shared UI header spacing.
(require 'seq)

(defvar my/tab-line-hover-target nil
  "Window and tab currently under the mouse.")
(defvar my/tab-line-hover-timer nil)

(defun my/tab-line-update-hover ()
  "Refresh tab buttons only when the mouse enters or leaves a tab."
  (let* ((mouse (mouse-pixel-position))
         (frame (car mouse))
         (xy (cdr mouse))
         (position (when (and (frame-live-p frame)
                              (numberp (car xy)) (numberp (cdr xy)))
                     (posn-at-x-y (car xy) (cdr xy) frame)))
         (string (and position (posn-string position)))
         (tab (and (eq (posn-area position) 'tab-line) string
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
         (padding (apply #'propertize " " (text-properties-at 0 label))))
    ;; Share the vertical strut with Dirvish; keep the label font unchanged.
    (put-text-property 0 1 'display
                       (my/ui-header-space 1.2) padding)
    (concat padding label padding)))

(with-eval-after-load 'tab-line
  (setq tab-line-tab-name-format-function #'my/tab-line-format-with-padding)
  (add-hook 'tab-line-mode-hook #'my/tab-line-manage-hover-timer)
  (add-hook 'global-tab-line-mode-hook #'my/tab-line-manage-hover-timer)
  (my/tab-line-manage-hover-timer)
  (custom-theme-set-faces
   'user
   '(tab-line
     ((((background light)) :inherit default :height 1.0 :box nil :background "#F3F4F5")
      (((background dark)) :inherit default :height 1.0 :box nil :background "#25282D")))
   '(tab-line-tab
     ((t :inherit tab-line :box nil :weight normal)))
   '(tab-line-tab-inactive
     ((((background light)) :inherit tab-line-tab :box nil :foreground "#555B63" :background "#F3F4F5")
      (((background dark)) :inherit tab-line-tab :box nil :foreground "#B8BEC7" :background "#25282D")))
   '(tab-line-tab-current
     ((((background light)) :inherit tab-line-tab :box nil :weight bold :foreground "#245FA5" :background "#E3ECFA")
      (((background dark)) :inherit tab-line-tab :box nil :weight bold :foreground "#A8CFFF" :background "#33445C")))
   '(tab-line-highlight
     ((((background light)) :box nil :background "#E7E9ED" :foreground "#20252B")
      (((background dark)) :box nil :background "#3A3F47" :foreground "#F0F2F5"))))
  (tab-line-force-update t))

(provide 'init-tab-line)
;;; init-tab-line.el ends here
