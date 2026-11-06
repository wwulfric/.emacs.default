;;; editing-tests.el --- Editing command boundaries -*- lexical-binding: t; -*-
(require 'ert)
(require 'global-shortkeys)

(ert-deftest my/open-line-above-first-and-later-lines ()
  (dolist (position '(1 3 5))
    (with-temp-buffer
      (insert "one\ntwo")
      (goto-char position)
      (my-open-line-above)
      (should (equal (buffer-string)
                     (if (< position 5) "\none\ntwo" "one\n\ntwo")))
      (should (bolp))
      (should (eolp)))))

(ert-deftest my/delete-whole-line-at-buffer-boundaries ()
  (dolist (text '("" "last" "last\n" "first\nlast"))
    (with-temp-buffer
      (insert text)
      (goto-char (point-min))
      (let ((kill-ring '("keep")))
        (my-delete-whole-line)
        (should (equal (buffer-string) (if (equal text "first\nlast") "last" "")))
        (should (equal kill-ring '("keep")))))))

;;; editing-tests.el ends here
