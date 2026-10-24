;;; git-sidebar.el --- Color the project sidebar by Git status -*- lexical-binding: t; -*-

;;; Commentary:
;; As in IntelliJ's Project view, a changed file's name takes the color of
;; its change, and a folder holding changes is drawn as modified (or as
;; unversioned when it holds only new files).  The sidebar asks for the
;; face through `my/sidebar-name-face-function'; names are drawn again
;; when the repository's snapshot changes.

;;; Code:

(require 'git-islands-core)
(require 'git-islands-faces)
(require 'init-sidebar)

(defvar my/git-sidebar-faces (make-hash-table :test #'equal)
  "Repository root to a table of absolute path to face.")

(defvar-local my/git-sidebar-root nil
  "Repository the sidebar lists, or nil outside one.")

(defconst my/git-sidebar-folder-rank
  '((git-islands-conflict . 3) (git-islands-modified . 2) (git-islands-untracked . 1))
  "How strongly a change colors the folders holding it.")

(defun my/git-sidebar-index (status)
  "Return the table of path to face for snapshot STATUS."
  (let ((root (git-islands-status-root status))
        (table (make-hash-table :test #'equal)))
    (dolist (entry (git-islands-status-entries status))
      (let* ((face (git-islands-change-face (git-islands-entry-change entry)))
             (folder-face (if (memq face '(git-islands-conflict git-islands-untracked))
                              face
                            'git-islands-modified))
             (rank (alist-get folder-face my/git-sidebar-folder-rank))
             (path (directory-file-name (expand-file-name (git-islands-entry-path entry) root))))
        (puthash path face table)
        (let ((directory (file-name-directory path)))
          (while (and directory (string-prefix-p root directory)
                      (not (equal (file-name-as-directory directory) root)))
            (let* ((key (directory-file-name directory))
                   (old (gethash key table)))
              (when (> rank (alist-get old my/git-sidebar-folder-rank 0))
                (puthash key folder-face table)))
            (setq directory (file-name-directory (directory-file-name directory)))))))
    table))

(defun my/git-sidebar-face (file _directory-p)
  "Return the face of FILE's name in the sidebar, or nil."
  (when-let* ((table (and my/git-sidebar-root
                          (gethash my/git-sidebar-root my/git-sidebar-faces))))
    (gethash (directory-file-name (expand-file-name file)) table)))

(defun my/git-sidebar-same-p (a b)
  "Return non-nil if tables A and B map the same paths to the same faces."
  (and a b (= (hash-table-count a) (hash-table-count b))
       (catch 'differ
         (maphash (lambda (key value)
                    (unless (eq (gethash key b) value) (throw 'differ nil)))
                  a)
         t)))

(defun my/git-sidebar-redraw ()
  "Draw the current sidebar's rows again, keeping the selection."
  (mapc #'delete-overlay my/sidebar-hl)
  (setq my/sidebar-hl nil)
  (my/sidebar-rows-draw (point-min) (point-max))
  (my/sidebar-select))

(defun my/git-sidebar-on-status (root)
  "Recolor the sidebars listing ROOT when its changed files differ."
  (when-let* ((status (git-islands-status root)))
    (let ((table (my/git-sidebar-index status)))
      (unless (my/git-sidebar-same-p table (gethash root my/git-sidebar-faces))
        (puthash root table my/git-sidebar-faces)
        (dolist (buffer (buffer-list))
          (with-current-buffer buffer
            (when (and (bound-and-true-p my/sidebar-mode)
                       (equal my/git-sidebar-root root))
              (my/git-sidebar-redraw))))))))

(defun my/git-sidebar-setup ()
  "Follow the Git status of the repository a new sidebar lists."
  (when (and my/sidebar-mode (not my/git-sidebar-root)
             (not (file-remote-p default-directory)))
    (when-let* ((root (git-islands-root)))
      (setq my/git-sidebar-root root)
      (git-islands-watch root)
      (add-hook 'kill-buffer-hook (lambda () (git-islands-unwatch root)) nil t)
      ;; Rows were drawn before the repository was known; another view may
      ;; have read its status already.
      (if (gethash root my/git-sidebar-faces)
          (my/git-sidebar-redraw)
        (my/git-sidebar-on-status root)))))

(add-hook 'my/sidebar-mode-hook #'my/git-sidebar-setup)
(add-hook 'git-islands-status-functions #'my/git-sidebar-on-status)
(setq my/sidebar-name-face-function #'my/git-sidebar-face)

;; Sidebars made before this file loaded.
(dolist (buffer (buffer-list))
  (with-current-buffer buffer
    (when (bound-and-true-p my/sidebar-mode)
      (my/git-sidebar-setup))))

(provide 'git-sidebar)
;;; git-sidebar.el ends here
