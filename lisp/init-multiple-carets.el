;;; init-multiple-carets.el --- IntelliJ's multiple carets -*- lexical-binding: t; -*-

;;; Commentary:
;; Several carets edit at once, with the keys and mouse gestures of
;; IntelliJ, drawn by the multiple-cursors package (lisp/multiple-cursors):
;;
;;   s-d            Select the word at the caret; again, add the next
;;                  occurrence with a caret of its own (Ctrl-G in IntelliJ,
;;                  Cmd-D in VS Code).  Past the last, it wraps to the top.
;;   s-D            Drop the occurrence added last (Ctrl-Shift-G).
;;   C-s-g          Select every occurrence (Ctrl-Cmd-G).
;;   M-S-<up/down>  Add a caret on the line above or below (IntelliJ: press
;;                  Option twice and hold it with the arrows, which Emacs
;;                  cannot see).
;;   M-G            A caret at the end of each line of the selection
;;                  (Option-Shift-G).
;;   M-S-click      Add a caret, or remove the one clicked (Option-Shift-click).
;;   M-S-drag       A caret and selection on each line of the column dragged
;;                  over (Option-Shift-drag).
;;   <escape>       Back to one caret; C-g first drops the selections.
;;
;; Every command runs at each caret, but for those listed in
;; `my/carets-run-once', which act on the editor rather than the text.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'multiple-cursors)

(defvar my/var-directory)
(defvar lsp-bridge-completion-popup-predicates)
(declare-function my/var-file "init-session" (name))

;; Commands run at every caret without asking; those that should not are
;; listed below, and the list file keeps any added later.
(setq mc/always-run-for-all t
      mc/list-file (my/var-file "mc-lists.el"))

(defconst my/carets-run-once
  '(my/parameter-info my/parameter-info-hide my/intentions
    my/find-usages my/find-toggle my/problems-toggle my/recent-locations
    my/sidebar-toggle my/keys-reference
    palette-islands-search palette-islands-search-commands
    palette-islands-search-files palette-islands-search-text
    palette-islands-search-line palette-islands-search-structure
    palette-islands-search-symbols
    lsp-bridge-find-def lsp-bridge-find-references lsp-bridge-popup-documentation
    save-buffer save-some-buffers
    my/carets-select-next my/carets-unselect-last my/carets-select-all
    my/carets-add-above my/carets-add-below my/carets-line-ends
    my/carets-click my/carets-column-drag my/carets-escape)
  "Commands that act once, not at each caret.")

(dolist (command my/carets-run-once)
  (add-to-list 'mc/cmds-to-run-once command))

;; Extend Selection keeps its steps per caret.
(add-to-list 'mc/cursor-specific-vars 'my/extend--history)

;; Enter types a line break at each caret, as in IntelliJ; Escape ends.
(keymap-unset mc/keymap "<return>")
(defun my/carets-escape ()
  "Go back to one caret, dropping the selections too, as Escape in IntelliJ.
C-g first drops the selections, then the carets."
  (interactive)
  (deactivate-mark)
  (mc/disable-multiple-cursors-mode))

(keymap-set mc/keymap "<escape>" #'my/carets-escape)

;; No completion popup while several carets type: it would complete at
;; the main caret only.
(with-eval-after-load 'lsp-bridge
  (add-to-list 'lsp-bridge-completion-popup-predicates
               (lambda () (not (bound-and-true-p multiple-cursors-mode)))))

;;;; Look

;; The other carets look like the main one: a bar of its width and color,
;; drawn as a narrow space so the text moves as little as it can.
(defun my/carets--bar ()
  "Return the string that draws a caret bar."
  (propertize " " 'display `(space :width (,(if (consp cursor-type) (cdr cursor-type) 2)))
              'face 'mc/cursor-bar-face))

(defun my/carets--draw-bar (overlay)
  "Draw OVERLAY's caret as a bar of the main caret's width."
  (when (overlay-get overlay 'before-string)
    (overlay-put overlay 'before-string (my/carets--bar)))
  overlay)

(advice-add 'mc/make-cursor-overlay-inline :filter-return #'my/carets--draw-bar)
(advice-add 'mc/make-cursor-overlay-at-eol :filter-return #'my/carets--draw-bar)

(defun my/carets--face (&rest _)
  "Give the other carets the main caret's color."
  (face-spec-set 'mc/cursor-bar-face
                 `((t :background ,(face-background 'cursor nil t)))
                 'face-defface-spec))

(my/carets--face)
(add-hook 'enable-theme-functions #'my/carets--face)

;;;; Occurrences

(defvar-local my/carets--whole nil
  "The symbol s-d selected at the caret, as (START . END), or nil.
Occurrences of it match whole symbols only, as in IntelliJ.")

(defun my/carets--whole-p ()
  "Return non-nil when occurrences should match whole symbols."
  (and my/carets--whole
       (or (bound-and-true-p multiple-cursors-mode)
           (equal my/carets--whole (cons (region-beginning) (region-end))))))

(defun my/carets--select-symbol ()
  "Select the symbol at point, or signal that there is none."
  (let ((bounds (or (bounds-of-thing-at-point 'symbol)
                    (user-error "No word at the caret"))))
    (goto-char (cdr bounds))
    (push-mark (car bounds) t t)
    (setq my/carets--whole bounds)))

(defun my/carets--cursor-at-p (start end)
  "Return non-nil when a caret already selects START to END."
  (or (and (= (region-beginning) start) (= (region-end) end))
      (seq-some (lambda (cursor)
                  (let ((point (marker-position (overlay-get cursor 'point)))
                        (mark (marker-position (overlay-get cursor 'mark))))
                    (and (= (min point mark) start) (= (max point mark) end))))
                (mc/all-fake-cursors))))

(defun my/carets--wrap ()
  "Add the first occurrence above the main caret that has no caret yet.
Return non-nil when one was added."
  (let ((case-fold-search nil)
        (re (regexp-opt (mc/region-strings) mc/enclose-search-term))
        ;; Above the main caret, which the forward search started after.
        (limit (min (point) (mark)))
        found)
    (save-excursion
      (goto-char (point-min))
      (while (and (not found) (re-search-forward re limit t))
        (unless (my/carets--cursor-at-p (match-beginning 0) (match-end 0))
          (setq found (cons (match-beginning 0) (match-end 0))))))
    (when found
      ;; The caret at the same end of its occurrence as the main one.
      (let ((forward (< (mark) (point))))
        (mc/save-excursion
         (goto-char (if forward (cdr found) (car found)))
         (push-mark (if forward (car found) (cdr found)) t t)
         (mc/create-fake-cursor-at-point)))
      t)))

(defun my/carets-select-next ()
  "Select the word at the caret, then add its next occurrence.
Each occurrence gets a caret of its own, as Ctrl-G does in IntelliJ."
  (interactive)
  (if (not (region-active-p))
      (my/carets--select-symbol)
    (let ((mc/enclose-search-term (and (my/carets--whole-p) 'symbols)))
      (condition-case nil
          (mc/mark-more-like-this nil 'forwards)
        (user-error
         (unless (my/carets--wrap)
           (message "Every occurrence is selected")))))
    (mc/maybe-multiple-cursors-mode)))

(defun my/carets-unselect-last ()
  "Drop the occurrence added last, as Ctrl-Shift-G does in IntelliJ."
  (interactive)
  (if (mc/furthest-cursor-after-point)
      (mc/unmark-next-like-this)
    (when-let* ((cursor (car (last (mc/all-fake-cursors)))))
      (mc/remove-fake-cursor cursor))
    (mc/maybe-multiple-cursors-mode)))

(defun my/carets-select-all ()
  "Select every occurrence of the selection or of the word at the caret."
  (interactive)
  (unless (region-active-p)
    (my/carets--select-symbol))
  (let ((mc/enclose-search-term (and (my/carets--whole-p) 'symbols)))
    (mc/mark-all-like-this)))

(defun my/carets--reset-whole ()
  "Forget that occurrences match whole symbols once one caret is left."
  (unless multiple-cursors-mode
    (setq my/carets--whole nil)))

(add-hook 'multiple-cursors-mode-hook #'my/carets--reset-whole)

;;;; Lines

(defun my/carets-add-above ()
  "Add a caret on the line above."
  (interactive)
  (deactivate-mark)
  (mc/mark-previous-lines 1))

(defun my/carets-add-below ()
  "Add a caret on the line below."
  (interactive)
  (deactivate-mark)
  (mc/mark-next-lines 1))

(defun my/carets-line-ends ()
  "Put a caret at the end of each line of the selection."
  (interactive)
  (unless (region-active-p)
    (user-error "Select the lines first"))
  (mc/edit-ends-of-lines))

;;;; Mouse

(defun my/carets-click (event)
  "Add a caret where EVENT clicked, or remove the one there."
  (interactive "e")
  (mc/toggle-cursor-on-click event))

(defun my/carets--column (posn)
  "Return the column POSN points at, past the end of its line too."
  (save-excursion
    (goto-char (posn-point posn))
    (let ((column (current-column)))
      (if (not (eolp))
          column
        (let ((past (- (car (posn-x-y posn))
                       (car (posn-x-y (posn-at-point (point)))))))
          (+ column (max 0 (round past (frame-char-width)))))))))

(defun my/carets-column-drag (event)
  "Put a caret and selection on each line of the column EVENT dragged over.
Lines too short for the column get a caret at their end."
  (interactive "e")
  (let* ((start (event-start event))
         (end (event-end event))
         (window (posn-window start)))
    (unless (and (windowp window) (eq window (posn-window end))
                 (posn-point start) (posn-point end))
      (user-error "Drag inside one window"))
    (select-window window)
    (let* ((from (my/carets--column start))
           (to (my/carets--column end))
           (first (line-number-at-pos (posn-point start)))
           (last (line-number-at-pos (posn-point end)))
           (step (if (<= first last) 1 -1)))
      (mc/remove-fake-cursors)
      (deactivate-mark)
      (goto-char (posn-point start))
      (cl-loop
       for line = first then (+ line step)
       do (progn
            (forward-line (- line (line-number-at-pos)))
            (move-to-column from)
            (let ((mark (point)))
              (move-to-column to)
              (if (= mark (point))
                  (deactivate-mark)
                (push-mark mark t t)))
            (unless (= line last)
              (mc/create-fake-cursor-at-point)))
       until (= line last))
      (mc/maybe-multiple-cursors-mode))))

(keymap-global-set "s-d" #'my/carets-select-next)
(keymap-global-set "s-D" #'my/carets-unselect-last)
(keymap-global-set "C-s-g" #'my/carets-select-all)
(keymap-global-set "M-S-<up>" #'my/carets-add-above)
(keymap-global-set "M-S-<down>" #'my/carets-add-below)
(keymap-global-set "M-G" #'my/carets-line-ends)
(keymap-global-set "M-S-<down-mouse-1>" #'ignore)
(keymap-global-set "M-S-<mouse-1>" #'my/carets-click)
(keymap-global-set "M-S-<drag-mouse-1>" #'my/carets-column-drag)

(provide 'init-multiple-carets)
;;; init-multiple-carets.el ends here
