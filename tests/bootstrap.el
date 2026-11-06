;;; bootstrap.el --- Isolated configuration test environment -*- lexical-binding: t; -*-

;; Loaded in a fresh Emacs for each suite by run.sh.
(setq load-prefer-newer t)
(setq user-emacs-directory (file-name-as-directory (getenv "EMACS_TEST_HOME")))
(let ((default-directory
       (expand-file-name "../lisp/" (file-name-directory load-file-name))))
  (add-to-list 'load-path default-directory)
  (normal-top-level-add-subdirs-to-load-path)
  (add-to-list 'load-path (expand-file-name "ui" default-directory)))

;;; bootstrap.el ends here
