;;; status-scroll-tests.el --- Status updates during scrolling -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(require 'init-status)

(ert-deftest my-status-scroll-burst-refreshes-once-after-pause ()
  (let ((my/status-mode t) (my/status--scroll-timer nil) (updates 0)
        (this-command 'pixel-scroll-precision))
    (cl-letf (((symbol-function 'my/status-update) (lambda (&rest _) (cl-incf updates))))
      (unwind-protect
          (progn
            (my/status--after-command)
            (let ((timer my/status--scroll-timer))
              (dotimes (_ 200) (my/status--after-command))
              (should (eq timer my/status--scroll-timer))
              (should (= updates 0))
              (cancel-timer timer)
              (my/status--after-scroll)
              (should-not my/status--scroll-timer)
              (should (= updates 1))))
        (my/status--cancel-scroll-update)))))

(ert-deftest my-status-edit-after-scroll-refreshes-immediately ()
  (let ((my/status-mode t) (my/status--scroll-timer nil) (updates 0))
    (cl-letf (((symbol-function 'my/status-update) (lambda (&rest _) (cl-incf updates))))
      (unwind-protect
          (progn
            (let ((this-command 'pixel-scroll-precision)) (my/status--after-command))
            (let ((timer my/status--scroll-timer)
                  (this-command 'self-insert-command))
              (my/status--after-command)
              (should (= updates 1))
              (should-not my/status--scroll-timer)
              (should-not (memq timer timer-idle-list))))
        (my/status--cancel-scroll-update)))))

(ert-deftest my-status-disabled-does-not-redraw-after-scroll ()
  (let ((my/status-mode nil) (my/status--scroll-timer nil))
    (cl-letf (((symbol-function 'my/status-update) (lambda (&rest _) (ert-fail "Disabled bar redrawn"))))
      (my/status--after-scroll))))

;;; status-scroll-tests.el ends here
