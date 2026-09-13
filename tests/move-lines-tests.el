;; -*- lexical-binding: t; -*-

(require 'ert)
(load (expand-file-name "../lisp/global-shortkeys.el"
                        (file-name-directory load-file-name)) nil t)

(ert-deftest my-move-lines-permutations ()
  "Check boundaries, counts, selection direction and final newlines."
  (dolist (trailing '(nil t))
    (dolist (selection '(nil forward backward))
      (dotimes (first 4)
        (dotimes (extra (if selection (- 4 first) 1))
          (dolist (count '(-8 -2 -1 0 1 2 8))
            (with-temp-buffer
              (let* ((lines '("alpha" "beta" "gamma" "delta"))
                     (size (1+ extra))
                     (destination (max 0 (min (- 4 size) (+ first count))))
                     (block (seq-subseq lines first (+ first size)))
                     (rest (append (seq-take lines first)
                                   (seq-drop lines (+ first size))))
                     (expected (append (seq-take rest destination) block
                                       (seq-drop rest destination)))
                     (transient-mark-mode t)
                     (kill-ring '("unchanged")))
                (insert (mapconcat #'identity lines "\n")
                        (if trailing "\n" ""))
                (goto-char (point-min))
                (forward-line first)
                (forward-char 1)
                (when selection
                  (set-mark (point))
                  (forward-line extra)
                  (end-of-line)
                  (setq mark-active t)
                  (when (eq selection 'backward) (exchange-point-and-mark)))
                (let ((selected-text (and selection
                                          (buffer-substring (region-beginning)
                                                            (region-end))))
                      (column (current-column)))
                  (my-move-lines count)
                  (should (equal (buffer-string)
                                 (concat (mapconcat #'identity expected "\n")
                                         (if trailing "\n" ""))))
                  (should (= (current-column) column))
                  (should (equal kill-ring '("unchanged")))
                  (when selection
                    (should mark-active)
                    (should (equal selected-text
                                   (buffer-substring (region-beginning)
                                                     (region-end))))))))))))))

(ert-deftest my-move-lines-selection-ending-at-line-start ()
  (with-temp-buffer
    (insert "a\nb\nc\nd\n")
    (let ((transient-mark-mode t))
      (goto-char 3)
      (set-mark 7)
      (setq mark-active t)
      (my-move-lines-down 1)
      (should (equal (buffer-string) "a\nd\nb\nc\n"))
      (should (equal (buffer-substring (region-beginning) (region-end))
                     "b\nc\n")))))

(ert-deftest my-move-lines-empty-and-blank-lines ()
  (dolist (text '("" "\n" "single" "single\n"))
    (with-temp-buffer
      (insert text)
      (goto-char (point-min))
      (my-move-lines-up 1)
      (my-move-lines-down 1)
      (should (equal (buffer-string) text))))
  (with-temp-buffer
    (insert "a\n\nb\n")
    (goto-char 3)
    (my-move-lines-down 1)
    (should (equal (buffer-string) "a\nb\n\n"))))

(ert-deftest my-move-lines-keybindings ()
  (should (eq (key-binding (kbd "s-S-<up>")) #'my-move-lines-up))
  (should (eq (key-binding (kbd "s-S-<down>")) #'my-move-lines-down)))
