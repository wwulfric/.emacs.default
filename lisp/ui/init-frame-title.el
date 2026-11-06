;;; init-frame-title.el --- Cached project titles -*- lexical-binding: t; -*-

(require 'project)
(require 'subr-x)

(defvar my/frame-title-cache (make-hash-table :test #'equal)
  "Directory to (timestamp . title).  Redisplay only reads this cache.")
(defvar my/frame-title-refresh-timer nil)

(defun my/frame-title-directory ()
  "Return the current buffer's project context without probing the filesystem."
  (or (and (fboundp 'lsp-bridge-source-origin-directory)
           (lsp-bridge-source-origin-directory))
      default-directory))

(defun my/frame-title-directory-name (directory)
  "Return a short label for DIRECTORY without resolving it."
  (let ((name (file-name-nondirectory (directory-file-name directory))))
    (if (string-empty-p name) directory name)))

(defun my/frame-title ()
  "Read the cached title; never discover projects or invoke Git during redisplay."
  (let ((directory (my/frame-title-directory)))
    (or (cdr (gethash directory my/frame-title-cache))
        (my/frame-title-directory-name directory))))

(defun my/frame-title-store (directory title)
  "Cache TITLE for DIRECTORY and request a title-bar redraw."
  (puthash directory (cons (float-time) title) my/frame-title-cache)
  (force-mode-line-update t))

(defun my/frame-title-refresh-directory (directory)
  "Refresh DIRECTORY's project name outside redisplay, at most every three seconds."
  (let ((cached (gethash directory my/frame-title-cache)))
    (unless (and cached (< (- (float-time) (car cached)) 3))
      (let ((name (my/frame-title-directory-name directory)))
        (condition-case nil
            (unless (file-remote-p directory)
              ;; A remote title must never start a TRAMP connection.
              (when-let* ((project (project-current nil directory)))
                (setq name (project-name project))))
          (error nil))
        (my/frame-title-store directory name)))))

(defun my/frame-title-refresh ()
  "Update visible, focused GUI frames after Emacs becomes idle."
  (setq my/frame-title-refresh-timer nil)
  (dolist (frame (frame-list))
    (when (and (display-graphic-p frame) (not (frame-parent frame))
               (eq (frame-visible-p frame) t) (frame-focus-state frame))
      (with-current-buffer (window-buffer (frame-selected-window frame))
        (my/frame-title-refresh-directory (my/frame-title-directory))))))

(defun my/frame-title-schedule-refresh (&rest _)
  "Coalesce context changes into one refresh after 0.3 seconds of idle time."
  (unless (timerp my/frame-title-refresh-timer)
    (setq my/frame-title-refresh-timer
          (run-with-idle-timer 0.3 nil #'my/frame-title-refresh))))

(defun my/frame-title-source-refresh ()
  "Invalidate the current source buffer's title when its origin changes."
  (remhash (my/frame-title-directory) my/frame-title-cache)
  (my/frame-title-schedule-refresh))

;; Reloading must not leave a timer or an old callback able to overwrite titles.
(when (timerp my/frame-title-refresh-timer)
  (cancel-timer my/frame-title-refresh-timer))
(setq my/frame-title-refresh-timer nil)
(clrhash my/frame-title-cache)

(add-hook 'post-command-hook #'my/frame-title-schedule-refresh)
(add-hook 'window-buffer-change-functions #'my/frame-title-schedule-refresh)
(add-hook 'after-make-frame-functions #'my/frame-title-schedule-refresh)
(add-function :after after-focus-change-function #'my/frame-title-schedule-refresh)
(with-eval-after-load 'lsp-bridge-source
  (add-hook 'lsp-bridge-source-context-update-hook #'my/frame-title-source-refresh)
  (add-hook 'lsp-bridge-source-mode-hook #'my/frame-title-source-refresh))

(setq frame-title-format '(:eval (my/frame-title)))
(my/frame-title-schedule-refresh)
(force-mode-line-update t)

(provide 'init-frame-title)
;;; init-frame-title.el ends here
