;;; source-project-tests.el --- Standalone provider project tests -*- lexical-binding: t; -*-
(require 'ert)
(require 'lsp-bridge-source)

(ert-deftest source-project-standalone-customize-and-cleanup ()
  (let ((origin (expand-file-name default-directory))
        (saved lsp-bridge-source-preserve-project))
    (unwind-protect
        (with-temp-buffer
          (setq default-directory temporary-file-directory
                lsp-bridge-source--reading t
                lsp-bridge-source--origin `((project . ,origin)))
          (lsp-bridge-source-mode 1)
          (should (equal (expand-file-name (project-root (project-current nil))) origin))
          (customize-set-variable 'lsp-bridge-source-preserve-project nil)
          (should-not lsp-bridge-source--project)
          (should-not (memq #'lsp-bridge-source--find-project project-find-functions))
          (customize-set-variable 'lsp-bridge-source-preserve-project t)
          (should (equal (expand-file-name (project-root (project-current nil))) origin))
          (let ((project-current-directory-override default-directory))
            (should-not (lsp-bridge-source--find-project default-directory)))
          (lsp-bridge-source-mode -1)
          (should-not lsp-bridge-source--project)
          (should-not (memq #'lsp-bridge-source--find-project project-find-functions)))
      (customize-set-variable 'lsp-bridge-source-preserve-project saved))))

(ert-deftest source-project-does-not-associate-unmanaged-buffer ()
  (with-temp-buffer
    (setq lsp-bridge-source--origin `((project . ,default-directory)))
    (lsp-bridge-source-mode 1)
    (should-not lsp-bridge-source--project)
    (should-not (memq #'lsp-bridge-source--find-project project-find-functions))))
