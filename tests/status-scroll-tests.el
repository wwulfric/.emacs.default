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

(defmacro my-status-test--echo-area (heights &rest body)
  "Run BODY with a fake idle echo area.
HEIGHTS is (LINE WINDOW BODY): its line height, window height and body
height in pixels.  `resizes' counts resize calls; LIMIT, when bound
non-nil, is the tallest height a resize can reach."
  (declare (indent 1))
  `(let* ((line (nth 0 ,heights)) (height (nth 1 ,heights))
          (chrome (- height (nth 2 ,heights)))
          (resizes 0) (my/status--fit-attempt nil))
     (cl-letf (((symbol-function 'display-graphic-p) #'always)
               ((symbol-function 'active-minibuffer-window) #'ignore)
               ((symbol-function 'minibuffer-window) (lambda (&rest _) 'mini))
               ((symbol-function 'window-buffer) (lambda (&rest _) (get-buffer-create " *Minibuf-0*")))
               ((symbol-function 'window-default-line-height) (lambda (&rest _) line))
               ((symbol-function 'window-pixel-height) (lambda (&rest _) height))
               ((symbol-function 'window-body-height) (lambda (&rest _) (- height chrome)))
               ((symbol-function 'window--resize-mini-window)
                (lambda (_ delta)
                  (cl-incf resizes)
                  (setq height (if limit (min limit (+ height delta)) (+ height delta))))))
       ,@body)))

(ert-deftest my-status-echo-area-uses-native-line-height ()
  ;; Measuring styled text gave 29 where Emacs keeps 28: no resize then.
  (let ((limit nil))
    (my-status-test--echo-area '(28 28 28)
      (dotimes (_ 10) (my/status--fit-echo-area))
      (should (= resizes 0)))))

(ert-deftest my-status-echo-area-refits-once-after-frame-resize ()
  ;; A frame resize gives the echo area one bare line back.
  (let ((limit nil))
    (my-status-test--echo-area '(28 20 20)
      (dotimes (_ 10) (my/status--fit-echo-area))
      (should (= resizes 1))
      (should (= height 28)))))

(ert-deftest my-status-echo-area-unreachable-height-tried-once ()
  (let ((limit 24))
    (my-status-test--echo-area '(28 20 20)
      (dotimes (_ 10) (my/status--fit-echo-area))
      (should (= resizes 1))
      (should (= height 24)))))

(ert-deftest my-status-update-leaves-echo-area-height-alone ()
  ;; New bar text, as on each cursor move, must not resize the echo area.
  (let ((my/status--last nil) (limit nil) (n 0))
    (my-status-test--echo-area '(28 20 20)
      (cl-letf (((symbol-function 'my/status--compose)
                 (lambda (_) (format "bar %d" (cl-incf n))))
                ((symbol-function 'my/status--window) #'selected-window))
        (dotimes (_ 5) (my/status-update))
        (should (= n 5))
        (should (= resizes 0))))))

;;; status-scroll-tests.el ends here
