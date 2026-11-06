;;; tool-islands.el --- IntelliJ-style tool window lists and panes -*- lexical-binding: t; -*-

;; Copyright (C) 2026 haidao
;; SPDX-License-Identifier: Apache-2.0

;; Author: haidao
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (magit-section "4.0") (expui-icons "0.2.2"))
;; Keywords: tools, convenience
;; URL: https://github.com/wwulfric/tool-islands

;;; Commentary:
;; The pieces JetBrains' New UI builds its tool windows from, for Emacs:
;;
;; - rows of one height in the interface font, indented by depth, with a
;;   disclosure chevron, an optional checkbox and an icon;
;; - the selected row drawn as a rounded pill, fainter while another
;;   window is selected, and names too wide for the window cut at their end;
;; - a header with a title, toolbar icons and buttons;
;; - side panes that keep their width as a share of the frame's;
;; - folder trees that merge a folder holding only one folder, "a/b".
;;
;; Rows are Magit sections (magit-section, not Magit), so they fold and
;; keep their visibility across refreshes.  Git Islands draws its Git tool
;; windows with these; anything else can draw a list the same way:
;;
;;   (define-derived-mode my-list-mode magit-section-mode "List"
;;     (tool-islands-view-setup))
;;
;;   (magit-insert-section (my-root)
;;     (magit-insert-section (my-item 'a)
;;       (tool-islands-row 0 (tool-islands-icon "nodes/folder")
;;                         (tool-islands-gap) (tool-islands-fit "Name"))))
;;   (tool-islands-draw-chevrons)
;;
;; Faces and sizes have plain defaults that work in a bare Emacs; a
;; configuration can tie them to its own look.  Every measurement is in
;; pixels, for proportional text and icons.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'face-remap)
(require 'svg)
(require 'eieio)
(require 'expui-icons)
;; Rows are Magit sections, but drawing them needs no section loaded:
;; only reading their slots, which compiling needs the class for.
(eval-when-compile (require 'magit-section))

(defvar magit-root-section)

(defgroup tool-islands nil
  "IntelliJ-style tool window lists."
  :group 'tools)

;;;; Faces

(defface tool-islands-font '((t ()))
  "Typography of the tool windows' text.
Leave colors unspecified so text keeps its surrounding background."
  :group 'tool-islands)

(defface tool-islands-header
  '((((background dark))
     (:inherit (tool-islands-font default) :height 1.0 :weight normal
      :box (:line-width -1 :color "#484848")))
    (t (:inherit (tool-islands-font default) :height 1.0 :weight normal
        :box (:line-width -1 :color "#D8D8D8"))))
  "Common header face for lists, messages, diffs and merges.
The inset one-pixel box follows the actual header edges.  Customize
its color, or set `:box' to nil to hide the border."
  :group 'tool-islands)

(defface tool-islands-text '((t (:inherit tool-islands-font :height 1.0)))
  "Default text of the tool windows' lists."
  :group 'tool-islands)

(defface tool-islands-title '((t (:inherit tool-islands-font :weight medium)))
  "Tool window titles and group rows."
  :group 'tool-islands)

(defface tool-islands-neutral-icon '((t (:inherit shadow)))
  "Icons in the tool windows' rows and toolbars."
  :group 'tool-islands)

(defface tool-islands-source-icon '((t (:inherit link :underline nil)))
  "Icons of source files, drawn in the accent color."
  :group 'tool-islands)

(defface tool-islands-hl-line
  '((t (:inherit highlight)))
  "The selected rows of the selected tool window."
  :group 'tool-islands)

(defface tool-islands-hl-line-inactive
  '((t (:inherit highlight)))
  "The selected rows of a tool window that is not selected."
  :group 'tool-islands)

(defface tool-islands-toolbar-hover '((t (:inherit highlight)))
  "A header button under the mouse."
  :group 'tool-islands)

;;;; Sizes

(defconst tool-islands-indent 16 "Pixels each folder level indents its rows.")

(defcustom tool-islands-hl-margin 0
  "Pixels between a selected row and the window's edges."
  :type 'natnum
  :group 'tool-islands)

(defcustom tool-islands-hl-radius 0
  "Radius in pixels of selected rows; zero gives square corners."
  :type 'natnum
  :group 'tool-islands)

(defcustom tool-islands-row-inset 12
  "Pixels before row contents, including the selection's left end.
Keep this at least as large as the selection margin plus radius."
  :type 'natnum
  :group 'tool-islands)

(defconst tool-islands-state-width 16 "Pixels a folder's chevron takes.")

(defconst tool-islands-icon-gap 6 "Pixels between an icon and the name after it.")

(defconst tool-islands-toolbar-padding 4 "Pixels on each side of a toolbar icon.")

(defconst tool-islands-toolbar-margin 6 "Pixels between a toolbar and the window's right edge.")

(defcustom tool-islands-row-height 1.3
  "Height of a row, in frame character units."
  :type 'number
  :group 'tool-islands)

(defcustom tool-islands-header-height 1.5
  "Height of a tool window's header, in font units."
  :type 'number
  :group 'tool-islands)

(defcustom tool-islands-header-space-function nil
  "Optional function returning a header spacer display spec for WIDTH.
Use this to share exact height and baseline metrics with the surrounding
editor.  Nil measures the header's font and content measurements."
  :type '(choice (const :tag "Automatic" nil) function)
  :group 'tool-islands)

(defcustom tool-islands-header-padding 4
  "Minimum vertical padding in pixels on each side of header content."
  :type 'natnum
  :group 'tool-islands)

(defcustom tool-islands-header-ascent nil
  "Percentage of the header above the baseline, or nil to center its font.
An explicit number preserves the alignment of existing configurations."
  :type '(choice (const :tag "Automatic" nil) integer)
  :group 'tool-islands)

(defcustom tool-islands-line-end-inset 0
  "Pixels kept free at the right end of headers.
A number, or a function returning one for the window being drawn; a
configuration drawing rounded window corners there can set it."
  :type '(choice integer function)
  :group 'tool-islands)

(defvar tool-islands-source-icons
  '("xml" "c" "h" "cpp" "Csharp" "java" "kotlin" "kotlinScript" "groovy"
    "language/scala" "language/php" "python" "perl" "javaScript" "typeScript"
    "swiftLang" "nodes/sourceRoot" "nodes/testRoot" "nodes/class"
    "nodes/classAbstract" "nodes/interface" "nodes/enum" "nodes/record"
    "nodes/annotation" "nodes/exception" "nodes/abstractException")
  "Icons drawn in `tool-islands-source-icon'.
Others are drawn in `tool-islands-neutral-icon'.")

;;;; Spaces

(defun tool-islands-space (pixels)
  "Return a space PIXELS wide."
  (propertize " " 'display `(space :width (,(max 0 pixels)))))

(defun tool-islands-header-space (width)
  "Return a display spec WIDTH wide that gives a header its height."
  (if tool-islands-header-space-function
      (funcall tool-islands-header-space-function width)
    (tool-islands-default-header-space width)))

(defun tool-islands-default-header-space (width)
  "Return an automatically measured header spacer for WIDTH."
  (let* ((font (and (display-graphic-p) (face-font 'tool-islands-header)))
         (info (and font (font-info font)))
         (font-height (if info (aref info 3) (frame-char-height)))
         (font-ascent (if info (aref info 8) (* font-height 0.75)))
         (content-height
          (max font-height 16
               (if (eq (bound-and-true-p tool-islands-button-render-function)
                       'tool-islands-button-rounded)
                   (round (* 1.4 (frame-char-height)))
                 0)))
         (height (max (ceiling (* font-height tool-islands-header-height))
                      (+ content-height (* 2 tool-islands-header-padding))))
         (ascent (or tool-islands-header-ascent
                     (round (* 100.0 (/ (+ font-ascent (/ (- height font-height) 2.0))
                                        height))))))
    `(space :width ,width :height (,height) :ascent ,ascent)))

(defun tool-islands-line-end-inset ()
  "Return the pixels kept free at the right end of this window's header."
  (if (functionp tool-islands-line-end-inset)
      (funcall tool-islands-line-end-inset)
    tool-islands-line-end-inset))

(defun tool-islands-line-end ()
  "Return the `:align-to' position where header text ends."
  `(- (+ right right-fringe right-margin) (,(tool-islands-line-end-inset))))

(defun tool-islands-at-right (text &optional edge buffer)
  "Return TEXT preceded by the space that aligns its end to EDGE.
EDGE is an `:align-to' position, `right' by default.  TEXT is measured
with BUFFER's face remapping, as `string-pixel-width' does."
  (concat (propertize " " 'display
                      `(space :align-to (- ,(or edge 'right)
                                           (,(string-pixel-width text buffer)))))
          text))

;;;; Pills

(defvar tool-islands-pill-cache (make-hash-table :test #'equal)
  "Strut and pill end strings by their arguments.")

(defun tool-islands-svg-color (color)
  "Return COLOR, which may be an Emacs color name, as #RRGGBB."
  (if-let* ((values (and color (color-values color))))
      (apply #'format "#%02x%02x%02x" (mapcar (lambda (v) (/ v 257)) values))
    "none"))

(defun tool-islands-image-string (svg)
  "Return a string displaying SVG, centered on its row's text as icons are.
The image is loaded at once: a window fitted to its rows before then
would measure them as tall as their text."
  (let ((image (create-image svg 'svg t :ascent 'center :scale 1)))
    (when (display-images-p)
      (image-size image t))
    (propertize " " 'display image)))

(defun tool-islands-strut (height)
  "Return a one-pixel-wide string that makes its row HEIGHT pixels high."
  (with-memoization (gethash (list nil height) tool-islands-pill-cache)
    (tool-islands-image-string
     (format "<svg xmlns='http://www.w3.org/2000/svg' width='1' height='%d'/>"
             height))))

(defun tool-islands-pill-cap (side radius height color &optional margin outside)
  "Return a string showing the SIDE end of a pill, RADIUS pixels round.
SIDE is `left' or `right'.  The end fills a row HEIGHT pixels high in
COLOR, and also sets the row's height as `tool-islands-strut' does.  MARGIN
pixels, 0 by default, stay clear outside it, showing OUTSIDE or else the
background of the face the string is drawn in."
  (let ((margin (or margin 0)))
    (if (zerop radius)
        (propertize " " 'face (and outside `(:background ,outside))
                    'display `(space :width (,margin) :height (,height)))
      (with-memoization (gethash (list side radius height color margin outside)
				 tool-islands-pill-cache)
	(let ((width (+ margin radius)))
          (tool-islands-image-string
           (format "<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d'>\
%s<path d='%s' fill='%s'/></svg>"
                   width height
                   (if outside
                       (format "<rect width='%d' height='%d' fill='%s'/>"
                               width height (tool-islands-svg-color outside))
                     "")
                   (if (eq side 'left)
                       (format "M%d,0 A%d,%d 0 0 0 %d,%d V%d A%d,%d 0 0 0 %d,%d Z"
                               width radius radius margin radius
                               (- height radius) radius radius width height)
                     (format "M0,0 A%d,%d 0 0 1 %d,%d V%d A%d,%d 0 0 1 0,%d Z"
                             radius radius radius radius
                             (- height radius) radius radius height))
                   (tool-islands-svg-color color))))))))

(defun tool-islands-forget-pills (&rest _)
  "Draw pills again after the theme or font changed."
  (clrhash tool-islands-pill-cache))

(add-hook 'enable-theme-functions #'tool-islands-forget-pills)
(add-hook 'after-setting-font-hook #'tool-islands-forget-pills)

;;;; Rows

(defun tool-islands-row-pixels ()
  "Return the height of a row in pixels."
  (ceiling (* (frame-char-height) tool-islands-row-height)))

(defun tool-islands-row-prefix (depth &optional face)
  "Return the line prefix of a row DEPTH folders deep, which sets its height.
FACE, a selection face, highlights the row from a rounded left end."
  (concat (if face
              (tool-islands-pill-cap 'left tool-islands-hl-radius (tool-islands-row-pixels)
                                       (face-background face nil t) tool-islands-hl-margin)
            (tool-islands-strut (tool-islands-row-pixels)))
          (propertize " " 'face face
                      'display `(space :width (,(- (+ tool-islands-row-inset
                                                      (* depth tool-islands-indent))
                                                   (if face (+ tool-islands-hl-margin tool-islands-hl-radius) 1)))))))

(defun tool-islands-under-face (string face)
  "Return STRING with FACE, a selection face or nil, beneath its own faces.
Overlay strings do not take the background of the selection overlay."
  (when face
    (add-face-text-property 0 (length string) face t string))
  string)

(defun tool-islands-icon (icon)
  "Return ICON, an icon name, in the face its kind is drawn in."
  (expui-icons-icon icon :face (if (member icon tool-islands-source-icons)
                                   'tool-islands-source-icon
                                 'tool-islands-neutral-icon)))

;;;; Header buttons

(defun tool-islands-header-button (action help &rest strings)
  "Return STRINGS as a header button running ACTION, with tooltip HELP.
ACTION is a command, or a function called with the click event; it runs
in the clicked window."
  (let ((map (make-sparse-keymap)))
    ;; Act on press; this also keeps the press from resizing the window.
    (define-key map [header-line down-mouse-1]
                (lambda (event)
                  (interactive "e")
                  (select-window (posn-window (event-start event)))
                  (if (commandp action)
                      ;; The command clicked, not this lambda, is what ran.
                      (call-interactively (setq this-command action))
                    (funcall action event))))
    (define-key map [header-line mouse-1] #'ignore)
    (propertize (apply #'concat strings)
                'local-map map 'help-echo help 'pointer 'hand
                'mouse-face 'tool-islands-toolbar-hover)))


(defcustom tool-islands-header-function #'identity
  "Function given a tool window's header format, returning the one to show.
Called with one mode line format in the tool buffer during header
redisplay; return a mode line format.  The selected window need not be
that buffer's window.  Keep this function cheap and free of side effects.
The default is `identity'."
  :type 'function
  :group 'tool-islands)

(defcustom tool-islands-background-function nil
  "Function returning the color the tool windows are drawn on, or nil.
Called without arguments in the tool buffer while drawing or setting up
its header.  Return an Emacs color string.  Nil, or a function returning
nil, means the default face's background.  Existing header face remappings
are set at mode initialization; recreate buffers after changing this."
  :type '(choice (const nil) function)
  :group 'tool-islands)

(defface tool-islands-dim '((t (:inherit shadow)))
  "Folders after a file name, counts and hints."
  :group 'tool-islands)

(defface tool-islands-button '((t (:inherit link :underline nil)))
  "Secondary buttons."
  :group 'tool-islands)

(defface tool-islands-primary-button '((t (:inherit tool-islands-button :weight bold)))
  "The default button of a tool window."
  :group 'tool-islands)

;;;; Checkboxes

(defconst tool-islands-checkbox-size 14 "Pixel size of a checkbox.")

(defun tool-islands-face-color (face attribute fallback)
  "Return FACE's ATTRIBUTE color as #RRGGBB, or FALLBACK if it has none.
SVG images take the color too, and know no Emacs names such as grey50."
  (let ((color (face-attribute face attribute nil t)))
    (if (or (null color) (eq color 'unspecified)
            (string-prefix-p "unspecified" color)
            (null (color-values color)))
        fallback
      (tool-islands-svg-color color))))

(defun tool-islands-checkbox-image (state)
  "Return an upstream gutter checkbox in STATE: `on', `off' or `partial'."
  (expui-icons-image
   (pcase state
     ('on "diff/gutterCheckBoxSelected@14x14")
     ('partial "diff/gutterCheckBoxIndeterminate@14x14")
     (_ "diff/gutterCheckBox@14x14"))
   :height tool-islands-checkbox-size))

(defun tool-islands-checkbox (state &optional action help)
  "Return a checkbox in STATE that runs ACTION when clicked, with tooltip HELP."
  (let ((map (make-sparse-keymap)))
    (when action
      (define-key map [mouse-1] action)
      (define-key map [down-mouse-1] #'ignore))
    (propertize " " 'display (if (expui-icons-svg-p)
                                 (tool-islands-checkbox-image state)
                               (pcase state ('on "[x]") ('partial "[-]") (_ "[ ]")))
                'keymap map 'pointer 'hand 'help-echo help)))

;;;; Rows

(defun tool-islands-chevron (section)
  "Return SECTION's disclosure chevron, or blank room for a leaf."
  (let ((state (cond ((or (not (oref section content))
                          ;; A group listing nothing has nothing to unfold.
                          (and (null (oref section children))
                               (>= (oref section content) (oref section end))))
                      nil)
                     ((oref section hidden) 'collapsed)
                     (t 'expanded))))
    (if (display-images-p)
        (propertize " " 'face 'tool-islands-neutral-icon
                    'display (pcase state
                               ('expanded (expui-icons-image "general/chevronDown"))
                               ('collapsed (expui-icons-image "general/chevronRight"))
                               (_ `(space :width (,tool-islands-state-width)))))
      (pcase state ('expanded "▾") ('collapsed "▸") (_ " ")))))

(defun tool-islands-chevron-put (overlay string)
  "Make STRING the chevron OVERLAY draws, in the selection's color if selected."
  (overlay-put overlay 'tool-islands-plain string)
  (overlay-put overlay 'before-string
               (if-let* ((face (overlay-get overlay 'tool-islands-selected)))
                   (tool-islands-under-face (copy-sequence string) face)
                 string)))

(defun tool-islands-draw-chevron (section)
  "Draw SECTION's chevron again, after it was folded or unfolded."
  (when-let* ((overlay (seq-find (lambda (overlay) (overlay-get overlay 'tool-islands-chevron))
                                 (overlays-at (oref section start)))))
    (tool-islands-chevron-put overlay (tool-islands-chevron section))))

(defun tool-islands-draw-chevrons (&optional section)
  "Draw the chevrons of SECTION, the root by default, and its descendants."
  (let ((section (or section magit-root-section)))
    (when section
      (unless (eq section magit-root-section)
        (tool-islands-draw-chevron section))
      (mapc #'tool-islands-draw-chevrons (oref section children)))))

(defun tool-islands-row (depth &rest strings)
  "Insert a row DEPTH levels deep made of STRINGS.
The chevron is drawn at its start; see `tool-islands-draw-chevron'."
  (let ((start (point)))
    (insert (apply #'concat strings) "\n")
    (add-text-properties start (point) `(line-prefix ,(tool-islands-row-prefix depth)
                                                     tool-islands-depth ,depth))
    (let ((overlay (make-overlay start (1+ start))))
      (overlay-put overlay 'tool-islands-chevron t)
      (overlay-put overlay 'evaporate t))))

(defun tool-islands-gap ()
  "Return the gap between an icon and its name."
  (tool-islands-space tool-islands-icon-gap))

;;;; Tool window headers

(defun tool-islands-header-line (format)
  "Return header FORMAT as `tool-islands-header-function' shows it."
  (let ((header (copy-sequence format))
        (border (face-attribute 'tool-islands-header :box nil t)))
    ;; Keep one continuous border across text, buttons and stretch spaces.
    (unless (eq border 'unspecified)
      (add-face-text-property 0 (length header) `(:box ,border) nil header))
    (funcall tool-islands-header-function header)))

(defun tool-islands-toolbar (buttons)
  "Return a toolbar of BUTTONS, each (ICON ACTION HELP)."
  (let ((pad (tool-islands-space tool-islands-toolbar-padding)))
    (concat (mapconcat (pcase-lambda (`(,icon ,action ,help))
                         (tool-islands-header-button
                          action help pad
                          (expui-icons-icon icon :face 'tool-islands-neutral-icon) pad))
                       buttons "")
            (tool-islands-space tool-islands-toolbar-margin))))

;;;; Lists

;; Every tool window's list shares one look: rows of the
;; same height in the interface font, the selected row a rounded pill in
;; the selection color (fainter while another window is selected), and
;; names too wide for the window shortened at their end.

(defvar-local tool-islands-view nil "Non-nil in a tool window's list.")
(defvar-local tool-islands-hl nil "Overlays drawing the selected rows.")
(defvar-local tool-islands-hl-chevron nil "Chevron overlays drawn as selected.")
(defvar-local tool-islands-selected-rows-function nil
  "Function returning the starts of the selected rows, as a list.
Nil selects the row at point alone; a list may select several.")

(defvar tool-islands-view-mouse-map
  (let ((map (make-sparse-keymap)))
    ;; A press selects its row; no drag selects a region of text.
    (define-key map [down-mouse-1] #'tool-islands-mouse-select)
    (define-key map [drag-mouse-1] #'ignore)
    (define-key map [mouse-1] #'ignore)
    map)
  "Mouse keys every list shares, under its own.")

(defun tool-islands-mouse-select (event)
  "Move point to the row clicked at EVENT, selecting it."
  (interactive "e")
  (mouse-set-point event)
  (deactivate-mark))

(defun tool-islands-card-color ()
  "Return the background the tool windows are drawn on."
  (or (and tool-islands-background-function (funcall tool-islands-background-function))
      (tool-islands-face-color 'default :background "#FFFFFF")))

(defun tool-islands-view-setup (&optional wrap)
  "Set up the current buffer as a tool window's list.
WRAP non-nil wraps long lines at word boundaries instead of fitting them."
  (setq-local tool-islands-view t
              cursor-type nil
              tab-line-exclude t
              truncate-lines (not wrap)
              ;; Narrow side windows would otherwise truncate regardless.
              truncate-partial-width-windows (not wrap)
              word-wrap wrap
              ;; The selected row reaches the edge; that is no truncation.
              fringe-indicator-alist (cons '(truncation nil nil) fringe-indicator-alist)
              wrap-prefix (and wrap (tool-islands-space tool-islands-row-inset))
              ;; A cut line ends in a plain ellipsis, never a boxed glyph.
              buffer-display-table
              (let ((table (make-display-table)))
                (set-display-table-slot table 'truncation (make-glyph-code ?… 'tool-islands-dim))
                table))
  ;; A selected row's end lies past the window's edge: never scroll to it.
  (setq-local auto-hscroll-mode nil)
  (use-local-map (make-composed-keymap (current-local-map) tool-islands-view-mouse-map))
  (face-remap-add-relative 'default 'tool-islands-text)
  (tool-islands-header-style t)
  (add-hook 'post-command-hook #'tool-islands-highlight nil t)
  (add-hook 'window-selection-change-functions #'tool-islands-highlight nil t)
  (add-hook 'window-size-change-functions #'tool-islands-fit-rows nil t)
  (add-hook 'window-buffer-change-functions #'tool-islands-fit-rows nil t))

(defun tool-islands-highlight (&rest _)
  "Draw the selected rows as pills, as JetBrains' New UI does.
Pills fade while another window is selected; a blank row has none.
Window change hooks may run it in another buffer the window now shows."
  (when tool-islands-view (tool-islands-highlight-1)))

(defun tool-islands-highlight-1 ()
  "Draw the selected rows; see `tool-islands-highlight'."
  (let* ((window (get-buffer-window (current-buffer)))
         (face (if (and window (eq window (selected-window)))
                   'tool-islands-hl-line 'tool-islands-hl-line-inactive))
         (rows (if tool-islands-selected-rows-function
                   (funcall tool-islands-selected-rows-function)
                 (list (pos-bol)))))
    (dolist (chevron tool-islands-hl-chevron)
      (when (overlay-buffer chevron)
        (overlay-put chevron 'tool-islands-selected nil)
        (tool-islands-chevron-put chevron (overlay-get chevron 'tool-islands-plain))))
    (setq tool-islands-hl-chevron nil)
    (mapc #'delete-overlay tool-islands-hl)
    (setq tool-islands-hl nil)
    (dolist (start rows)
      (let ((end (save-excursion (goto-char start) (pos-eol))))
        (unless (= start end)
          (let ((overlay (make-overlay start end nil t)))
            (overlay-put overlay 'priority 100)
            (overlay-put overlay 'face face)
            (overlay-put overlay 'line-prefix
                         (tool-islands-row-prefix (or (get-text-property start 'tool-islands-depth) 0)
                                                 face))
            (overlay-put overlay 'after-string
                         (tool-islands-row-pill-end (face-background face nil t)
                                               (tool-islands-row-end-inset window)))
            (push overlay tool-islands-hl))
          ;; Overlay strings take no background from the pill: draw it in.
          (when-let* ((chevron (seq-find (lambda (overlay) (overlay-get overlay 'tool-islands-chevron))
                                         (overlays-at start))))
            (overlay-put chevron 'tool-islands-selected face)
            (tool-islands-chevron-put chevron (or (overlay-get chevron 'tool-islands-plain)
                                                 (overlay-get chevron 'before-string)))
            (push chevron tool-islands-hl-chevron)))))))

(defun tool-islands-row-end-inset (window)
  "Return the pixels a selected row stops short of WINDOW's edge.
Without a right fringe a row filling the window would count as cut, with
an ellipsis at its end, so it leaves a column free there."
  (if (and (window-live-p window) (> (or (cadr (window-fringes window)) 0) 0))
      0
    (frame-char-width (window-frame window))))

(defun tool-islands-row-pill-end (color inset)
  "Return the selected row's right end in COLOR, INSET pixels from the edge.
The clear margin around the rounded end is drawn in the card's color: an
overlay string would show the canvas there."
  (let ((radius tool-islands-hl-radius)
        (margin tool-islands-hl-margin))
    (concat (propertize " " 'face `(:background ,color)
                        'display `(space :align-to (- right (,(+ radius margin inset)))))
            (tool-islands-pill-cap 'right radius (tool-islands-row-pixels) color margin
                                     (tool-islands-card-color)))))

(defun tool-islands-row-width (start end)
  "Return the pixel width of the row from START to END, unwrapped.
It counts the row's indentation and disclosure chevron, which are not text."
  (+ tool-islands-row-inset
     (* tool-islands-indent (or (get-text-property start 'tool-islands-depth) 0))
     (if (seq-some (lambda (overlay) (overlay-get overlay 'tool-islands-chevron))
                   (overlays-at start))
         tool-islands-state-width 0)
     (string-pixel-width (buffer-substring start end) (current-buffer))))

(defun tool-islands-fit-margin ()
  "Return the pixels reserved for the selection's right end."
  (+ tool-islands-hl-margin tool-islands-hl-radius 4))

(defun tool-islands-fit-rows (&optional window)
  "Shorten the names that WINDOW is too narrow for, at their end.
Names are the spans marked `tool-islands-fit'; WINDOW defaults to one showing
the current buffer."
  (let ((window (if (windowp window) window (get-buffer-window (current-buffer)))))
    (when (and (window-live-p window) (display-graphic-p (window-frame window)))
      (with-current-buffer (window-buffer window)
        (when tool-islands-view
          (let ((room (- (window-body-width window t) (tool-islands-fit-margin)
                         (tool-islands-row-end-inset window)))
                (inhibit-read-only t))
            ;; The selected row's rounded end reaches the window's edge: measure
            ;; rows without it.
            (mapc #'delete-overlay tool-islands-hl)
            (setq tool-islands-hl nil)
            (with-silent-modifications
              (save-excursion
                (goto-char (point-min))
                (while (not (eobp))
                  (let* ((line-end (pos-eol))
                         (span (text-property-any (point) line-end 'tool-islands-fit t)))
                    (when span
                      (let ((span-end (or (text-property-not-all span line-end 'tool-islands-fit t)
                                          line-end)))
                        (remove-text-properties span span-end '(display nil))
                        (let ((over (- (tool-islands-row-width (point) line-end) room)))
                          (when (> over 0)
                            (let* ((text (buffer-substring span span-end))
                                   (width (- (string-pixel-width text (current-buffer)) over
                                             (string-pixel-width "…" (current-buffer)))))
                              (put-text-property
                               span span-end 'display
                               (concat (truncate-string-pixelwise text (max 0 width)
                                                                  (current-buffer))
                                       (propertize "…" 'face 'tool-islands-dim)))))))))
                  (forward-line 1))))
            (tool-islands-highlight)))))))

(defvar-local tool-islands-refit-function #'tool-islands-fit-rows
  "Function fitting this buffer's rows to its window, given the window.
A side pane resized by `tool-islands-pane-fit' calls it.")

;;;; Side panes

;; A tool window's panes keep their width as a share of the frame's, within
;; limits: splitting side windows loses the widths asked for, and a frame
;; maximized after a pane opens would otherwise give it a share of its own.

(defvar tool-islands-pane--fitting nil "Non-nil while side panes are resized.")

(defun tool-islands-pane-keep (window width)
  "Keep side pane WINDOW as wide as WIDTH, a function returning pixels."
  (when (window-live-p window)
    (set-window-parameter window 'tool-islands-pane-width width)
    (set-window-parameter window 'tool-islands-pane-buffer (window-buffer window))
    (tool-islands-pane-fit (window-frame window))))

(defun tool-islands-pane--width (window)
  "Return the function giving side pane WINDOW's width, or nil.
A side window kept for showing another buffer is no pane any more."
  (and (memq (window-parameter window 'tool-islands-pane-buffer)
             (list nil (window-buffer window)))
       (window-parameter window 'tool-islands-pane-width)))

(defun tool-islands-pane-fit (frame)
  "Give FRAME's side panes their widths, and fit their rows to them.
A resize made here, inside a size change, runs no size hooks again, so
each pane's rows are fitted here too."
  (let ((tool-islands-pane--fitting t)
        ;; PIXELWISE in `window-resize' specifies the delta's units, but
        ;; without this binding Emacs still rounds it to character cells.
        ;; An unreachable target then retries on every size hook, even for
        ;; echo-area changes, resetting the editor's pixel scroll offset.
        (window-resize-pixelwise t)
        (windows (window-list frame 'no-minibuffer))
        (neighbors nil)
        panes)
    ;; Resizing a side pane can also take width from the central log.
    ;; Record its body width before moving either divider.
    (dolist (window windows)
      (when (and (buffer-local-value 'tool-islands-view (window-buffer window))
                 (not (tool-islands-pane--width window)))
        (push (cons window (window-body-width window t)) neighbors)))
    (dolist (window windows)
      (when-let* ((width (tool-islands-pane--width window)))
        (push window panes)
        (let ((delta (- (funcall width) (window-pixel-width window))))
          ;; Even a zero-delta resize applies a new window configuration.
          (unless (zerop delta)
            (ignore-errors (window-resize window delta t t t))))))
    (dolist (entry neighbors)
      (unless (= (cdr entry) (window-body-width (car entry) t))
        (push (car entry) panes)))
    (dolist (window panes)
      (with-current-buffer (window-buffer window)
        (funcall tool-islands-refit-function window)))
    (set-frame-parameter frame 'tool-islands-pane-frame-width (frame-pixel-width frame))))

(defun tool-islands-pane--dragged-p ()
  "Return non-nil when a mouse drag is resizing windows, or has just ended.
`mouse-drag-line' only starts the drag: each motion runs from a transient
map, so `this-command' does not name it, and it marks the drag in
`track-mouse' instead.  Releasing the button clears that, possibly before
the redisplay that runs the size hooks for the last motion."
  (or (eq track-mouse 'dragging)
      (and (consp last-input-event)
           (memq 'drag (event-modifiers last-input-event)))))

(defun tool-islands-pane-follow (frame)
  "Size FRAME's side panes again after its windows changed size.
A pane its divider was dragged for keeps its new share of the frame;
after any other change, such as the frame's width or another window
showing, each pane takes its own width again."
  (unless tool-islands-pane--fitting
    (let ((panes (seq-filter #'tool-islands-pane--width
                             (window-list frame 'no-minibuffer))))
      (if (tool-islands-pane--dragged-p)
          (dolist (window panes)
            (let ((share (/ (float (window-pixel-width window)) (frame-pixel-width frame))))
              (set-window-parameter window 'tool-islands-pane-width
                                    (lambda () (round (* share (frame-pixel-width frame)))))))
        (when (seq-some (lambda (window)
                          (/= (window-pixel-width window)
                              (funcall (tool-islands-pane--width window))))
                        panes)
          (tool-islands-pane-fit frame))))))

(add-hook 'window-size-change-functions #'tool-islands-pane-follow)

(defun tool-islands-wrap (text width)
  "Return TEXT's lines broken at spaces to fit WIDTH pixels, in this buffer's font."
  (mapcan
   (lambda (line)
     (let ((words (split-string line " "))
           (rows nil)
           (row nil))
       (dolist (word words)
         (let ((candidate (if row (concat row " " word) word)))
           (if (and row (> (string-pixel-width candidate (current-buffer)) width))
               (progn (push row rows) (setq row word))
             (setq row candidate))))
       (nreverse (cons (or row "") rows))))
   (split-string text "\n")))

(defvar-local tool-islands-header-cookie nil
  "Remapping giving an editor buffer the tool windows' header, while shown so.")

(defun tool-islands-header-style (enable)
  "Give the current buffer's header the tool windows' look if ENABLE, else undo it.
For editor buffers a diff or merge borrows, until it closes."
  (if enable
      (unless tool-islands-header-cookie
        (setq tool-islands-header-cookie
              (let ((background (and tool-islands-background-function
                                     (funcall tool-islands-background-function))))
                (if background
                    (face-remap-add-relative 'header-line
                                             :inherit 'tool-islands-header :background background)
                  (face-remap-add-relative 'header-line 'tool-islands-header)))))
    (when tool-islands-header-cookie
      (face-remap-remove-relative tool-islands-header-cookie)
      (setq tool-islands-header-cookie nil))))

(defun tool-islands-ui-text (text &optional face)
  "Return TEXT in the interface font, with FACE's colors.
Headers of editor windows otherwise take the buffer's own font."
  (propertize text 'face (if face (list face 'tool-islands-text) 'tool-islands-text)))

(defun tool-islands-fit (string)
  "Mark STRING as a name `tool-islands-fit-rows' may shorten."
  (propertize string 'tool-islands-fit t))

;;;; Buttons

(defcustom tool-islands-button-render-function #'tool-islands-button-text
  "Function rendering a button's LABEL and PRIMARY flag as a string.
Interaction and hover properties are added here.  Use
`tool-islands-button-rounded' for SVG buttons, or provide your own function."
  :type 'function
  :group 'tool-islands)

(defcustom tool-islands-button-radius nil
  "Rounded button radius in pixels, or nil for half the button height."
  :type '(choice (const :tag "Pill" nil) natnum)
  :group 'tool-islands)

(defcustom tool-islands-button-padding 12
  "Horizontal padding in pixels on each side of a rounded button."
  :type 'natnum
  :group 'tool-islands)

(defun tool-islands-button-text (label primary)
  "Return a plain text button for LABEL and PRIMARY."
  (propertize (concat " " label " ")
              'face (if primary 'tool-islands-primary-button 'tool-islands-button)))

(defun tool-islands-button-rounded (label primary)
  "Return a rounded button for LABEL and PRIMARY, with a text fallback."
  (if (expui-icons-svg-p)
      (propertize label 'display (tool-islands-button-image label primary))
    (tool-islands-button-text label primary)))

(defun tool-islands-button-height ()
  "Return the pixel height of a header button, with air above and below."
  (round (* 1.4 (frame-char-height))))

(defvar tool-islands-button-cache (make-hash-table :test #'equal))

(defun tool-islands-button-image (label primary)
  "Return a pill image showing LABEL, in the accent color if PRIMARY.
It is one image: a text's background would fill the header's height."
  (let* ((face (if primary 'tool-islands-primary-button 'tool-islands-button))
         (background (tool-islands-face-color face :background (if primary "#245FA5" "#ECEDEF")))
         (foreground (tool-islands-face-color face :foreground (if primary "#FFFFFF" "#333333")))
         (font (face-font 'tool-islands-text))
         (size (if font (aref (font-info font) 2) 13))
         (family (let ((family (face-attribute 'tool-islands-font :family nil t)))
                   (if (stringp family) family "sans-serif")))
         (height (tool-islands-button-height))
         (radius (min (/ height 2.0) (or tool-islands-button-radius (/ height 2.0))))
         (key (list label background foreground family size height radius tool-islands-button-padding)))
    (or (gethash key tool-islands-button-cache)
        (puthash key
                 (let* ((width (+ (string-pixel-width
                                   (propertize label 'face 'tool-islands-text))
                                  (* 2 tool-islands-button-padding)))
                        (svg (svg-create width height)))
                   (svg-rectangle svg 0 0 width height :rx radius :fill background)
                   (svg-text svg label :x (/ width 2.0) :y (/ height 2.0)
                             :text-anchor "middle" :dominant-baseline "central"
                             :font-family family :font-size size :fill foreground)
                   (svg-image svg :ascent 'center))
                 tool-islands-button-cache))))

(defun tool-islands-button (label action help &optional primary)
  "Return a button LABEL running ACTION, with tooltip HELP.
PRIMARY identifies the default action to the configured renderer."
  (tool-islands-header-button action help
                            (funcall tool-islands-button-render-function label primary)))

(add-hook 'enable-theme-functions (lambda (&rest _) (clrhash tool-islands-button-cache)))

;;;; Folding

(declare-function magit-current-section "magit-section" ())
(declare-function magit-section-toggle "magit-section" (section))
(declare-function magit-section-show-children "magit-section" (section &optional depth))
(declare-function magit-section-hide-children "magit-section" (section))

(defun tool-islands-toggle-section ()
  "Fold or unfold the group or folder at point."
  (interactive)
  (when-let* ((section (magit-current-section)))
    (when (oref section content)
      (magit-section-toggle section)
      (tool-islands-draw-chevron section))))

(defun tool-islands-expand-all ()
  "Unfold every group and folder."
  (interactive)
  (when magit-root-section
    (magit-section-show-children magit-root-section 99)
    (tool-islands-draw-chevrons)))

(defun tool-islands-collapse-all ()
  "Fold every folder, leaving the top-level groups open."
  (interactive)
  (when magit-root-section
    (dolist (group (oref magit-root-section children))
      (magit-section-hide-children group))
    (tool-islands-draw-chevrons)))

;;;; Trees

;; A node is (NAME DIRS ITEMS): DIRS an alist of name to node, ITEMS the
;; items directly inside.  A folder holding only one folder is drawn as
;; one row, "a/b", as IntelliJ does.

(defun tool-islands-tree-build (items path)
  "Return the folder tree of ITEMS, each at the relative file name PATH returns."
  (let ((root (list "" nil nil)))
    (dolist (item items)
      (let ((node root)
            (parts (split-string (funcall path item) "/")))
        (dolist (part (butlast parts))
          (let ((child (assoc part (nth 1 node))))
            (unless child
              (setq child (list part nil nil))
              (setf (nth 1 node) (append (nth 1 node) (list child))))
            (setq node child)))
        (setf (nth 2 node) (append (nth 2 node) (list item)))))
    (tool-islands-tree-compact root path)))

(defun tool-islands-tree-compact (node path)
  "Merge NODE's folders that hold a single folder and nothing else.
Sort folders by name, and items by the base name of their PATH."
  (setf (nth 1 node)
        (mapcar (lambda (child)
                  (while (and (null (nth 2 child)) (= (length (nth 1 child)) 1))
                    (let ((only (car (nth 1 child))))
                      (setq child (list (concat (car child) "/" (car only))
                                        (nth 1 only) (nth 2 only)))))
                  (tool-islands-tree-compact child path))
                (sort (nth 1 node) (lambda (a b) (string< (car a) (car b))))))
  (setf (nth 2 node)
        (sort (nth 2 node)
              (lambda (a b) (string< (file-name-nondirectory (funcall path a))
                                     (file-name-nondirectory (funcall path b))))))
  node)

(defun tool-islands-tree-items (node)
  "Return every item in NODE and below."
  (append (nth 2 node) (mapcan #'tool-islands-tree-items (nth 1 node))))

(provide 'tool-islands)
;;; tool-islands.el ends here
