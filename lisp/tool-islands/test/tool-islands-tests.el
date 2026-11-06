;;; tool-islands-tests.el --- Tests for tool-islands -*- lexical-binding: t; -*-

(require 'ert)
(require 'magit-section)
(require 'tool-islands)

(ert-deftest tool-islands-tree-compacts-single-folders ()
  (let* ((items '("a/b/c/x.el" "a/b/c/y.el" "a/d.el" "e.el"))
         (tree (tool-islands-tree-build items #'identity)))
    ;; "a" holds a file, so it stays; "b" holds only "c", so they merge.
    (should (equal (mapcar #'car (nth 1 tree)) '("a")))
    (should (equal (mapcar #'car (nth 1 (car (nth 1 tree)))) '("b/c")))
    (should (equal (nth 2 tree) '("e.el")))
    (should (= (length (tool-islands-tree-items tree)) 4))))

(ert-deftest tool-islands-row-marks-depth ()
  (with-temp-buffer
    (tool-islands-row 2 "name")
    (should (equal (buffer-string) "name\n"))
    (should (= (get-text-property 1 'tool-islands-depth) 2))
    (should (get-text-property 1 'line-prefix))
    (should (seq-some (lambda (o) (overlay-get o 'tool-islands-chevron))
                      (overlays-at 1)))))

(ert-deftest tool-islands-row-width-counts-indent ()
  (with-temp-buffer
    (tool-islands-row 1 "x")
    (should (= (tool-islands-row-width 1 2)
               (+ tool-islands-row-inset tool-islands-indent tool-islands-state-width
                  (string-pixel-width "x" (current-buffer)))))))

(ert-deftest tool-islands-pill-cap-square-is-space ()
  (let ((cap (tool-islands-pill-cap 'left 0 20 "#ffffff" 4)))
    (should (equal (get-text-property 0 'display cap) '(space :width (4) :height (20))))))

(ert-deftest tool-islands-fit-marks-span ()
  (should (get-text-property 0 'tool-islands-fit (tool-islands-fit "abc"))))

(ert-deftest tool-islands-view-in-section-buffer ()
  (with-temp-buffer
    (magit-section-mode)
    (tool-islands-view-setup)
    (let ((inhibit-read-only t))
      (magit-insert-section (root)
        (magit-insert-section (item 'a)
          (tool-islands-row 0 (tool-islands-fit "Item"))
          (magit-insert-heading))))
    (tool-islands-draw-chevrons)
    (should tool-islands-view)
    (goto-char (point-min))
    (tool-islands-highlight)
    (should (= (length tool-islands-hl) 1))))

;;; tool-islands-tests.el ends here
