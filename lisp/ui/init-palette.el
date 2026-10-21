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
(require 'ui-layout)

(defvar vertico-count)
(defvar consult-after-jump-hook)

(defface my/palette '((t (:inherit default)))
  "Text and background of the floating minibuffer panel."
  :group 'faces)

(defface my/palette-border '((t (:background "gray70")))
  "One-pixel outline of the floating minibuffer panel."
  :group 'faces)

(defface my/palette-edge '((t (:foreground "gray70")))
  "Side outline drawn in the panel's fringes; follows `my/palette-border'."
  :group 'faces)

(defface my/palette-title '((t (:inherit shadow)))
  "Title above the input of the floating minibuffer panel."
  :group 'faces)

(defface my/palette-divider '((t (:strike-through "gray85")))
  "Line between the input and the candidates of the panel."
  :group 'faces)

(defface my/palette-tab '((t (:inherit shadow)))
  "Tab of the panel's header that is not the current one."
  :group 'faces)

(defface my/palette-tab-active '((t (:inherit highlight)))
  "Current tab of the panel's header."
  :group 'faces)

(defface my/palette-footer '((t (:background "gray96")))
  "Band at the bottom of the panel holding the footer."
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
  "Panel titles by command.
Completions opened by no command, such as replies of a language server,
are titled by category in `my/palette-category-titles'; others take their
prompt as title.")

(defvar my/palette-category-titles
  '((imenu . "File Structure")
    (consult-grep . "Find in Files"))
  "Panel titles by completion category, for completions without a command.")

(defvar my/palette-actions
  '((consult-buffer "<" "Narrow"))
  "Keys named at the right of the footer, by command, as (KEY DESCRIPTION).
See `my/palette-set-action'.")

(defvar my/palette-ignore-commands
  '(my/welcome-filter)
  "Commands whose minibuffer stays in the echo area.
Live filters keep their page in view.  Expressions read in a panel show
ElDoc in its footer (see `my/palette--eldoc-display').")

(defvar my/palette-top 0.12
  "Top edge of the palette as a fraction of the frame height.")

(defvar my/palette-width '(0.55 72 . 120)
  "Palette width: fraction of the frame, then minimum and maximum columns.")

(defvar my/palette-point-width '(48 . 100)
  "Minimum and maximum columns of the panel at point.")

(defvar my/palette-rows '((palette . 14) (point . 8))
  "Candidates shown by each placement.")

(defvar my/palette-line-spacing
  (if (< emacs-major-version 31) 0.44 '(0.22 . 0.22))
  "Extra spacing relative to the line height of each row.
Emacs 31 splits it above and below; older versions put it all below.")

(defconst my/palette-padding (* 3 my/ui-space-small)
  "Horizontal padding inside the panel, in pixels.")

(defvar my/palette-radius 8
  "Radius of the panel's rounded corners, in pixels.")

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

(defvar-local my/palette--editor nil
  "Editor window selected when this minibuffer opened.")

(defvar-local my/palette--anchor nil
  "Frame pixel position (X Y LINE-HEIGHT) of the symbol for `point'.")

(defvar-local my/palette--width 0
  "Width in columns of the panel at point, fixed after its first display.")

(defvar-local my/palette--list nil
  "Non-nil when this panel lists candidates, so that it has a footer.")

(defvar-local my/palette--status nil
  "Status shown at the left of the footer instead of the detail, or nil.")

(defvar-local my/palette--action nil
  "Key named at the right of the footer, as (KEY DESCRIPTION), or nil.")

(defvar-local my/palette--line-face nil
  "Face attributes of a panel's title and footer lines.")

(defvar-local my/palette--footer-face nil
  "Face attributes of a panel's footer band.")

(defvar-local my/palette--tabs nil
  "Tabs shown in the header instead of the title, or nil.")

(defvar-local my/palette--icon nil
  "Overlay showing the search icon in place of the prompt, or nil.")

(defvar-local my/palette--input-start nil
  "Overlay of the space before the input, or nil.")

(defvar-local my/palette--prefix nil
  "Overlay showing the prefix of the input, or nil.")

(defvar-local my/palette--outside nil
  "Color under the panel, shown in its cut-off corners.")

(defvar-local my/palette--edge-face nil
  "Face of the empty mode line padding the bottom of a panel without a list.")

(defvar-local my/palette--line-heights nil
  "Alist of a header or mode line face and its height in pixels.")

(defvar-local my/palette--title nil
  "Title of this minibuffer, or nil when it shows its prompt.")

;;;; Placement

(defun my/palette--origin ()
  "Return the editor window that was selected when the minibuffer opened.
It is kept from the start: a click on the panel selects the panel's own
window."
  (let ((window (or my/palette--editor (minibuffer-selected-window))))
    (if (and (window-live-p window) (not (frame-parent (window-frame window))))
        window
      (frame-first-window (or (frame-parent) (selected-frame))))))

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
    (cons (max 0 (min (- x my/palette-padding my/palette-indent)
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
               ;; The panel draws its own rounded outline (see
               ;; `my/palette--rounded'); a frame border has square corners.
               :border-width 0
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
    ;; Fringes are the horizontal padding: paint them like the panel, with
    ;; the side outline at their outer edge.
    (let ((color (face-background 'my/palette nil t))
          (line (face-background 'my/palette-border nil t)))
      (unless (equal (face-background 'fringe frame t) color)
        (set-face-background 'fringe color frame))
      (unless (equal (face-foreground 'my/palette-edge frame t) line)
        (set-face-foreground 'my/palette-edge line frame)))
    ;; The cut-off corners show what the panel sits on.
    ;; Editor windows have the theme's background, whatever their frame's.
    (setq my/palette--outside (if (fboundp 'my/islands--card)
                                  (my/islands--card)
                                (face-background 'default (window-frame origin) t)))))

(defvar my/palette--echo-height nil
  "Height of the echo area, in pixels, recorded before a panel opens.")

(defun my/palette--display ()
  "Show this minibuffer in its panel and hide the echo-area copy.
The copy is scrolled out of view; its window keeps the echo area's height,
so the windows above do not move while the panel is open."
  ;; A click on the panel selects its frame; the panel belongs to the
  ;; editor frame.
  (when-let* ((parent (frame-parent)))
    (select-frame parent t))
  (when-let* ((window (active-minibuffer-window))
              ((eq (window-buffer window) (current-buffer))))
    (setq-local resize-mini-windows nil)
    (let ((delta (- (or my/palette--echo-height 0) (window-pixel-height window))))
      (unless (zerop delta)
        (ignore-errors (window-resize window delta nil nil 'pixelwise))))
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
                   (and minibuffer-completion-table
                        (alist-get (completion-metadata-get
                                    (completion-metadata
                                     "" minibuffer-completion-table
                                     minibuffer-completion-predicate)
                                    'category)
                                   my/palette-category-titles))
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
  "Return the title line: the title or tabs at the left, the count at the right."
  (let ((count (my/palette--count)))
    (concat (my/ui-space-to my/palette-icon-indent)
            (or my/palette--tabs
                (and my/palette--title
                     (propertize (my/palette--literal my/palette--title)
                                 'face 'my/palette-title)))
            (when count
              (my/palette--at-right (propertize count 'face 'shadow))))))

(define-fringe-bitmap 'my/palette-edge-left
  (vector (ash 1 (1- my/palette-padding))) 1 my/palette-padding '(top periodic))
(define-fringe-bitmap 'my/palette-edge-right [1] 1 my/palette-padding '(top periodic))

(defconst my/palette--edges
  (concat (propertize " " 'display '(left-fringe my/palette-edge-left my/palette-edge))
          (propertize " " 'display '(right-fringe my/palette-edge-right my/palette-edge)))
  "Text that draws the side outline in the fringes of its row.")

(defun my/palette--line-height (face)
  "Return the height of a header or mode line in FACE, measured once."
  (or (alist-get face my/palette--line-heights nil nil #'eq)
      (setf (alist-get face my/palette--line-heights nil nil #'eq)
            (my/ui-line-height face))))

(defun my/palette--rounded (text top)
  "Return TEXT as the panel's TOP line, or else its bottom one.
Its corners are rounded and carry the outline's sides around them."
  (let ((face (cond (top my/palette--line-face)
                    ((my/palette--banded-p) my/palette--footer-face)
                    (t my/palette--edge-face))))
    (if (not (and my/palette--outside (display-graphic-p)))
        text
      (my/ui-rounded-line text my/palette-radius (my/palette--line-height face)
                          (plist-get face :background) my/palette--outside
                          (face-background 'my/palette-border nil t) top))))

(defun my/palette--remap (line spec)
  "Draw LINE, `header-line' or `mode-line', with face attributes SPEC.
The minibuffer window has neither line, so only the panel shows them."
  (dolist (face (list line (intern (format "%s-active" line))
                      (intern (format "%s-inactive" line))))
    (when (facep face)
      (setq-local face-remapping-alist
                  (cons (cons face spec)
                        (assq-delete-all face (copy-sequence face-remapping-alist)))))))

(defun my/palette--literal (text)
  "Return TEXT for the header or footer, which read % as a format directive."
  (string-replace "%" "%%" text))

(defun my/palette--at-right (text)
  "Return TEXT, in the title and footer size, aligned to the right edge."
  (concat (my/ui-right-space
           (propertize text 'face `(:inherit my/ui-font
                                    :height ,my/palette-header-height)))
          text))

(defun my/palette--detail (width)
  "Return the full location or description of the selected candidate.
It is shortened from the left to WIDTH columns."
  (when-let* (((fboundp 'my/completion-detail))
              ((>= vertico--index 0))
              (detail (my/completion-detail (vertico--candidate))))
    (propertize (my/palette--literal (my/ui-fit-left detail width))
                'face 'shadow)))

(defun my/palette--banded-p ()
  "Return non-nil when the panel's bottom line is a footer band, not padding.
A list always has one; a panel without a list, while it has a status."
  (or my/palette--list my/palette--status))

(defun my/palette--footer ()
  "Return the bottom line.
A list's footer tells about the selected candidate, or the picker's status,
at the left, and names one key at the right.  Without a list it shows the
status, such as ElDoc's, or else is blank, padding the panel."
  (cond
   ((and (not my/palette--list) my/palette--status)
    (concat (my/ui-space-to my/palette-icon-indent)
            (my/palette--literal
             (truncate-string-to-width my/palette--status
                                       (+ 2 (or (my/palette-text-width) 80)) nil nil "…"))))
   ((not my/palette--list)
    " ")
   (t
    (let* ((action (when my/palette--action
                     (concat (propertize (my/palette--literal (car my/palette--action))
                                         'face 'my/palette-title)
                             " "
                             (propertize (my/palette--literal (cadr my/palette--action))
                                         'face 'shadow))))
           (room (- (+ 2 (or (my/palette-text-width) 80))
                    (if action (+ 3 (string-width action)) 0))))
      (concat (my/ui-space-to my/palette-icon-indent)
              (if my/palette--status
                  (my/palette--literal (my/ui-fit-left my/palette--status room))
                (my/palette--detail room))
              (and action (my/palette--at-right action)))))))

(defun my/palette-set-status (status)
  "Show STATUS at the left of this panel's footer, instead of the detail.
STATUS tells why a list is empty, for example; nil gives the place back to
the selected candidate.  Call it in the minibuffer."
  (when my/palette--placement
    (let ((banded (my/palette--banded-p)))
      (setq my/palette--status status)
      ;; A panel without a list gains or loses its footer band.
      (unless (eq (and banded t) (and (my/palette--banded-p) t))
        (my/palette--remap 'mode-line (if (my/palette--banded-p)
                                          my/palette--footer-face
                                        my/palette--edge-face))
        (my/palette--display)))
    (force-mode-line-update t)))

(defun my/palette--eldoc-display (docs _interactive)
  "Show the first of ElDoc's DOCS in the panel's footer, or clear it.
In the echo area ElDoc writes into the mode line of the window above,
which the frame's single status bar leaves no room for."
  (my/palette-set-status
   (when-let* ((doc (car docs)))
     (let ((text (car (split-string (car doc) "\n")))
           (thing (plist-get (cdr doc) :thing)))
       (if thing
           (concat (propertize (format "%s" thing)
                               'face (or (plist-get (cdr doc) :face) 'my/palette-title))
                   ": " text)
         text)))))

(defun my/palette-set-tabs (tabs)
  "Show TABS, a string, in this panel's header instead of its title.
Pickers that are kinds of one search show which kind is open; see
init-search.el.  Call it in the minibuffer."
  (when my/palette--placement
    (setq my/palette--tabs tabs)
    ;; Every kind of the search shows the search icon, lists or not.
    (when (overlayp my/palette--icon)
      (overlay-put my/palette--icon 'display (my/palette--search-icon)))
    (force-mode-line-update t)))

(defun my/palette-set-action (key description)
  "Name KEY, a string, and what it does, DESCRIPTION, in this panel's footer.
Each picker names at most one key, one that is easy to miss."
  (when my/palette--placement
    (setq my/palette--action (and key (list key description)))
    (force-mode-line-update t)))

(defun my/palette-text-width ()
  "Return the columns for candidate text in this minibuffer's panel, or nil."
  (when-let* ((my/palette--placement)
              (frame (bound-and-true-p posframe--frame))
              ((frame-live-p frame)))
    (- (window-body-width (frame-root-window frame))
       (ceiling my/palette-indent (frame-char-width frame)))))

(defun my/palette--search-icon ()
  "Return the display of the search icon."
  ;; JetBrains' search icon, in the face's color in the mono style.
  ;; Display strings ignore display properties inside them, so the image
  ;; is the display itself.
  (if (expui-icons-svg-p) (expui-icons-image "general/search") "🔍"))

(defun my/palette--replace-prompt (search)
  "Hide the prompt, which the title replaces, showing an icon if SEARCH.
The prompt's last character becomes the space before the input, so that
input lines up with candidates, or with the input of other panels."
  (let ((end (minibuffer-prompt-end)))
    (when (> end (1+ (point-min)))
      (let ((icon (make-overlay (point-min) (1- end))))
        (overlay-put icon 'display (if search (my/palette--search-icon) ""))
        (overlay-put icon 'face 'shadow)
        (overlay-put icon 'before-string (my/ui-space-to my/palette-icon-indent))
        (setq my/palette--icon icon)))
    (when (> end (point-min))
      ;; A display string would ignore an alignment inside it.
      (let ((space (make-overlay (1- end) end)))
        (overlay-put space 'display `(space :align-to (,my/palette-indent)))
        (setq my/palette--input-start space)))))

(defun my/palette-set-prefix (prefix)
  "Show PREFIX, faded, before the input of this panel, or nothing if nil.
It reads as the start of the input, as in VS Code's quick open, without
being part of what is matched.  It is drawn on the prompt's last
characters, so that messages shown after the input stay after it.  Call
it in the minibuffer."
  (when (overlayp my/palette--input-start)
    (let* ((end (overlay-end my/palette--input-start))
           (start (overlay-start my/palette--input-start))
           ;; The space before the input moves one character back, onto the
           ;; icon's last character, to leave the prompt's last one for
           ;; the prefix.
           (room (and prefix (overlayp my/palette--icon)
                      (> (overlay-end my/palette--icon)
                         (1+ (overlay-start my/palette--icon))))))
      (if (not room)
          (progn
            (move-overlay my/palette--input-start start end)
            (when (overlayp my/palette--prefix) (delete-overlay my/palette--prefix)))
        (move-overlay my/palette--icon (overlay-start my/palette--icon) (1- start))
        (move-overlay my/palette--input-start (1- start) start)
        (unless (overlayp my/palette--prefix)
          (setq my/palette--prefix (make-overlay start end)))
        (move-overlay my/palette--prefix start end)
        (overlay-put my/palette--prefix 'display
                     ;; Plain, not in the bold of the prompt it covers.
                     (propertize (concat prefix " ")
                                 'face `(:inherit shadow :weight normal
                                         :height ,my/palette-input-height)))))))

(defun my/palette--divider-args (args)
  "Put a line before the candidate lines in ARGS when they show in a panel.
Every line draws the panel's side outline in the fringes."
  (pcase-let ((`(,lines) args))
    (if (and my/palette--placement lines)
        (list (mapcar (lambda (line) (concat my/palette--edges line))
                      (cons (concat (propertize " " 'face 'my/palette-divider
                                                'display '(space :align-to right))
                                    (propertize "\n" 'face 'my/palette-divider))
                            lines)))
      args)))

(defun my/palette--format-candidate (format cand prefix &rest args)
  "Call FORMAT with CAND, PREFIX and ARGS, indenting panel candidates.
The indentation holds a bar for the selected candidate, then the icon of a
file or buffer below the search icon, so that names line up with the input.
Vertico puts a space before every alignment in a candidate, so the
indentation is made of exact widths instead.  Emoji and symbols are scaled
to the row, which the panel's height counts on."
  (apply format (if my/palette--placement (my/ui-fit-tall-glyphs cand) cand)
         (if my/palette--placement
             (let* ((icon (and (fboundp 'my/completion-icon)
                               (my/completion-icon cand)))
                    (icon-width (if icon (car (image-size (get-text-property
                                                           0 'display icon)
                                                          t))
                                  0))
                    (mark (when (= (nth 1 args) vertico--index)
                            (propertize (my/ui-space my/palette-mark-width)
                                        'face 'my/palette-mark)))
                    (used (if mark my/palette-mark-width 0)))
               (concat mark
                       (when icon
                         (prog1 (concat (my/ui-space
                                         (- my/palette-icon-indent used))
                                        icon)
                           (setq used (+ my/palette-icon-indent icon-width))))
                       (my/ui-space (- my/palette-indent used))
                       prefix))
           prefix)
         args))

(defun my/palette--format-group-title (title)
  "Indent group TITLE in a panel like the panel title, outside its items."
  (if my/palette--placement
      (concat (my/ui-space-to my/palette-icon-indent)
              title)
    title))

;;;; Session

(defun my/palette--setup ()
  "Decide where this minibuffer appears before it is first displayed."
  (when (= (minibuffer-depth) 1)
    (setq my/palette--echo-height (window-pixel-height (minibuffer-window))))
  (setq my/palette--placement
        (and (display-graphic-p)
             (not (memq this-command my/palette-ignore-commands))
             my/palette-placement))
  (when my/palette--placement
    ;; One panel at a time: an enclosing one comes back when this exits
    ;; (see `my/palette--after-exit').
    (when (> (minibuffer-depth) 1)
      (dolist (buffer (buffer-list))
        (when (and (not (eq buffer (current-buffer)))
                   (minibufferp buffer t)
                   (buffer-local-value 'my/palette--placement buffer))
          (posframe-hide buffer))))
    (setq my/palette--editor nil
          my/palette--editor (my/palette--origin)
          my/palette--width 0
          my/palette--anchor (and (eq my/palette--placement 'point)
                                  (my/palette--symbol-anchor (my/palette--origin)))
          my/palette--list (bound-and-true-p vertico--input)
          my/palette--title (my/palette--title))
    (setq-local eldoc-display-functions (list #'my/palette--eldoc-display))
    (setq-local vertico-count (alist-get my/palette--placement my/palette-rows)
                truncate-lines t
                auto-hscroll-mode 'current-line
                ;; The header line holds the title, the mode line the footer
                ;; of a list or else padding.
                header-line-format '(:eval (my/palette--rounded (my/palette--header) t))
                mode-line-format '(:eval (my/palette--rounded (my/palette--footer) nil)))
    (let* ((background (face-background 'my/palette nil t))
           (border (face-background 'my/palette-border nil t))
           ;; The outline's top runs along the header line, its bottom along
           ;; the mode line; an underline that low lands on the last pixel.
           (top `(:overline ,border :underline nil))
           (bottom `(:overline nil :underline (:color ,border :position 100)))
           (plain `(:box nil :inherit my/ui-font :background ,background))
           (edge `(:height ,my/palette-edge-height ,@bottom ,@plain)))
      (setq my/palette--status nil
            my/palette--tabs nil
            my/palette--icon nil
            my/palette--input-start nil
            my/palette--prefix nil
            my/palette--action (alist-get this-command my/palette-actions)
            my/palette--edge-face edge
            my/palette--line-heights nil
            my/palette--line-face
            `(:height ,my/palette-header-height ,@top
                      ,@plain :box (:line-width (0 . ,my/palette-header-padding)
                                                :color ,background))
            my/palette--footer-face
            (let ((band (face-background 'my/palette-footer nil t)))
              `(:height ,my/palette-header-height ,@bottom
                        :inherit my/ui-font :background ,band
                        :box (:line-width (0 . ,my/palette-header-padding)
                                          :color ,band))))
      (my/palette--remap 'header-line my/palette--line-face)
      (my/palette--remap 'mode-line (if my/palette--list my/palette--footer-face
                                      edge)))
    ;; Interface text in the interface font; pickers keep code in the code
    ;; font (init-completion.el).
    (face-remap-add-relative 'default 'my/ui-font)
    (overlay-put (make-overlay (point-min) (point-min)) 'before-string my/palette--edges)
    (let ((start (minibuffer-prompt-end)))
      (when my/palette--title
        (my/palette--replace-prompt my/palette--list))
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
  ;; Never leave the hidden panel selected: keys would go nowhere.
  (when-let* ((parent (frame-parent)))
    (select-frame parent t))
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
  "Show BUFFER's panel again if its minibuffer is still active.
Each fit measures the header and mode lines as the last redisplay drew
them, and they grow as they gain their spacing and corners; fit again
until the panel's height settles.  A list's panel also refits whenever
the list updates, but a panel without one has only this."
  (when (and (minibufferp buffer t)
             (buffer-local-value 'my/palette--placement buffer))
    (let ((height nil) (tries 0))
      (while (and (< tries 4)
                  (not (eql height (my/palette--frame-height buffer))))
        (setq height (my/palette--frame-height buffer)
              tries (1+ tries))
        ;; Let the header line appear first, so the fit counts it.
        (redisplay)
        (with-current-buffer buffer
          (my/palette--display))))))

(defun my/palette--frame-height (buffer)
  "Return the pixel height of BUFFER's panel, or nil when it has none."
  (when-let* ((frame (seq-find (lambda (frame)
                                 (and (frame-parent frame)
                                      (eq (window-buffer (frame-root-window frame))
                                          buffer)))
                               (frame-list))))
    (frame-pixel-height frame)))

(defun my/palette-active-placement ()
  "Return the placement of the active minibuffer, or nil."
  (when-let* ((window (active-minibuffer-window)))
    (buffer-local-value 'my/palette--placement (window-buffer window))))

(defun my/palette-recenter ()
  "Recenter after a jump, keeping a previewed line below the palette."
  (if (eq (my/palette-active-placement) 'palette)
      (recenter (round (* 0.62 (window-body-height))))
    (recenter)))

(defun my/palette--nested-exit ()
  "Hide an enclosing panel's echo-area copy again after this minibuffer exits.
All minibuffers share the echo area's window: one nested in a panel's, and
not in a panel itself (such as \\[eval-expression]), resizes and scrolls
it, so the panel's input would show there until the panel next redraws."
  (when (and (> (minibuffer-depth) 1) (not my/palette--placement))
    (run-at-time 0 nil #'my/palette--rehide (current-buffer))))

(defun my/palette--rehide (buffer)
  "Show the panel enclosing BUFFER's minibuffer again, once it has exited.
The redisplay that follows the exit puts the shared window back at the
start of the text; let it happen first, or it undoes the hiding."
  (redisplay t)
  (my/palette--after-exit buffer))

(define-minor-mode my/palette-mode
  "Show the minibuffer in a floating panel instead of the echo area."
  :global t
  :group 'minibuffer
  (if my/palette-mode
      (progn
        (add-hook 'minibuffer-setup-hook #'my/palette--setup 50)
        (add-hook 'minibuffer-exit-hook #'my/palette--nested-exit)
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
    (remove-hook 'minibuffer-exit-hook #'my/palette--nested-exit)
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
