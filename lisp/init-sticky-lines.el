;;; init-sticky-lines.el --- IntelliJ's Sticky Lines -*- lexical-binding: t; -*-

;;; Commentary:
;; As the code scrolls, the first lines of the class, function and block
;; the top of the window is in stay pinned there, as IntelliJ's Sticky
;; Lines do: up to `my/sticky-lines-max' of them, outermost first, each
;; with its line number, and a thin line under them.  Clicking one goes to
;; it.  The scopes come from the tree-sitter syntax tree where the buffer
;; has one, and from enclosing brackets otherwise.
;;
;; The lines are drawn in a child frame laid over the top of the window,
;; with a one-pixel child frame under it for the line.  Nothing in the
;; buffer or the window's layout changes, so scrolling by pixels is left
;; alone (AGENTS.md).

;;; Code:

(require 'seq)
(require 'subr-x)
(require 'treesit nil t)

(defgroup my/sticky-lines nil
  "IntelliJ's Sticky Lines."
  :group 'convenience)

(defcustom my/sticky-lines-max 5
  "Most lines pinned at the top of a window."
  :type 'natnum)

(defcustom my/sticky-lines-node-regexp
  (rx bos
      (or (seq (or "class" "function" "method" "struct" "impl" "interface"
                   "enum" "trait" "module" "namespace" "object" "constructor"
                   "if" "for" "while" "with" "try" "switch" "match" "do"
                   "foreach" "loop" "unless" "until" "case")
               "_" (or "definition" "declaration" "statement" "item"
                       "expression" "specifier"))
          (seq (or "else" "elif" "except" "finally" "catch" "case") "_clause")
          "function_item" "arrow_function" "lambda_expression")
      eos)
  "Syntax node types whose first line is pinned."
  :type 'regexp)

(defface my/sticky-lines-border
  '((t :background "#EBECF0"))
  "The thin line under the pinned lines.")

(defface my/sticky-lines-hover
  '((t :inherit highlight))
  "A pinned line under the mouse.")

;;;; Scopes

(defun my/sticky-lines--scopes (position)
  "Return where the scopes around POSITION start, on lines above it.
Each is the start of the scope's first line, outermost first."
  (save-excursion
    (goto-char position)
    (let ((line (pos-bol))
          starts)
      (if (and (fboundp 'treesit-parser-list) (treesit-parser-list))
          (let ((node (ignore-errors
                        (treesit-node-at (progn (back-to-indentation) (point))))))
            (while node
              (when (and (string-match-p my/sticky-lines-node-regexp (treesit-node-type node))
                         (< (treesit-node-start node) line))
                (push (save-excursion (goto-char (treesit-node-start node)) (pos-bol))
                      starts))
              (setq node (treesit-node-parent node))))
        (dolist (open (reverse (nth 9 (syntax-ppss line))))
          (let ((start (save-excursion (goto-char open) (pos-bol))))
            (when (< start line)
              (push start starts)))))
      (seq-uniq starts))))

(defun my/sticky-lines--lines (window)
  "Return the starts of the lines to pin at the top of WINDOW."
  (with-current-buffer (window-buffer window)
    (let* ((top (window-start window))
           ;; The pinned lines cover as many lines at the top; what counts
           ;; is the scope of the first line below them.
           (count (min my/sticky-lines-max (length (my/sticky-lines--scopes top))))
           (below (save-excursion (goto-char top) (forward-line count) (point))))
      (seq-take (my/sticky-lines--scopes below) my/sticky-lines-max))))

;;;; Drawing

(defvar my/sticky-lines-map)

(defvar-local my/sticky-lines--source nil
  "In a pinned lines buffer, the window whose lines it shows.")

(defun my/sticky-lines--frame-parameters (parent)
  "Return the parameters of a child frame of PARENT."
  `((parent-frame . ,parent)
    (minibuffer . nil)
    (no-accept-focus . t)
    (no-focus-on-map . t)
    (min-width . t)
    (min-height . t)
    (border-width . 0)
    (internal-border-width . 0)
    (child-frame-border-width . 0)
    (left-fringe . 0)
    (right-fringe . 0)
    (vertical-scroll-bars . nil)
    (horizontal-scroll-bars . nil)
    (menu-bar-lines . 0)
    (tool-bar-lines . 0)
    (tab-bar-lines . 0)
    (no-other-frame . t)
    (unsplittable . t)
    (undecorated . t)
    (visibility . nil)
    (no-special-glyphs . t)
    (cursor-type . nil)
    (desktop-dont-save . t)))

(defun my/sticky-lines--make-frame (window name)
  "Return a hidden child frame over WINDOW's frame, showing buffer NAME."
  (let* ((after-make-frame-functions nil)
         (parent (window-frame window))
         (frame (make-frame (my/sticky-lines--frame-parameters parent)))
         (buffer (get-buffer-create name)))
    (with-selected-frame frame
      (set-frame-font (face-attribute 'default :font parent) nil (list frame)))
    (with-current-buffer buffer
      (setq-local my/sticky-lines--source window
                  mode-line-format nil
                  header-line-format nil
                  tab-line-format nil
                  cursor-type nil
                  cursor-in-non-selected-windows nil
                  truncate-lines t
                  buffer-read-only t
                  display-line-numbers nil)
      (use-local-map my/sticky-lines-map))
    (let ((frame-window (frame-root-window frame)))
      (set-window-buffer frame-window buffer)
      (set-window-dedicated-p frame-window t)
      (set-window-parameter frame-window 'no-other-window t))
    frame))

(defun my/sticky-lines--frames (window)
  "Return WINDOW's two child frames, (TEXT . LINE), making them if needed."
  (let ((frames (window-parameter window 'my/sticky-lines)))
    (unless (and frames (frame-live-p (car frames)) (frame-live-p (cdr frames))
                 (eq (frame-parent (car frames)) (window-frame window)))
      (my/sticky-lines--delete window)
      (let ((id (format "%x" (sxhash-eq window))))
        (setq frames (cons (my/sticky-lines--make-frame window (format " *sticky-lines-%s*" id))
                           (my/sticky-lines--make-frame window (format " *sticky-line-%s*" id)))))
      (set-window-parameter window 'my/sticky-lines frames))
    frames))

(defun my/sticky-lines--delete (window)
  "Delete WINDOW's child frames."
  (when-let* ((frames (window-parameter window 'my/sticky-lines)))
    (dolist (frame (list (car frames) (cdr frames)))
      (when (frame-live-p frame)
        (let ((buffer (window-buffer (frame-root-window frame))))
          (delete-frame frame)
          (kill-buffer buffer))))
    (set-window-parameter window 'my/sticky-lines nil)
    (set-window-parameter window 'my/sticky-lines-shown nil)))

(defun my/sticky-lines--hide (window)
  "Hide WINDOW's pinned lines."
  (when-let* ((frames (window-parameter window 'my/sticky-lines)))
    (dolist (frame (list (car frames) (cdr frames)))
      (when (and (frame-live-p frame) (frame-visible-p frame))
        (make-frame-invisible frame))))
  (set-window-parameter window 'my/sticky-lines-shown nil))

(defun my/sticky-lines--number (window line)
  "Return LINE's number as WINDOW draws it, or an empty string without numbers."
  (if (not (buffer-local-value 'display-line-numbers (window-buffer window)))
      ""
    (with-selected-window window
      (let* ((width (line-number-display-width t))
             ;; In the text's font: as text, the numbers' own font would
             ;; make the line taller than the editor's lines.
             (face `(:inherit line-number :family ,(face-attribute 'default :family)))
             (number (propertize (number-to-string line) 'face face))
             ;; Right-aligned, a column of padding after it, as Emacs pads.
             (column (string-pixel-width (propertize " " 'face 'line-number)))
             (start (- width column (string-pixel-width number))))
        (concat (propertize " " 'display `(space :width (,(max 0 start))) 'face face)
                number
                (propertize " " 'display `(space :width (,column)) 'face face))))))

(defun my/sticky-lines--text (window starts)
  "Return the pinned lines of WINDOW starting at STARTS, as text."
  (with-current-buffer (window-buffer window)
    (mapconcat
     (lambda (start)
       (save-excursion
         (goto-char start)
         (font-lock-ensure start (pos-eol))
         (let ((code (buffer-substring start (pos-eol))))
           (remove-list-of-text-properties
            0 (length code)
            '(display invisible keymap local-map mouse-face help-echo wrap-prefix
                      line-prefix fontified cursor-sensor-functions)
            code)
           (let ((line (concat (my/sticky-lines--number window (line-number-at-pos start t))
                               code
                               ;; To the window's edge, for the mouse highlight.
                               (propertize " " 'display '(space :align-to right)))))
             (add-text-properties 0 (length line)
                                  (list 'my/sticky-lines-target start
                                        'mouse-face 'my/sticky-lines-hover)
                                  line)
             line))))
     starts "\n")))

(defun my/sticky-lines--show (window text)
  "Pin TEXT, the pinned lines, over the top of WINDOW."
  (pcase-let* ((`(,text-frame . ,line-frame) (my/sticky-lines--frames window))
               (source (window-buffer window))
               (`(,left ,top ,right ,_) (window-inside-pixel-edges window))
               (width (- right left))
               (text-window (frame-root-window text-frame))
               (window-min-height 0)
               (window-safe-min-height 0)
               (window-min-width 0)
               (window-safe-min-width 0))
    (with-current-buffer (window-buffer text-window)
      (let ((inhibit-read-only t))
        (setq-local my/sticky-lines--source window
                    line-spacing (buffer-local-value 'line-spacing source)
                    face-remapping-alist (buffer-local-value 'face-remapping-alist source))
        (erase-buffer)
        (insert text)
        (goto-char (point-min))))
    (set-frame-parameter text-frame 'background-color
                         (face-background 'default (window-frame window) t))
    (let ((height (cdr (window-text-pixel-size text-window nil nil width 10000))))
      (unless (equal (cons (frame-pixel-width text-frame) (frame-pixel-height text-frame))
                     (cons width height))
        (set-frame-size text-frame width height t))
      (unless (equal (frame-position text-frame) (cons left top))
        (set-frame-position text-frame left top))
      (set-frame-parameter line-frame 'background-color
                           (face-background 'my/sticky-lines-border nil t))
      (unless (equal (cons (frame-pixel-width line-frame) (frame-pixel-height line-frame))
                     (cons width 1))
        (set-frame-size line-frame width 1 t))
      (unless (equal (frame-position line-frame) (cons left (+ top height)))
        (set-frame-position line-frame left (+ top height))))
    (dolist (frame (list text-frame line-frame))
      (unless (frame-visible-p frame)
        (make-frame-visible frame)))
    (set-window-parameter window 'my/sticky-lines-shown
                          (list text (window-inside-pixel-edges window)))))

;;;; Updating

(defun my/sticky-lines--wanted-p (window)
  "Return non-nil when WINDOW should pin lines."
  (and (window-live-p window)
       (not (window-minibuffer-p window))
       (not (frame-parent (window-frame window)))
       (not (window-parameter window 'window-side))
       (with-current-buffer (window-buffer window)
         (and (derived-mode-p 'prog-mode)
              (not (buffer-local-value 'my/sticky-lines--source (current-buffer)))))
       (> (window-body-height window) (* 2 my/sticky-lines-max))))

(defun my/sticky-lines-update (window)
  "Pin the right lines over the top of WINDOW, if they changed."
  (if (not (and (bound-and-true-p my/sticky-lines-mode)
                (my/sticky-lines--wanted-p window)))
      (when (window-live-p window)
        (my/sticky-lines--hide window))
    (let ((starts (my/sticky-lines--lines window)))
      (if (null starts)
          (my/sticky-lines--hide window)
        (let ((text (my/sticky-lines--text window starts)))
          ;; Nothing to redraw while the lines and the window stay as they
          ;; were, as when scrolling within a scope or typing below it.
          (unless (equal-including-properties
                   (window-parameter window 'my/sticky-lines-shown)
                   (list text (window-inside-pixel-edges window)))
            (my/sticky-lines--show window text)))))))

(defvar my/sticky-lines--pending nil
  "Windows whose pinned lines may have changed.")

(defvar my/sticky-lines--timer nil)

(defun my/sticky-lines--run ()
  "Update the windows waiting for it."
  (setq my/sticky-lines--timer nil)
  (let ((windows (seq-uniq my/sticky-lines--pending)))
    (setq my/sticky-lines--pending nil)
    (dolist (window windows)
      (when (window-live-p window)
        (with-demoted-errors "Sticky lines: %S"
          (my/sticky-lines-update window))))))

(defun my/sticky-lines--schedule (window &optional delay)
  "Update WINDOW's pinned lines after DELAY seconds, or once Emacs is free."
  (push window my/sticky-lines--pending)
  (unless my/sticky-lines--timer
    ;; Not during redisplay, which calls the scroll functions.
    (setq my/sticky-lines--timer
          (run-with-timer (or delay 0) nil #'my/sticky-lines--run))))

(defun my/sticky-lines--scrolled (window _start)
  "Update WINDOW's pinned lines once it has scrolled."
  (my/sticky-lines--schedule window))

(defun my/sticky-lines--frame-changed (frame)
  "Update the pinned lines of FRAME's windows, and drop those of dead ones."
  (unless (frame-parent frame)
    (dolist (window (window-list frame 'never))
      (my/sticky-lines--schedule window))))

(defun my/sticky-lines--cleanup ()
  "Delete the child frames of windows that are gone."
  (dolist (frame (frame-list))
    (when-let* (((frame-parent frame))
                (window-frame (frame-root-window frame))
                (buffer (window-buffer window-frame))
                (source (buffer-local-value 'my/sticky-lines--source buffer)))
      (unless (window-live-p source)
        (delete-frame frame)
        (kill-buffer buffer)))))

(defun my/sticky-lines--changed (&rest _)
  "Update the pinned lines of the windows showing this buffer, soon."
  (when (and (derived-mode-p 'prog-mode) (not my/sticky-lines--source))
    (dolist (window (get-buffer-window-list nil nil t))
      (my/sticky-lines--schedule window 0.2))))

;;;; Mouse

(defun my/sticky-lines-click (event)
  "Go to the pinned line clicked in EVENT."
  (interactive "e")
  (let* ((posn (event-start event))
         (buffer (window-buffer (posn-window posn)))
         (window (buffer-local-value 'my/sticky-lines--source buffer))
         (target (and (posn-point posn)
                      (get-text-property (posn-point posn) 'my/sticky-lines-target buffer))))
    (when (and target (window-live-p window))
      (select-frame-set-input-focus (window-frame window))
      (select-window window)
      (let ((outer (with-current-buffer buffer
                     (count-lines (point-min) (posn-point posn)))))
        (goto-char target)
        (back-to-indentation)
        ;; Below the scopes that stay pinned above it.
        (recenter (max 0 (1- outer)))))))

(defun my/sticky-lines-wheel (event)
  "Scroll the window under the pinned lines by EVENT."
  (interactive "e")
  (let* ((buffer (window-buffer (posn-window (event-start event))))
         (window (buffer-local-value 'my/sticky-lines--source buffer)))
    (when (window-live-p window)
      (let* ((event (copy-sequence event))
             (command (with-selected-window window
                        (key-binding (vector (car event))))))
        (setcar (cdr event) (posn-at-x-y 1 1 window))
        (when (commandp command)
          (with-selected-window window
            (funcall-interactively command event)))))))

(defvar-keymap my/sticky-lines-map
  "<mouse-1>" #'my/sticky-lines-click
  "<down-mouse-1>" #'ignore
  "<wheel-up>" #'my/sticky-lines-wheel
  "<wheel-down>" #'my/sticky-lines-wheel)

;;;; Mode

(define-minor-mode my/sticky-lines-mode
  "Pin the first lines of the scopes the top of each window is in."
  :global t
  (dolist (frame (frame-list))
    (unless (frame-parent frame)
      (dolist (window (window-list frame 'never))
        (if my/sticky-lines-mode
            (my/sticky-lines--schedule window)
          (my/sticky-lines--delete window)))))
  (if my/sticky-lines-mode
      (progn
        (add-hook 'window-scroll-functions #'my/sticky-lines--scrolled)
        (add-hook 'window-size-change-functions #'my/sticky-lines--frame-changed)
        (add-hook 'window-buffer-change-functions #'my/sticky-lines--frame-changed)
        (add-hook 'window-configuration-change-hook #'my/sticky-lines--cleanup)
        (add-hook 'after-change-functions #'my/sticky-lines--changed))
    (remove-hook 'window-scroll-functions #'my/sticky-lines--scrolled)
    (remove-hook 'window-size-change-functions #'my/sticky-lines--frame-changed)
    (remove-hook 'window-buffer-change-functions #'my/sticky-lines--frame-changed)
    (remove-hook 'window-configuration-change-hook #'my/sticky-lines--cleanup)
    (remove-hook 'after-change-functions #'my/sticky-lines--changed)))

(unless noninteractive
  (my/sticky-lines-mode 1))

(provide 'init-sticky-lines)
;;; init-sticky-lines.el ends here
