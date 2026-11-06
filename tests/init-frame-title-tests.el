;;; init-frame-title-tests.el --- Title refresh regression tests -*- lexical-binding: t; -*-

;; Run: emacs -Q --batch -L lisp/ui -l tests/init-frame-title-tests.el -f ert-run-tests-batch-and-exit
(require 'ert)
(require 'cl-lib)
(require 'init-frame-title)

(defmacro my/title-test-with-cache (&rest body)
  "Run BODY with isolated title state and clean up any pending work."
  `(let ((my/frame-title-cache (make-hash-table :test #'equal))
         (my/frame-title-refresh-timer nil))
     (unwind-protect (progn ,@body)
       (when (timerp my/frame-title-refresh-timer)
         (cancel-timer my/frame-title-refresh-timer)))))

(ert-deftest my/title-redisplay-never-probes ()
  (my/title-test-with-cache
   (let ((default-directory "/tmp/title-project/")
         (fail (lambda (&rest _) (ert-fail "Redisplay performed I/O"))))
     (cl-letf (((symbol-function 'project-current) fail)
               ((symbol-function 'vc-git-root) fail)
               ((symbol-function 'process-file) fail)
               ((symbol-function 'make-process) fail))
       (should (equal (my/frame-title) "title-project"))
       ;; Even an expired entry is rendered immediately, without a refresh.
       (puthash default-directory '(0 . "cached project") my/frame-title-cache)
       (should (equal (my/frame-title) "cached project"))))))

(ert-deftest my/title-remote-never-connects ()
  (my/title-test-with-cache
   (let ((directory "/ssh:example.invalid:/srv/project/")
         probed)
     (cl-letf (((symbol-function 'project-current)
                (lambda (&rest _) (setq probed t)))
               ((symbol-function 'vc-git-root)
                (lambda (&rest _) (setq probed t)))
               ((symbol-function 'make-process)
                (lambda (&rest _) (setq probed t))))
       (my/frame-title-refresh-directory directory)
       (should-not probed)
       (should (equal (cdr (gethash directory my/frame-title-cache)) "project"))))))

(ert-deftest my/title-project-refresh-is-cached ()
  (my/title-test-with-cache
   (let ((calls 0) (now 100))
     (cl-letf (((symbol-function 'float-time) (lambda (&rest _) now))
               ((symbol-function 'project-current)
                (lambda (&rest _) (cl-incf calls) 'project))
               ((symbol-function 'project-name) (lambda (_) "Project")))
       (my/frame-title-refresh-directory "/tmp/src/")
       (should (equal (cdr (gethash "/tmp/src/" my/frame-title-cache)) "Project"))
       (my/frame-title-refresh-directory "/tmp/src/")
       (should (= calls 1))
       (setq now 104)
       (my/frame-title-refresh-directory "/tmp/src/")
       (should (= calls 2))))))

(ert-deftest my/title-project-error-keeps-directory-name ()
  (my/title-test-with-cache
   (cl-letf (((symbol-function 'project-current) (lambda (&rest _) (error "Unavailable"))))
     (my/frame-title-refresh-directory "/tmp/project/")
     (should (equal (cdr (gethash "/tmp/project/" my/frame-title-cache)) "project")))))

(ert-deftest my/title-source-origin-and-refresh-coalescing ()
  (my/title-test-with-cache
   (let ((default-directory "/tmp/dependency/"))
     (cl-letf (((symbol-function 'lsp-bridge-source-origin-directory)
                (lambda () "/tmp/original-project/")))
       (puthash "/tmp/original-project/" '(0 . "original") my/frame-title-cache)
       (should (equal (my/frame-title) "original"))
       (my/frame-title-source-refresh)
       (should-not (gethash "/tmp/original-project/" my/frame-title-cache))
       (let ((timer my/frame-title-refresh-timer))
         (should (timerp timer))
         (my/frame-title-schedule-refresh)
         (should (eq timer my/frame-title-refresh-timer)))))))

(ert-deftest my/title-reload-cleans-pending-work ()
  (my/title-test-with-cache
   (let ((post-command-hook nil)
         (window-buffer-change-functions nil)
         (after-make-frame-functions nil)
         (after-focus-change-function nil))
     (my/frame-title-schedule-refresh)
     (let ((old-timer my/frame-title-refresh-timer))
       (load "init-frame-title" nil t)
       (should-not (memq old-timer timer-idle-list))
       (should-not (eq old-timer my/frame-title-refresh-timer)))
     (load "init-frame-title" nil t)
     (should (= (cl-count #'my/frame-title-schedule-refresh post-command-hook) 1))
     (let ((count 0))
       (advice-function-mapc (lambda (function _props)
                      (when (eq function #'my/frame-title-schedule-refresh)
                        (cl-incf count)))
                    after-focus-change-function)
       (should (= count 1))))))

;;; init-frame-title-tests.el ends here
