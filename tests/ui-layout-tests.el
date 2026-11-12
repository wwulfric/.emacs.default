;;; ui-layout-tests.el --- Pixel-sized UI images -*- lexical-binding: t; -*-

(require 'ert)
(require 'ui-layout)

(ert-deftest my/ui-corners-keep-pixel-size-under-image-scaling ()
  "A corner measured from its row must never enlarge that row again."
  (skip-unless (display-images-p))
  (dolist (image-scaling-factor '(1.1 1.5 2.0))
    (let ((my/ui--corner-cache (make-hash-table :test #'equal)))
      (dolist (corner '(top-left top-right bottom-left bottom-right))
        (let* ((text (my/ui-corner corner 8 41 "white" "gray" nil 68))
               (image (get-text-property 0 'display text)))
          (should (equal (image-size image t) '(8 . 41))))))))
