;;; init-auto-save.el --- Save edited files when idle -*- lexical-binding: t; -*-

(defvar-local my/auto-save-declined-file nil
  "Visited file whose overwrite was declined during idle saving.")

(defun my/auto-save-clear-conflict ()
  "Resume idle saving after a successful save or revert."
  (setq my/auto-save-declined-file nil))

(defun my/auto-save-buffer ()
  "Save the current buffer if eligible, remembering a declined overwrite."
  (let ((remote (bound-and-true-p lsp-bridge-remote-file-flag)))
    (when (and (buffer-modified-p)
               (or buffer-file-name remote)
               (not buffer-read-only)
               (not (bound-and-true-p yas--active-snippets))
               (not (bound-and-true-p company-candidates))
               (zerop (or (bound-and-true-p corfu--total) 0))
               (not (bound-and-true-p org-capture-mode))
               (not (get-buffer (concat "CAPTURE-" (buffer-name))))
               (not (and my/auto-save-declined-file
                         (equal buffer-file-name my/auto-save-declined-file)
                         (not (verify-visited-file-modtime (current-buffer))))))
      (condition-case err
          (if remote
              (lsp-bridge-remote-save-buffer)
            (let ((save-silently t))
              (basic-save-buffer)))
        (error
         (if (and (equal err '(user-error "Save not confirmed"))
                  buffer-file-name
                  (not (verify-visited-file-modtime (current-buffer))))
             (setq my/auto-save-declined-file buffer-file-name)
           (message "Idle save of %s failed: %s" (buffer-name)
                    (error-message-string err))))))))

(defun my/auto-save-buffers ()
  "Save modified files when Emacs is idle and outside a recursive edit."
  (when (zerop (recursion-depth))
    (dolist (buffer (buffer-list))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer (my/auto-save-buffer))))))

;; Preserve the file settings previously supplied by the auto-save package.
(setq make-backup-files nil auto-save-default nil create-lockfiles nil)

;; Retire the old idle timer when reloading an already running session.
(when (featurep 'auto-save)
  (auto-save-disable))

(add-hook 'after-save-hook #'my/auto-save-clear-conflict)
(add-hook 'after-revert-hook #'my/auto-save-clear-conflict)

(defvar my/auto-save-timer nil)
(when (timerp my/auto-save-timer) (cancel-timer my/auto-save-timer))
(setq my/auto-save-timer (run-with-idle-timer 1 t #'my/auto-save-buffers))

(provide 'init-auto-save)
;;; init-auto-save.el ends here
