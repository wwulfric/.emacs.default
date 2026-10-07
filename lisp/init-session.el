;;; init-session.el --- Global history, recent files and places -*- lexical-binding: t; -*-

;;; Commentary:
;; Persistent state shared by every project.  Generated files live under
;; var/ instead of the configuration root.  Per-project window and tab
;; sessions belong to init-workspace.el.

;;; Code:

(defconst my/var-directory (expand-file-name "var/" user-emacs-directory)
  "Directory for files Emacs writes on its own.")

(defun my/var-file (name)
  "Return NAME inside `my/var-directory', creating its parent directory."
  (let ((file (expand-file-name name my/var-directory)))
    (make-directory (if (directory-name-p file) file (file-name-directory file)) t)
    file))

(defun my/var-migrate (old new)
  "Move the legacy state file OLD to NEW unless NEW already exists."
  (let ((old (expand-file-name old user-emacs-directory)))
    (when (and (file-exists-p old) (not (file-exists-p new)))
      (rename-file old new))
    new))

;; Must be set before smex and ido first read their files.
(setq smex-save-file (my/var-migrate "smex-items" (my/var-file "smex-items"))
      ido-save-directory-list-file (my/var-migrate "ido.last" (my/var-file "ido.last"))
      project-list-file (my/var-migrate "projects" (my/var-file "projects")))

;; Recent files feed the start page.  Never probe remote files at startup.
(setq recentf-save-file (my/var-migrate "recentf" (my/var-file "recentf"))
      recentf-max-saved-items 200
      recentf-auto-cleanup 'never
      recentf-exclude (list (concat "\\`" (regexp-quote my/var-directory))
                            "/\\.git/" "COMMIT_EDITMSG\\'"))
(recentf-mode 1)

(defvar my/recentf-save-timer nil)
(when (timerp my/recentf-save-timer) (cancel-timer my/recentf-save-timer))
(setq my/recentf-save-timer
      (run-with-idle-timer 300 t (lambda ()
                                   (let ((inhibit-message t))
                                     (recentf-save-list)))))

;; Minibuffer and search history.  The kill ring may hold secrets: not saved.
(setq savehist-file (my/var-file "history")
      savehist-additional-variables '(search-ring regexp-search-ring)
      history-length 300
      history-delete-duplicates t)
(savehist-mode 1)

;; Remember the position in every file, including files outside projects.
;; A restored workspace sets its own positions after this has run.
(setq save-place-file (my/var-file "places"))
(save-place-mode 1)

(provide 'init-session)
;;; init-session.el ends here
