;;; git-tests.el --- Tests of the Git sidebar colors -*- lexical-binding: t; -*-

;; Run: emacs -Q --batch -l tests/git-tests.el -f ert-run-tests-batch-and-exit
;; The Git tool windows themselves are the git-islands package, tested in
;; its own repository; these test what this configuration builds on it.
(require 'ert)
(require 'cl-lib)

(let ((default-directory (expand-file-name "../lisp/" (file-name-directory
                                                       (or load-file-name buffer-file-name)))))
  (add-to-list 'load-path default-directory)
  (normal-top-level-add-subdirs-to-load-path)
  (add-to-list 'load-path (expand-file-name "ui" default-directory)))

(require 'frame-setting)
(require 'git-islands-test-helpers)
(require 'git-sidebar)

;;;; Sidebar colors

(ert-deftest my/git-sidebar-index-ranks-folders ()
  (let* ((root "/repo/")
         (entry (lambda (path kind index worktree)
                  (git-islands-entry-create :path path :kind kind :index index :worktree worktree)))
         (status (git-islands-status-create
                  :root root
                  :entries (list (funcall entry "a/new.txt" 'untracked ?. ??)
                                 (funcall entry "a/b/x.el" 'changed ?. ?M)
                                 (funcall entry "c/only-new.txt" 'untracked ?. ??)
                                 (funcall entry "d/added.el" 'changed ?A ?.)
                                 (funcall entry "e/both.el" 'unmerged ?U ?U))))
         (table (my/git-sidebar-index status)))
    (should (eq (gethash "/repo/a/new.txt" table) 'git-islands-untracked))
    (should (eq (gethash "/repo/a/b/x.el" table) 'git-islands-modified))
    (should (eq (gethash "/repo/a" table) 'git-islands-modified))
    (should (eq (gethash "/repo/a/b" table) 'git-islands-modified))
    (should (eq (gethash "/repo/c" table) 'git-islands-untracked))
    (should (eq (gethash "/repo/d/added.el" table) 'git-islands-added))
    (should (eq (gethash "/repo/d" table) 'git-islands-modified))
    (should (eq (gethash "/repo/e" table) 'git-islands-conflict))
    (should-not (gethash "/repo" table))))

(ert-deftest my/git-sidebar-colors-rows ()
  (git-islands-test-with-repo
    (git-islands-test-write "README" "changed\n")
    (git-islands-test-write "fresh.txt" "new\n")
    (let ((sidebar (my/sidebar-buffer root)))
      (git-islands-test-fetch root)
      (with-current-buffer sidebar
        (should (equal my/git-sidebar-root root))
        (cl-flet ((face-of (name)
                    (goto-char (point-min))
                    (search-forward name)
                    (seq-some (lambda (overlay) (overlay-get overlay 'face))
                              (seq-filter (lambda (overlay) (overlay-get overlay 'my/sidebar-label))
                                          (overlays-at (match-beginning 0))))))
          (should (eq (face-of "README") 'git-islands-modified))
          (should (eq (face-of "fresh.txt") 'git-islands-untracked))
          (should-not (face-of "src")))))))

(ert-deftest my/git-sidebar-colors-when-status-came-first ()
  (git-islands-test-with-repo
    (git-islands-test-write "README" "changed\n")
    ;; Another view read the status before the sidebar existed.
    (git-islands-test-fetch root)
    (with-current-buffer (my/sidebar-buffer root)
      (goto-char (point-min))
      (search-forward "README")
      (should (eq (seq-some (lambda (overlay) (overlay-get overlay 'face))
                            (seq-filter (lambda (o) (overlay-get o 'my/sidebar-label))
                                        (overlays-at (match-beginning 0))))
                  'git-islands-modified)))))

;;; git-tests.el ends here
