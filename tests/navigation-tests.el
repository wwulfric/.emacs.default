;;; navigation-tests.el --- Position history regressions -*- lexical-binding: t; -*-
(require 'ert)
(require 'init-navigation)
(require 'isearch)

(defmacro nav-test (&rest body)
  `(let ((xref--history (cons nil nil))
         (my/navigation-start nil)
         (my/navigation-generation 0)
         (a (generate-new-buffer "nav-a"))
         (b (generate-new-buffer "nav-b")))
     (unwind-protect
         (save-window-excursion
           (dolist (buf (list a b))
             (with-current-buffer buf
               (setq buffer-file-name (concat "/tmp/" (buffer-name)))
               (dotimes (_ 30) (insert "abcdefghij\n"))
               (goto-char 1)))
           (switch-to-buffer a)
           ,@body)
       (dolist (buf (list a b))
         (with-current-buffer buf (set-buffer-modified-p nil))
         (kill-buffer buf)))))

(ert-deftest navigation-round-trip ()
  (nav-test
   (my/navigation-around (lambda () (switch-to-buffer b) (goto-char 40)))
   (xref-go-back)
   (should (eq (current-buffer) a))
   (should (= (point) 1))
   (xref-go-forward)
   (should (eq (current-buffer) b))
   (should (= (point) 40))))

(ert-deftest navigation-nesting-and-noop ()
  (nav-test
   (my/navigation-around (lambda () nil))
   (should (xref-marker-stack-empty-p))
   (my/navigation-around
    (lambda () (my/navigation-around (lambda () (goto-char 80)))))
   (should (= (length (car xref--history)) 1))))

(ert-deftest navigation-new-branch ()
  (nav-test
   (my/navigation-around (lambda () (goto-char 50)))
   (my/navigation-around (lambda () (goto-char 100)))
   (xref-go-back)
   (my/navigation-around (lambda () (goto-char 150)))
   (should (xref-forward-history-empty-p))
   (xref-go-back)
   (should (= (point) 50))))

(ert-deftest navigation-command-threshold ()
  (nav-test
   (let ((this-command 'next-line))
     (my/navigation-pre-command) (forward-line 1)
     (my/navigation-post-command)
     (should (xref-marker-stack-empty-p)))
   (let ((this-command 'scroll-up-command))
     (my/navigation-pre-command) (forward-line 12)
     (my/navigation-post-command)
     (should (= (length (car xref--history)) 1)))))

(ert-deftest navigation-no-double-recording ()
  (nav-test
   (let ((this-command 'imenu))
     (my/navigation-pre-command)
     (my/navigation-around (lambda () (goto-char 150)))
     (my/navigation-post-command)
     (should (= (length (car xref--history)) 1)))))

(ert-deftest navigation-search-and-readonly ()
  (nav-test
   (setq buffer-read-only t)
   (let ((isearch-opoint 1))
     (goto-char 3)
     (my/navigation-isearch-end))
   (xref-go-back)
   (should (= (point) 1))
   (xref-go-forward)
   (should (= (point) 3))))

(ert-deftest navigation-interactive-buffer-switch ()
  (nav-test
   (execute-kbd-macro (vconcat (kbd "C-x b") (buffer-name b) (kbd "RET")))
   (should (eq (current-buffer) b))
   (execute-kbd-macro (kbd "C-c n b"))
   (should (eq (current-buffer) a))
   (execute-kbd-macro (kbd "C-c n f"))
   (should (eq (current-buffer) b))))

(ert-deftest navigation-interactive-search ()
  (nav-test
   (execute-kbd-macro (kbd "C-s a b c C-s RET"))
   (let ((target (point)))
     (should (= (length (car xref--history)) 1))
     (execute-kbd-macro (kbd "C-c n b"))
     (should (= (point) 1))
     (execute-kbd-macro (kbd "C-c n f"))
     (should (= (point) target)))))

(ert-deftest navigation-native-xref-not-duplicated ()
  (nav-test
   (let ((this-command 'xref-find-definitions))
     (my/navigation-pre-command)
     (xref-push-marker-stack)
     (switch-to-buffer b)
     (my/navigation-post-command)
     (should (= (length (car xref--history)) 1)))))

(ert-deftest navigation-edits-are-not-jumps ()
  (nav-test
   (let ((this-command 'yank))
     (my/navigation-pre-command)
     (insert (make-string 20 ?\n))
     (my/navigation-post-command)
     (should (xref-marker-stack-empty-p)))))

(ert-deftest navigation-lsp-definition-callback ()
  (skip-unless (featurep 'lsp-bridge))
  (nav-test
   ;; Exercise the real result handler without starting a language server.
   (lsp-bridge-define--jump (buffer-file-name b) "" '(:line 2 :character 3))
   (should (eq (current-buffer) b))
   (should (= (point) 26))
   (should (= (length (car xref--history)) 1))
   (xref-go-back)
   (should (eq (current-buffer) a))
   (xref-go-forward)
   (should (eq (current-buffer) b))
   (should (= (point) 26))))

(ert-deftest navigation-lsp-key-bindings ()
  (skip-unless (featurep 'lsp-bridge))
  (dolist (map (list global-map lsp-bridge-mode-map lsp-bridge-source-mode-map))
    (should (eq (lookup-key map (kbd "s-[")) #'xref-go-back))
    (should (eq (lookup-key map (kbd "s-]")) #'xref-go-forward))))

(ert-deftest navigation-via-non-file-sidebar ()
  (nav-test
   (let ((sidebar (generate-new-buffer "nav-sidebar"))
         (this-command 'sidebar-toggle))
     (unwind-protect
         (progn
           (my/navigation-pre-command)
           (switch-to-buffer sidebar)
           (my/navigation-post-command)
           (should (xref-marker-stack-empty-p))
           (my/navigation-pre-command)
           (switch-to-buffer b)
           (my/navigation-post-command)
           (xref-go-back)
           (should (eq (current-buffer) a)))
       (kill-buffer sidebar)))))
