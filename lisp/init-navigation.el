;;; init-navigation.el --- Unified position history -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'xref)

(setq xref-history-storage #'xref-global-history)

(defvar my/navigation-inhibit nil)
(defvar my/navigation-generation 0)
(defvar my/navigation-start nil)
(defvar my/navigation-min-lines 8)

(defun my/navigation-note-push (&rest _)
  (cl-incf my/navigation-generation))
(advice-add 'xref-push-marker-stack :after #'my/navigation-note-push)

(defun my/navigation-origin ()
  "Return an origin marker for a visible file buffer."
  (when (and buffer-file-name (not (minibufferp)))
    (point-marker)))

(defun my/navigation-moved-p (origin)
  (and (marker-buffer origin)
       (or (not (eq (marker-buffer origin) (current-buffer)))
           (/= (marker-position origin) (point)))))

(defun my/navigation-around (original &rest args)
  "Record the departure of a completed synchronous navigation."
  (if my/navigation-inhibit
      (apply original args)
    (let ((origin (my/navigation-origin))
          (generation my/navigation-generation)
          (my/navigation-inhibit t))
      (unwind-protect
          (prog1 (apply original args)
            (when (and origin
                       (= generation my/navigation-generation)
                       (my/navigation-moved-p origin))
              (xref-push-marker-stack origin)
              (setq origin nil)))
        (when origin (set-marker origin nil))))))

(defun my/navigation-without-recording (original &rest args)
  (let ((my/navigation-inhibit t))
    (apply original args)))

(dolist (command '(xref-go-back xref-go-forward))
  (advice-add command :around #'my/navigation-without-recording))

;; Ordinary commands: record file/buffer changes and large, non-editing
;; movements. A single character/line step does not become a history entry.
(defun my/navigation-pre-command ()
  ;; Keep the departure through minibuffer prompts and non-file UIs such
  ;; as the Dirvish sidebar, until a file is selected again.
  (when (and (not (minibufferp))
             (or buffer-file-name my/navigation-inhibit
                 (memq this-command '(xref-go-back xref-go-forward))))
    (when my/navigation-start
      (set-marker (car my/navigation-start) nil))
    (setq my/navigation-start nil)
    (unless (or my/navigation-inhibit
                (bound-and-true-p isearch-mode)
                (memq this-command '(xref-go-back xref-go-forward)))
      (when-let* ((origin (my/navigation-origin)))
        (setq my/navigation-start
              (list origin (buffer-chars-modified-tick)
                    my/navigation-generation))))))

(defun my/navigation-large-move-p (origin)
  "Check line distance without scanning from the start of the buffer."
  (let* ((destination (line-beginning-position))
         (direction (if (< origin (point)) 1 -1)))
    (save-excursion
      (goto-char origin)
      (and (zerop (forward-line (* direction my/navigation-min-lines)))
           (if (> direction 0)
               (>= destination (point))
             (<= destination (point)))))))

(defun my/navigation-post-command ()
  (when (and my/navigation-start buffer-file-name (not (minibufferp)))
    (pcase-let ((`(,origin ,tick ,generation) my/navigation-start))
      (setq my/navigation-start nil)
      (unwind-protect
          (when (and (not my/navigation-inhibit)
                     (= generation my/navigation-generation)
                     buffer-file-name
                     (my/navigation-moved-p origin)
                     (or (memq this-command '(mouse-set-point my/lsp-click))
                         (not (eq (marker-buffer origin) (current-buffer)))
                         (and (= tick (buffer-chars-modified-tick))
                              (my/navigation-large-move-p origin))))
            (xref-push-marker-stack origin)
            (setq origin nil))
        (when origin (set-marker origin nil))))))

(add-hook 'pre-command-hook #'my/navigation-pre-command)
(add-hook 'post-command-hook #'my/navigation-post-command)

;; Isearch spans multiple command-loop iterations; record its original point
;; only when the search ends, including targets on the same line.
(defun my/navigation-isearch-end ()
  (when (and (not my/navigation-inhibit) buffer-file-name
             (boundp 'isearch-opoint) isearch-opoint
             (/= isearch-opoint (point)))
    (xref-push-marker-stack (copy-marker isearch-opoint))))
(add-hook 'isearch-mode-end-hook #'my/navigation-isearch-end)

(dolist (command '(imenu goto-line))
  (advice-add command :around #'my/navigation-around))

(with-eval-after-load 'lsp-bridge
  ;; Actual asynchronous definition result, synchronous file navigation,
  ;; and the separate Emacs Lisp definition path.
  (dolist (command '(lsp-bridge-define--jump
                    lsp-bridge-jump-to-file
                    acm-backend-elisp-find-def
                    lsp-bridge-diagnostic-jump-next
                    lsp-bridge-diagnostic-jump-prev))
    (advice-add command :around #'my/navigation-around))
  (dolist (map (list lsp-bridge-mode-map lsp-bridge-source-mode-map))
    (define-key map (kbd "s-[") #'xref-go-back)
    (define-key map (kbd "s-]") #'xref-go-forward)))

(global-set-key (kbd "s-[") #'xref-go-back)
(global-set-key (kbd "s-]") #'xref-go-forward)
(global-set-key (kbd "C-c n b") #'xref-go-back)
(global-set-key (kbd "C-c n f") #'xref-go-forward)

(provide 'init-navigation)
;;; init-navigation.el ends here
