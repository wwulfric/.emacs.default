;;; init-extend-selection.el --- IntelliJ's Extend and Shrink Selection -*- lexical-binding: t; -*-

;;; Commentary:
;; M-<up> selects the smallest piece of code around the selection, or
;; around point: a word, then the expression, the inside of its string
;; or brackets, the brackets with them, the line, the statement, the
;; block's contents and the block, up to the function and the file.
;; M-<down> goes back a step, as Option-Up and Option-Down do in IntelliJ.
;;
;; The pieces come from the tree-sitter syntax tree where the buffer has
;; one, and from the syntax table everywhere, so every mode gets strings,
;; brackets and comments.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'thingatpt)
(require 'treesit nil t)

(defvar-local my/extend--history nil
  "Regions the selection was extended from, the latest first.
Each is (START . END), an empty one where point was without a selection;
it lasts while M-<up> and M-<down> follow each other.")

(defconst my/extend-open-delimiters '("(" "[" "{" "<" "\"" "'" "`" "\"\"\"" "'''")
  "Tokens that open a node whose inside is a step of its own.")

(defun my/extend--trim (start end)
  "Return (START . END) without the blanks at both ends, or nil if empty."
  (save-excursion
    (goto-char start)
    (skip-chars-forward " \t\n" end)
    (let ((start (point)))
      (goto-char end)
      (skip-chars-backward " \t\n" start)
      (when (< start (point))
        (cons start (point))))))

(defun my/extend--treesit-ranges (start end)
  "Return the ranges of the syntax nodes around START to END, and their insides."
  (when (and (fboundp 'treesit-parser-list) (treesit-parser-list))
    (let ((node (ignore-errors (treesit-node-on start end)))
          ranges)
      (while node
        (push (cons (treesit-node-start node) (treesit-node-end node)) ranges)
        ;; The inside of brackets and quotes, as (a, b) gives a, b.
        (let ((count (treesit-node-child-count node)))
          (when (>= count 2)
            (let ((first (treesit-node-child node 0))
                  (last (treesit-node-child node (1- count))))
              (when (and (member (treesit-node-type first) my/extend-open-delimiters)
                         (not (treesit-node-check last 'named)))
                (when-let* ((inside (my/extend--trim (treesit-node-end first)
                                                     (treesit-node-start last))))
                  (push inside ranges))))))
        (setq node (treesit-node-parent node)))
      ranges)))

(defun my/extend--syntax-ranges (start)
  "Return the strings, comments and brackets around START, and their insides."
  (let ((ranges nil)
        (state (syntax-ppss start)))
    (save-excursion
      ;; The string or comment START is in.
      (when-let* ((open (nth 8 state)))
        (goto-char open)
        (when (ignore-errors (forward-sexp) t)
          (push (cons open (point)) ranges)
          (when (nth 3 state)
            (when-let* ((inside (my/extend--trim (1+ open) (1- (point)))))
              (push inside ranges)))))
      ;; Every bracket START is in, from the innermost out.
      (dolist (open (nth 9 state))
        (goto-char open)
        (when (ignore-errors (forward-sexp) t)
          (push (cons open (point)) ranges)
          (when-let* ((inside (my/extend--trim (1+ open) (1- (point)))))
            (push inside ranges)))))
    ranges))

(defun my/extend--line-range (start end)
  "Return the text of the lines from START to END, without indentation."
  (save-excursion
    (my/extend--trim (progn (goto-char start) (pos-bol))
                     (progn (goto-char end) (pos-eol)))))

(defun my/extend--defun-range (start)
  "Return the function START is in, or nil."
  (save-excursion
    (goto-char start)
    (ignore-errors
      (let ((end (progn (end-of-defun) (point)))
            (begin (progn (beginning-of-defun) (point))))
        (when (and (<= begin start) (< start end))
          (my/extend--trim begin end))))))

(defun my/extend--ranges (start end)
  "Return every piece of code around START to END, smallest first."
  (let* ((word (unless (/= start end)
                 (save-excursion
                   (goto-char start)
                   (or (bounds-of-thing-at-point 'symbol)
                       (bounds-of-thing-at-point 'word)))))
         (ranges (append (and word (list word))
                         (my/extend--treesit-ranges start end)
                         (my/extend--syntax-ranges start)
                         (delq nil (list (my/extend--line-range start end)
                                         (my/extend--defun-range start)))
                         (list (cons (point-min) (point-max))))))
    (sort (seq-uniq (seq-filter (lambda (range) (< (car range) (cdr range))) ranges))
          (lambda (a b) (< (- (cdr a) (car a)) (- (cdr b) (car b)))))))

(defun my/extend--next (start end)
  "Return the smallest range holding START to END and larger than it."
  (seq-find (lambda (range)
              (and (<= (car range) start) (>= (cdr range) end)
                   (or (< (car range) start) (> (cdr range) end))))
            (my/extend--ranges start end)))

(defun my/extend--select (range)
  "Select RANGE, point at its start."
  (goto-char (car range))
  (push-mark (cdr range) t t)
  (setq deactivate-mark nil))

(defun my/extend-selection ()
  "Select the piece of code around the selection, or around point."
  (interactive)
  (let* ((active (use-region-p))
         (start (if active (region-beginning) (point)))
         (end (if active (region-end) (point))))
    (unless (memq last-command '(my/extend-selection my/shrink-selection))
      (setq my/extend--history nil))
    (if-let* ((range (if (= start end)
                         (seq-find (lambda (range) (<= (car range) start (cdr range)))
                                   (my/extend--ranges start end))
                       (my/extend--next start end))))
        (progn
          (push (if active (cons start end) (cons (point) (point))) my/extend--history)
          (my/extend--select range))
      (message "The whole buffer is selected"))))

(defun my/shrink-selection ()
  "Go back to the selection before the last Extend Selection."
  (interactive)
  (if (and (memq last-command '(my/extend-selection my/shrink-selection))
           my/extend--history)
      (let ((range (pop my/extend--history)))
        (if (< (car range) (cdr range))
            (my/extend--select range)
          ;; Back to no selection, with point where it was.
          (deactivate-mark)
          (goto-char (car range))))
    (setq my/extend--history nil)))

(keymap-global-set "M-<up>" #'my/extend-selection)
(keymap-global-set "M-<down>" #'my/shrink-selection)

(provide 'init-extend-selection)
;;; init-extend-selection.el ends here
