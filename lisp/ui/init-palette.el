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
;; `minibuffer-message' keep working.  Messages sent meanwhile show in the
;; panel too.  Vertico draws the candidates (see init-completion.el); this
;; file places and frames them:
;;
;;     Recent                             1 / 22     title and count
;;     🔍 init                                        input
;;     ──────────────────────────────────────────     divider
;;     Buffer                                         group title
;;   ▎ 📄 init-lsp.el               ~/.emacs.d/lisp/  selected row
;;     📄 init-completion.el
;;
;; Titles, icons and the footer share an outer column; the input and the
;; candidates' names an inner one.

;;; Code:

(require 'posframe)
(require 'expui-icons)
(require 'thingatpt)

(defvar vertico-count)
(defvar consult-after-jump-hook)

(defface my/palette '((t (:inherit default)))
  "Text and background of the floating minibuffer panel."
  :group 'faces)

(defface my/palette-border '((t (:background "gray70")))
  "One-pixel outline of the floating minibuffer panel."
  :group 'faces)

(defface my/palette-title '((t (:inherit shadow)))
  "Title above the input of the floating minibuffer panel."
  :group 'faces)

(defface my/palette-divider '((t (:strike-through "gray85")))
  "Line between the input and the candidates of the panel."
  :group 'faces)

(defface my/palette-mark '((t (:background "RoyalBlue")))
  "Bar at the left of the selected candidate in the panel."
  :group 'faces)

(defvar my/palette-placement 'palette
  "Where the next minibuffer appears: `palette', `point', or nil for the echo area.
Let-bind it around code that reads from the minibuffer.")

(defvar my/palette-titles
  '((execute-extended-command . "Commands")
    (project-find-file . "Go to File")
    (find-file . "Open File")
    (consult-buffer . "Recent")
    (consult-ripgrep . "Find in Files")
    (consult-imenu . "File Structure")
    (my/file-symbols . "File Structure"))
  "Panel titles by command.  Other completions take their prompt as title.")

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
  "Height in 1/10 pt of the empty mode line padding the panel's bottom.
With the rows' own spacing it matches the side padding.")

(defvar my/palette-header-height 0.85
  "Height of the title line relative to the panel text.")

(defvar my/palette-header-padding 8
  "Space above and below the title line, in pixels.")

(defvar my/palette-input-height 1.1
  "Height of the input relative to the candidates.")

(defconst my/palette-indent 28
  "Pixels before the input and candidate text, holding the bar and icons.")

(defconst my/palette-icon-indent 6
  "Pixels before the outer column, after the bar of the selected candidate.
It holds the title, the search icon, group titles, icons and the footer;
the input and the candidates' names start at `my/palette-indent'.")

(defconst my/palette-mark-width 3
  "Width in pixels of the bar marking the selected candidate.")

(declare-function my/completion-icon "init-completion" (candidate))

(defvar-local my/palette--placement nil
  "Placement of this minibuffer session, or nil when it is not floating.")

(defvar-local my/palette--anchor nil
  "Frame pixel position (X Y LINE-HEIGHT) of the symbol for `point'.")

(defvar-local my/palette--width 0
  "Width in columns of the panel at point, fixed after its first display.")

(defvar-local my/palette--footer nil
  "Text of the line at the bottom of the panel, or nil for none.")

(defvar-local my/palette--line-face nil
  "Face attributes of a panel's title and footer lines.")

(defvar-local my/palette--edge-face nil
  "Face attributes of a panel's empty lines padding its top or bottom.")

(defvar-local my/palette--title nil
  "Title of this completion session, or nil when it shows its prompt.")

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
               ;; At point the first display fits the content; the width
               ;; then stays, so typing or moving never resizes it.
               :width (cond ((not anchor) (my/palette--columns origin))
                            ((> my/palette--width 0) my/palette--width))
               :min-width (when anchor (car my/palette-point-width))
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
      (when (zerop my/palette--width)
        (setq my/palette--width (frame-width frame))))
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

;;;; Structure

(defun my/palette--title ()
  "Return the title for this minibuffer: its command's, else its prompt."
  (let ((title (or (alist-get this-command my/palette-titles)
                   (string-trim (minibuffer-prompt) "[ \t]+" "[ \t:：]+"))))
    (unless (string-empty-p title) title)))

(defun my/palette--count ()
  "Return the position and number of candidates, or nil without any."
  (when (and (bound-and-true-p vertico--input) (boundp 'vertico--total)
             (> vertico--total 0))
    (if (>= vertico--index 0)
        (format "%d / %d" (1+ vertico--index) vertico--total)
      (number-to-string vertico--total))))

(defun my/palette--header ()
  "Return the title line: the title at the left, the count at the right."
  (let ((count (my/palette--count)))
    (concat (my/palette--space-to my/palette-icon-indent)
            (and my/palette--title
                 (propertize my/palette--title 'face 'my/palette-title))
            (when count
              (let ((width (string-pixel-width
                            (propertize count 'face
                                        `(:height ,my/palette-header-height)))))
                (concat (propertize " " 'display
                                    `(space :align-to (- right (,width))))
                        (propertize count 'face 'shadow)))))))

(defun my/palette--remap (line spec)
  "Draw LINE, `header-line' or `mode-line', with face attributes SPEC.
The minibuffer window has neither line, so only the panel shows them."
  (dolist (face (list line (intern (format "%s-active" line))
                      (intern (format "%s-inactive" line))))
    (when (facep face)
      (setq-local face-remapping-alist
                  (cons (cons face spec)
                        (assq-delete-all face (copy-sequence face-remapping-alist)))))))

(defun my/palette--footer ()
  "Return the bottom line: the footer, or a blank line padding the panel."
  (if my/palette--footer
      (concat (my/palette--space-to my/palette-icon-indent) my/palette--footer)
    " "))

(defun my/palette-set-footer (footer)
  "Show FOOTER, a string, at the bottom of this minibuffer's panel.
A nil FOOTER removes it.  Call it in the minibuffer once the panel is set
up, for hints that apply to one picker only."
  (when (and my/palette--placement (not (equal footer my/palette--footer)))
    (setq my/palette--footer footer)
    (my/palette--remap 'mode-line (if footer my/palette--line-face
                                    my/palette--edge-face))
    ;; The bottom line changes height: fit the panel once it shows.
    (run-at-time 0 nil #'my/palette--refit (current-buffer))))

(defun my/palette-text-width ()
  "Return the columns for candidate text in this minibuffer's panel, or nil."
  (when-let* ((my/palette--placement)
              (frame (bound-and-true-p posframe--frame))
              ((frame-live-p frame)))
    (- (window-body-width (frame-root-window frame))
       (ceiling my/palette-indent (frame-char-width frame)))))

(defun my/palette--replace-prompt ()
  "Show an icon instead of the prompt, which the title replaces.
The prompt's last character becomes the space before the input."
  (let ((end (minibuffer-prompt-end)))
    (when (> end (1+ (point-min)))
      (let ((icon (make-overlay (point-min) (1- end))))
        ;; JetBrains' search icon, in the face's color in the mono style.
        ;; Display strings ignore display properties inside them, so the
        ;; image is the display itself.
        (overlay-put icon 'display (or (and (expui-icons-svg-p)
                                            (expui-icons-image "general/search"))
                                       "🔍"))
        (overlay-put icon 'face 'shadow)
        (overlay-put icon 'before-string (my/palette--space-to my/palette-icon-indent))))
    (when (> end (point-min))
      ;; A display string would ignore an alignment inside it.
      (overlay-put (make-overlay (1- end) end) 'display
                   `(space :align-to (,my/palette-indent))))))

(defun my/palette--space-to (x)
  "Return a space reaching X pixels from the start of the text area."
  (propertize " " 'display `(space :align-to (,x))))

(defun my/palette--divider-args (args)
  "Put a line before the candidate lines in ARGS when they show in a panel."
  (pcase-let ((`(,lines) args))
    (if (and my/palette--placement lines)
        (list (cons (concat (propertize " " 'face 'my/palette-divider
                                        'display '(space :align-to right))
                            (propertize "\n" 'face 'my/palette-divider))
                    lines))
      args)))

(defun my/palette--space (width)
  "Return a space WIDTH pixels wide."
  (propertize " " 'display `(space :width (,(max 0 width)))))

(defun my/palette--format-candidate (format cand prefix &rest args)
  "Call FORMAT with CAND, PREFIX and ARGS, indenting panel candidates.
The indentation holds a bar for the selected candidate, then the icon of a
file or buffer below the search icon, so that names line up with the input.
Vertico puts a space before every alignment in a candidate, so the
indentation is made of exact widths instead."
  (apply format cand
         (if my/palette--placement
             (let* ((icon (and (fboundp 'my/completion-icon)
                               (my/completion-icon cand)))
                    (icon-width (if icon (car (image-size (get-text-property
                                                           0 'display icon)
                                                          t))
                                  0))
                    (mark (when (= (nth 1 args) vertico--index)
                            (propertize (my/palette--space my/palette-mark-width)
                                        'face 'my/palette-mark)))
                    (used (if mark my/palette-mark-width 0)))
               (concat mark
                       (when icon
                         (prog1 (concat (my/palette--space
                                         (- my/palette-icon-indent used))
                                        icon)
                           (setq used (+ my/palette-icon-indent icon-width))))
                       (my/palette--space (- my/palette-indent used))
                       prefix))
           prefix)
         args))

(defun my/palette--format-group-title (title)
  "Indent group TITLE in a panel like the panel title, outside its items."
  (if my/palette--placement
      (concat (my/palette--space-to my/palette-icon-indent)
              title)
    title))

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
                                  (my/palette--symbol-anchor (my/palette--origin)))
          ;; Plain prompts, such as a new name, keep their wording.
          my/palette--title (and (bound-and-true-p vertico--input)
                                 (my/palette--title)))
    (setq-local vertico-count (alist-get my/palette--placement my/palette-rows)
                truncate-lines t
                auto-hscroll-mode 'current-line
                ;; The header line holds the title; an empty mode line pads
                ;; the bottom.
                header-line-format '(:eval (my/palette--header))
                mode-line-format '(:eval (my/palette--footer)))
    (let* ((background (face-background 'my/palette nil t))
           (plain `(:box nil :overline nil :underline nil :inherit nil
                         :background ,background))
           (edge `(:height ,my/palette-edge-height ,@plain)))
      (setq my/palette--footer nil
            my/palette--edge-face edge
            my/palette--line-face
            `(:height ,my/palette-header-height
                      ,@plain :box (:line-width (0 . ,my/palette-header-padding)
                                                :color ,background)))
      ;; Without completion the header line is empty, padding like the
      ;; mode line.
      (my/palette--remap 'header-line (if (bound-and-true-p vertico--input)
                                          my/palette--line-face
                                        edge))
      (my/palette--remap 'mode-line edge))
    (let ((start (minibuffer-prompt-end)))
      (when my/palette--title
        (my/palette--replace-prompt))
      ;; Typed text grows the overlay, so it keeps the larger size.
      (overlay-put (make-overlay start (point-max) nil nil t)
                   'face `(:height ,my/palette-input-height)))
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
    ;; Let the header line appear first, so the fit counts it.
    (redisplay)
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
        (advice-add 'vertico--display-candidates :filter-args
                    #'my/palette--divider-args)
        (advice-add 'vertico--format-candidate :around
                    #'my/palette--format-candidate)
        (advice-add 'vertico--format-group-title :filter-return
                    #'my/palette--format-group-title)
        (with-eval-after-load 'consult
          (when my/palette-mode
            (setq consult-after-jump-hook
                  (cons #'my/palette-recenter
                        (remq #'recenter (remq #'my/palette-recenter
                                               consult-after-jump-hook)))))))
    (remove-hook 'minibuffer-setup-hook #'my/palette--setup)
    (advice-remove 'vertico--display-candidates #'my/palette--after-candidates)
    (advice-remove 'vertico--resize-window #'my/palette--vertico-resize)
    (advice-remove 'vertico--display-candidates #'my/palette--divider-args)
    (advice-remove 'vertico--format-candidate #'my/palette--format-candidate)
    (advice-remove 'vertico--format-group-title #'my/palette--format-group-title)
    (when (boundp 'consult-after-jump-hook)
      (setq consult-after-jump-hook
            (cons #'recenter (remq #'my/palette-recenter consult-after-jump-hook))))))

(my/palette-mode 1)

(provide 'init-palette)
;;; init-palette.el ends here
