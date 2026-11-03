;;; init-project-files.el --- List a project's Git submodules at once -*- lexical-binding: t; -*-

;;; Commentary:
;; project.el lists the files of a Git project, submodules included, with
;; one `git ls-files' per repository, each waiting for the last.  Untracked
;; files make every call walk its directories, so this configuration's 34
;; submodules took half a second each time the search window opened.
;;
;; Here project.el lists them twice.  The first time, each `git ls-files'
;; it asks for is only started, all of them at once; the second time,
;; project.el reads their output in its place.  So the files listed are
;; exactly those project.el lists alone.

;;; Code:

(require 'project)
(require 'vc-git)

(declare-function vc-git--env-vars "vc-git" (&optional command))

(defvar my/project-git-pass nil
  "While project.el lists a Git project: `start' or `read'.")

(defvar my/project-git-processes nil
  "Each `git ls-files' started, as ((DIRECTORY . FLAGS) PROCESS ERRORS).")

(defun my/project-git-start (flags)
  "Start `git ls-files' FLAGS as `vc-git-command' would run it."
  (let* ((process-environment (append (vc-git--env-vars (car flags))
                                      process-environment))
         (coding-system-for-read (or coding-system-for-read
                                     vc-git-log-output-coding-system))
         (errors (make-pipe-process :name "project-ls-files-errors"
                                    :buffer nil :noquery t)))
    (push (list (cons default-directory flags)
                (make-process :name "project-ls-files"
                              :buffer (generate-new-buffer " *project-ls-files*" t)
                              :command (append (list vc-git-program "--no-pager") flags)
                              :connection-type 'pipe
                              :stderr errors
                              :sentinel #'ignore
                              :noquery t)
                errors)
          my/project-git-processes)))

(defun my/project-git-output (flags)
  "Return what `git ls-files' FLAGS printed, or nil if it failed."
  (when-let* ((process (cadr (assoc (cons default-directory flags)
                                    my/project-git-processes))))
    ;; Until it has exited and all its output has been read.
    (while (accept-process-output process))
    (and (zerop (process-exit-status process))
         (with-current-buffer (process-buffer process)
           (buffer-string)))))

(defun my/project-git-command (git-command buffer okstatus file-or-list &rest flags)
  "Start or read `git ls-files' FLAGS for project.el, else run GIT-COMMAND.
BUFFER, OKSTATUS and FILE-OR-LIST are those of `vc-git-command'."
  (pcase (and (equal (car flags) "ls-files") my/project-git-pass)
    ('start (my/project-git-start flags) 0)
    ((and 'read (let (and output (pred stringp)) (my/project-git-output flags)))
     (with-current-buffer buffer (insert output))
     0)
    (_ (apply git-command buffer okstatus file-or-list flags))))

(defun my/project-git-list-files (list-files dir extra-ignores)
  "Call LIST-FILES on DIR and EXTRA-IGNORES, running its Git calls at once."
  (if (or my/project-git-pass (file-remote-p dir))
      (funcall list-files dir extra-ignores)
    (let ((my/project-git-processes nil))
      (advice-add 'vc-git-command :around #'my/project-git-command)
      (unwind-protect
          (progn
            (let ((my/project-git-pass 'start))
              (funcall list-files dir extra-ignores))
            (let ((my/project-git-pass 'read))
              (funcall list-files dir extra-ignores)))
        (advice-remove 'vc-git-command #'my/project-git-command)
        (pcase-dolist (`(,_ ,process ,errors) my/project-git-processes)
          (delete-process errors)
          (delete-process process)
          (kill-buffer (process-buffer process)))))))

(advice-add 'vc-git-project-list-files :around #'my/project-git-list-files)

(provide 'init-project-files)
;;; init-project-files.el ends here
