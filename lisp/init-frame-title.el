;;; init-frame-title.el --- Cached project titles -*- lexical-binding: t; -*-

(require 'project)
(require 'vc-git)
(require 'subr-x)

(defvar my/frame-title-cache (make-hash-table :test #'equal)
  "Directory to (timestamp . title).  Redisplay only reads this cache.")
(defvar my/frame-title-processes (make-hash-table :test #'equal)
  "Directory to the pending asynchronous Git process.")
(defvar my/frame-title-refresh-timer nil)
(defvar my/frame-title-retry-timer nil)

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

(defun my/frame-title-query-git (directory root name &optional detached)
  "Resolve DIRECTORY's branch asynchronously in ROOT, with project NAME.
DETACHED requests a short revision after the symbolic branch lookup fails."
  (let ((default-directory root)
        (output ""))
    (condition-case nil
        (puthash
         directory
         (make-process
          :name "emacs-frame-title-git"
          :command (if detached
                       '("git" "rev-parse" "--short" "HEAD")
                     '("git" "symbolic-ref" "--quiet" "--short" "HEAD"))
          :connection-type 'pipe :noquery t :coding 'utf-8-unix
          :filter (lambda (_process text) (setq output (concat output text)))
          :sentinel
          (lambda (process _event)
            (when (and (memq (process-status process) '(exit signal))
                       (eq process (gethash directory my/frame-title-processes)))
              (remhash directory my/frame-title-processes)
              (let ((branch (string-trim output)))
                (cond
                 ((and (eq (process-status process) 'exit)
                       (zerop (process-exit-status process))
                       (not (string-empty-p branch)))
                  (my/frame-title-store
                   directory (concat name " · ⎇ "
                                     (if detached "detached " "") branch)))
                 ((and (not detached) (eq (process-status process) 'exit)
                       (= (process-exit-status process) 1))
                  (my/frame-title-query-git directory root name t))
                 (t (my/frame-title-store directory name)))))))
         my/frame-title-processes)
      (error (my/frame-title-store directory name)))))

(defun my/frame-title-refresh-directory (directory)
  "Refresh DIRECTORY outside redisplay, at most once every three seconds."
  (let* ((cached (gethash directory my/frame-title-cache))
         (remaining (and cached (- 3 (- (float-time) (car cached))))))
    (cond
     ((gethash directory my/frame-title-processes))
     ((and remaining (> remaining 0))
      ;; A branch change inside the cache lifetime must not wait for another key.
      (unless (timerp my/frame-title-retry-timer)
        (setq my/frame-title-retry-timer
              (run-with-timer remaining nil #'my/frame-title-retry-refresh))))
     (t
      (let ((name (my/frame-title-directory-name directory)))
        (condition-case nil
            (if (file-remote-p directory)
                ;; A remote title must never start a TRAMP connection.
                (my/frame-title-store directory name)
              (let* ((default-directory directory)
                     (project (project-current nil directory))
                     (root (vc-git-root directory)))
                (when project (setq name (project-name project)))
                (if root
                    (progn
                      ;; Keep the previous branch visible while Git runs.
                      (my/frame-title-store directory (or (cdr cached) name))
                      (my/frame-title-query-git directory root name))
                  (my/frame-title-store directory name))))
          (error (my/frame-title-store directory name))))))))

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

(defun my/frame-title-retry-refresh ()
  "Queue an idle refresh after the previous cache entry expires."
  (setq my/frame-title-retry-timer nil)
  (my/frame-title-schedule-refresh))

(defun my/frame-title-source-refresh ()
  "Invalidate the current source buffer's title when its origin changes."
  (remhash (my/frame-title-directory) my/frame-title-cache)
  (my/frame-title-schedule-refresh))

;; Reloading must not leave a timer or an old callback able to overwrite titles.
(when (timerp my/frame-title-refresh-timer)
  (cancel-timer my/frame-title-refresh-timer))
(setq my/frame-title-refresh-timer nil)
(when (timerp my/frame-title-retry-timer)
  (cancel-timer my/frame-title-retry-timer))
(setq my/frame-title-retry-timer nil)
(maphash (lambda (_directory process)
           (set-process-sentinel process #'ignore)
           (when (process-live-p process) (delete-process process)))
         my/frame-title-processes)
(clrhash my/frame-title-processes)
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
