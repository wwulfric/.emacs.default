;;; init-palette.el --- Minibuffer in a floating panel -*- lexical-binding: t; -*-

;;; Commentary:
;; Minibuffer input appears in a child frame instead of the echo area:
;;
;;   palette  top center of the frame: commands, files, buffers and search.
;;   point    under the symbol at point: choices about that symbol, such as
;;            its implementations, references and new name.
;;
;; The child frame only displays the minibuffer buffer.  The minibuffer
;; window stays selected and is scrolled out of sight, so focus never leaves
;; the editor frame: key maps, input methods, recursive minibuffers and
;; `minibuffer-message' keep working.  Vertico draws the candidates (see
;; init-completion.el); this file only places and frames them.  Messages still
;; appear in the echo area.

;;; Code:

(require 'posframe)
(require 'thingatpt)

(defvar vertico-count)
(defvar consult-after-jump-hook)

(defface my/palette '((t (:inherit default)))
  "Text and background of the floating minibuffer panel."
  :group 'faces)

(defface my/palette-border '((t (:background "gray70")))
  "One-pixel outline of the floating minibuffer panel."
  :group 'faces)

(defvar my/palette-placement 'palette
  "Where the next minibuffer appears: `palette', `point', or nil for the echo area.
Let-bind it around code that reads from the minibuffer.")

(defvar my/palette-ignore-commands
  '(eval-expression edebug-eval-expression debugger-eval-expression
    my/welcome-filter)
  "Commands whose minibuffer stays in the echo area.
Expressions keep ElDoc beside them; live filters keep their page in view.")

(defvar my/palette-top 0.12
  "Top edge of the palette as a fraction of the frame height.")

(defvar my/palette-width '(0.45 64 . 100)
  "Palette width: fraction of the frame, then minimum and maximum columns.")

(defvar my/palette-point-width '(48 . 100)
  "Minimum and maximum columns of the panel at point.")

(defvar my/palette-rows '((palette . 10) (point . 8))
  "Candidates shown by each placement.")

(defvar my/palette-line-spacing '(0.22 . 0.22)
  "Space above and below each row, relative to the line height.")

(defconst my/palette-padding (* 3 my/ui-space-small)
  "Horizontal padding inside the panel, in pixels.")

(defconst my/palette-border-width 1)

(defvar my/palette-edge-height 80
  "Height in 1/10 pt of the empty header and mode lines padding the panel.
With the rows' own spacing they match the side padding.")

(defvar-local my/palette--placement nil
  "Placement of this minibuffer session, or nil when it is not floating.")

(defvar-local my/palette--anchor nil
  "Frame pixel position (X Y LINE-HEIGHT) of the symbol for `point'.")

(defvar-local my/palette--width 0
  "Widest panel at point so far; it never narrows while typing.")

;;;; Placement

(defun my/palette--origin ()
  "Return the editor window that was selected when the minibuffer opened."
  (let ((window (minibuffer-selected-window)))
    (if (window-live-p window) window (frame-first-window))))

(defun my/palette--symbol-anchor (window)
  "Return the frame pixel position of the symbol at point in WINDOW."
  (with-selected-window window
    (let* ((start (or (car (bounds-of-thing-at-point 'symbol)) (point)))
           (xy (and (pos-visible-in-window-p start window)
                    (posn-x-y (posn-at-point start window))))
           (edges (window-inside-pixel-edges window)))
      (when xy
        (list (+ (nth 0 edges) (car xy))
              (+ (nth 1 edges) (cdr xy))
              (save-excursion (goto-char start) (line-pixel-height)))))))

(defun my/palette--top-center (info)
  "Center the panel horizontally near the top of its frame, per INFO."
  (cons (/ (- (plist-get info :parent-frame-width)
              (plist-get info :posframe-width))
           2)
        (round (* my/palette-top (plist-get info :parent-frame-height)))))

(defun my/palette--below-symbol (info)
  "Align the panel's text with the symbol of INFO, below or above its line."
  (pcase-let* ((`(,x ,y ,line) (plist-get info :anchor))
               (width (plist-get info :posframe-width))
               (height (plist-get info :posframe-height))
               (below (+ y line)))
    (cons (max 0 (min (- x my/palette-border-width my/palette-padding)
                      (- (plist-get info :parent-frame-width) width)))
          (max 0 (if (> (+ below height) (plist-get info :parent-frame-height))
                     (- y height)
                   below)))))

(defun my/palette--columns (window)
  "Return the palette width in columns for WINDOW's frame."
  (pcase-let ((`(,ratio ,min . ,max) my/palette-width))
    (max min (min max (round (* ratio (frame-width (window-frame window))))))))

;;;; Display

(defun my/palette--show ()
  "Display the current minibuffer buffer in its floating panel."
  (let* ((buffer (current-buffer))
         (input (point))
         (anchor (and (eq my/palette--placement 'point) my/palette--anchor))
         (min-width (max (car my/palette-point-width) my/palette--width))
         (origin (my/palette--origin))
         (frame
          ;; Poshandlers measure the editor window, not the minibuffer.
          (with-selected-window origin
            ;; The panel never covers the pointer's work: leave it alone.
            (let ((posframe-mouse-banish-function #'ignore))
              (posframe-show
               buffer
               :poshandler (if anchor #'my/palette--below-symbol
                             #'my/palette--top-center)
               :poshandler-extra-info (list :anchor anchor)
               :width (unless anchor (my/palette--columns origin))
               :min-width (when anchor min-width)
               :max-width (when anchor (cdr my/palette-point-width))
               :lines-truncate t
               :cursor (default-value 'cursor-type)
               :window-point input
               :left-fringe my/palette-padding
               :right-fringe my/palette-padding
               :border-width my/palette-border-width
               :border-color (face-background 'my/palette-border nil t)
               :background-color (face-background 'my/palette nil t)
               :foreground-color (face-foreground 'my/palette nil t)
               ;; Its header and mode lines pad the panel (see the setup).
               :respect-header-line t
               :respect-mode-line t
               ;; Rows breathe without changing the echo area's height.
               :override-parameters `((line-spacing . ,my/palette-line-spacing))
               :hidehandler #'my/palette--hidehandler)))))
    (when anchor
      (setq my/palette--width (max my/palette--width (frame-width frame))))
    ;; Fringes are the horizontal padding: paint them like the panel.
    (let ((color (face-background 'my/palette nil t)))
      (unless (equal (face-background 'fringe frame t) color)
        (set-face-background 'fringe color frame)))))

(defun my/palette--display ()
  "Show this minibuffer in its panel and hide the echo-area copy."
  (when-let* ((window (active-minibuffer-window))
              ((eq (window-buffer window) (current-buffer))))
    (setq-local max-mini-window-height 1)
    (window-resize window (- (window-pixel-height window)) nil nil 'pixelwise)
    (set-window-vscroll window 100)
    (my/palette--show)))

(defun my/palette--refresh ()
  "Redisplay a floating minibuffer that Vertico does not manage."
  (when (and my/palette--placement (not (bound-and-true-p vertico--input)))
    (my/palette--display)))

(defun my/palette--after-candidates (&rest _)
  "Redisplay the panel whenever Vertico redraws, including async updates."
  (when my/palette--placement
    (my/palette--display)))

(defun my/palette--vertico-resize (resize &rest args)
  "Call RESIZE with ARGS only when the minibuffer is not floating."
  (unless my/palette--placement
    (apply resize args)))

(defun my/palette--hidehandler (info)
  "Hide a panel described by INFO once its minibuffer is no longer active."
  (not (minibufferp (cdr (plist-get info :posframe-buffer)) t)))

;;;; Session

(defun my/palette--setup ()
  "Decide where this minibuffer appears before it is first displayed."
  (setq my/palette--placement
        (and (display-graphic-p)
             (not (memq this-command my/palette-ignore-commands))
             my/palette-placement))
  (when my/palette--placement
    (setq my/palette--width 0
          my/palette--anchor (and (eq my/palette--placement 'point)
                                  (my/palette--symbol-anchor (my/palette--origin))))
    (setq-local vertico-count (alist-get my/palette--placement my/palette-rows)
                truncate-lines t
                auto-hscroll-mode 'current-line
                ;; Empty header and mode lines pad the panel above and below.
                header-line-format " "
                mode-line-format " ")
    (let ((edge `(:height ,my/palette-edge-height :box nil :overline nil
                          :underline nil :inherit nil
                          :background ,(face-background 'my/palette nil t))))
      ;; The minibuffer window has neither line, so only the panel shows them.
      (dolist (face '(header-line header-line-active header-line-inactive
                      mode-line mode-line-active mode-line-inactive))
        (when (facep face)
          (setq-local face-remapping-alist
                      (cons (cons face edge) face-remapping-alist)))))
    ;; A header line shows only once the frame is tall enough for it, so
    ;; fit the panel again after its first redisplay.
    (run-at-time 0 nil #'my/palette--refit (current-buffer))
    ;; The command loop runs this once on entry, then after every command.
    (add-hook 'post-command-hook #'my/palette--refresh 90 t)
    (add-hook 'minibuffer-exit-hook #'my/palette--exit nil t)))

(defun my/palette--exit ()
  "Hide the panel after this minibuffer exits.
Deferred so that a prompt which directly follows reuses the visible panel."
  (when-let* ((window (active-minibuffer-window)))
    (set-window-vscroll window 0))
  (run-at-time 0 nil #'my/palette--after-exit (current-buffer)))

(defun my/palette--after-exit (buffer)
  "Hide BUFFER's panel unless it is active again; show an enclosing one."
  (let* ((window (active-minibuffer-window))
         (active (and window (window-buffer window))))
    (unless (and (eq active buffer)
                 (buffer-local-value 'my/palette--placement buffer))
      (posframe-hide buffer))
    (when (and active (not (eq active buffer))
               (buffer-local-value 'my/palette--placement active))
      (with-current-buffer active
        (my/palette--display)))))

(defun my/palette--refit (buffer)
  "Show BUFFER's panel again if its minibuffer is still active."
  (when (and (minibufferp buffer t)
             (buffer-local-value 'my/palette--placement buffer))
    (with-current-buffer buffer
      (my/palette--display))))

(defun my/palette-active-placement ()
  "Return the placement of the active minibuffer, or nil."
  (when-let* ((window (active-minibuffer-window)))
    (buffer-local-value 'my/palette--placement (window-buffer window))))

(defun my/palette-recenter ()
  "Recenter after a jump, keeping a previewed line below the palette."
  (if (eq (my/palette-active-placement) 'palette)
      (recenter (round (* 0.62 (window-body-height))))
    (recenter)))

(define-minor-mode my/palette-mode
  "Show the minibuffer in a floating panel instead of the echo area."
  :global t
  :group 'minibuffer
  (if my/palette-mode
      (progn
        (add-hook 'minibuffer-setup-hook #'my/palette--setup 50)
        (advice-add 'vertico--display-candidates :after #'my/palette--after-candidates)
        (advice-add 'vertico--resize-window :around #'my/palette--vertico-resize)
        (with-eval-after-load 'consult
          (when my/palette-mode
            (setq consult-after-jump-hook
                  (cons #'my/palette-recenter
                        (remq #'recenter (remq #'my/palette-recenter
                                               consult-after-jump-hook)))))))
    (remove-hook 'minibuffer-setup-hook #'my/palette--setup)
    (advice-remove 'vertico--display-candidates #'my/palette--after-candidates)
    (advice-remove 'vertico--resize-window #'my/palette--vertico-resize)
    (when (boundp 'consult-after-jump-hook)
      (setq consult-after-jump-hook
            (cons #'recenter (remq #'my/palette-recenter consult-after-jump-hook))))))

(my/palette-mode 1)

(provide 'init-palette)
;;; init-palette.el ends here
