;;; init-islands.el --- Windows as rounded islands on a canvas -*- lexical-binding: t; -*-

;;; Commentary:
;; As in JetBrains' Islands theme, the frame is a gray canvas holding white
;; cards with rounded corners: the editor area, however it is split, is
;; one card and the side windows along each edge another: the sidebar, or
;; the Commit tool window over its message, on the left, and a tool window
;; along the bottom, whose panes share one card split by fine lines.
;; The canvas is the frame's own background, so the transparent macOS
;; title bar above the cards and the echo area below them show it; the
;; cards reach the frame's left and right edges, which have no tool strips
;; as in JetBrains, and round only the corners where they meet each other; buffers in windows remap their background back to the card
;; color, each with its own remapping.  Child frames (popups) keep the theme's background.  Window dividers are one pixel wide for every window, so a
;; side window paints its own fringe on the canvas to widen the gap to the
;; editor, while editor splits are only a fine canvas-colored line.
;; The outer corners are images in a window's top row (tab line or header
;; line) and its mode line, whose cut-off part shows the canvas.  A window
;; without those rows keeps square corners.

;;; Code:

(require 'ui-layout)
(require 'face-remap)
(require 'seq)

(defvar my/islands-mode)
(defvar my/ui-header-ascent)

(defgroup my/islands nil "Windows as rounded islands." :group 'convenience)

(defface my/island-canvas '((t (:background "#ECEEF1")))
  "Canvas around and between the islands." :group 'my/islands)

(defface my/island-rule '((t (:foreground "#E4E7EB")))
  "Lines between windows stacked within one card." :group 'my/islands)

(defvar my/islands-gap 4 "Pixels between the cards.")
(defvar my/islands-radius 6 "Radius of the islands' corners, in pixels.")

(defvar my/islands--saved nil
  "Settings replaced by `my/islands-mode', restored when it is turned off.")

(defvar my/islands--surface nil
  "Attributes giving a buffer the card color, as a `default' base remapping.")

(defun my/islands--canvas ()
  "Return the canvas color."
  (face-background 'my/island-canvas nil t))

(defvar my/islands--card-color nil
  "The theme's background, recorded before frames take the canvas color.")

(defun my/islands--record-card ()
  "Record the theme's background as the card color, unless it is the canvas."
  (let ((color (face-background 'default nil t)))
    (unless (equal color (my/islands--canvas))
      (setq my/islands--card-color color))))

(defun my/islands--card ()
  "Return the card color: the theme's background, before the canvas."
  (or my/islands--card-color (face-background 'default nil t)))

(defun my/islands--canvas-buffer-p (buffer)
  "Return non-nil when BUFFER shows on the canvas: the echo area or minibuffer."
  (or (minibufferp buffer)
      (string-prefix-p " *Echo Area" (buffer-name buffer))))

(defun my/islands--surface-p ()
  "Return non-nil when the current buffer's background is the card color."
  (equal (car (last (assq 'default face-remapping-alist))) my/islands--surface))

(defun my/islands--surface-buffer (&optional buffer)
  "Give BUFFER, the current one by default, the card color.
It is the base of the buffer's own `default' remapping, under any relative
ones such as a prose font, and never shared: remapping functions modify
entries in place.  Buffers that replace their remappings from scratch, or
change major mode, get it again."
  (with-current-buffer (or buffer (current-buffer))
    (when (and my/islands--surface
               (not (my/islands--canvas-buffer-p (current-buffer)))
               (not (my/islands--surface-p)))
      (face-remap-set-base 'default (copy-sequence my/islands--surface)))))

(defvar-local my/islands--canvas-fringe nil
  "Remapping that draws this echo area or minibuffer's fringes like its frame.")

(defun my/islands--canvas-fringe (&optional buffer)
  "Draw the fringes of BUFFER, the echo area or a minibuffer, like its frame.
The theme's fringes are white; in the editor frame these windows sit on the
canvas, while the minibuffer panel's own frame stays white."
  (with-current-buffer (or buffer (current-buffer))
    (when (and my/islands-mode (not my/islands--canvas-fringe))
      (setq my/islands--canvas-fringe (face-remap-add-relative 'fringe 'default)))))

(defun my/islands--set-surface (enable)
  "Give displayed buffers the card color when ENABLE, else remove it."
  (when my/islands--surface
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (when (my/islands--surface-p)
          (face-remap-reset-base 'default)))))
  (setq my/islands--surface (and enable (list :background (my/islands--card))))
  (dolist (buffer (buffer-list))
    (when (my/islands--canvas-buffer-p buffer)
      (with-current-buffer buffer
        (when my/islands--canvas-fringe
          (face-remap-remove-relative my/islands--canvas-fringe)
          (setq my/islands--canvas-fringe nil)))))
  (when enable
    (dolist (name '(" *Echo Area 0*" " *Echo Area 1*" " *Minibuf-0*"))
      (my/islands--canvas-fringe (get-buffer-create name)))
    (dolist (frame (frame-list))
      (dolist (window (window-list frame 'no-minibuffer))
        (my/islands--surface-buffer (window-buffer window))))))

(defun my/islands--side-p (&optional window)
  "Return non-nil when WINDOW is a side window, part of its side's card."
  (memq (window-parameter window 'window-side) '(left right bottom)))

(defun my/islands--card-edges (&optional window)
  "Return the pixel edges of the card WINDOW is part of.
The side windows along one edge make one card; the editor area is another."
  (let ((window (window-normalize-window window))
        (side (window-parameter window 'window-side)))
    (if (memq side '(left right bottom))
        (let ((edges (seq-map #'window-pixel-edges
                              (seq-filter (lambda (other)
                                            (eq (window-parameter other 'window-side) side))
                                          (window-list (window-frame window) 'no-minibuffer)))))
          (list (apply #'min (mapcar #'car edges)) (apply #'min (mapcar #'cadr edges))
                (apply #'max (mapcar #'caddr edges)) (apply #'max (mapcar #'cadddr edges))))
      (window-pixel-edges (window-main-window (window-frame window))))))

(defun my/islands--insets (&optional window)
  "Return WINDOW's canvas fringes, as (LEFT . RIGHT) pixels.
A bottom card's panes keep white fringes: no canvas there."
  (if (and (my/islands--side-p window)
           (not (eq (window-parameter window 'window-side) 'bottom)))
      (pcase-let ((`(,left ,right) (window-fringes window)))
        (cons left right))
    '(0 . 0)))

(defun my/islands--line-end-inset ()
  "Return the pixels at the right end of a line taken by its corner."
  (+ my/islands-radius (cdr (my/islands--insets))))

(defun my/islands--outer-p (top right &optional window)
  "Return non-nil when WINDOW's TOP or bottom, RIGHT or left corner is rounded.
That is a corner of its card, the editor area or a side window, which faces
another card rather than the frame's left or right edge."
  (let* ((frame (window-frame window))
         (edges (window-pixel-edges window))
         (area (my/islands--card-edges window))
         (side (if right 2 0)))
    (and (= (nth (if top 1 3) edges) (nth (if top 1 3) area))
         (= (nth side edges) (nth side area))
         (/= (nth side edges) (nth side (window-pixel-edges (frame-root-window frame)))))))

(defun my/islands--canvas-space (width &optional size)
  "Return a space WIDTH pixels wide in the canvas color.
SIZE, a list such as (:height (6) :ascent 75), sets its height."
  (when (> width 0)
    (propertize " " 'face `(:background ,(my/islands--canvas)
                            :box nil :overline nil :underline nil)
                'display `(space :width (,width) ,@size))))

(defun my/islands--corner (row right)
  "Return the left end, or with RIGHT the right end, of ROW.
ROW is `tab-line', `header-line' or `mode-line' of the window being drawn;
the mode line holds the bottom corners.  An end is a corner image where
the window's corner is an outer one; elsewhere a top row keeps the
corner's width blank, and a mode line nothing."
  (when (display-graphic-p)
    (let* ((top (not (eq row 'mode-line)))
           ;; A mode line of a fixed height holds no text to set it, so
           ;; the spaces here must not make it as tall as their font.
           (fixed (and (not top) my/ui-mode-line-pixels))
           (size (and fixed `(:height (,fixed) :ascent 75)))
           (height (pcase row
                     ('tab-line (window-tab-line-height))
                     ('header-line (window-header-line-height))
                     (_ (or fixed (window-mode-line-height)))))
           (insets (my/islands--insets))
           (inset (if right (cdr insets) (car insets)))
           (image (and (> height 0) (my/islands--outer-p top right)
                       ;; These rows take their height from a spacer with
                       ;; this ascent (`my/ui-header-space',
                       ;; `my/ui-mode-line-space').
                       (my/ui-corner (intern (format "%s-%s"
                                                     (if top "top" "bottom")
                                                     (if right "right" "left")))
                                     my/islands-radius height
                                     (my/islands--card)
                                     (my/islands--canvas) nil
                                     (if top my/ui-header-ascent 75))))
           ;; A top row's rule stops a corner's width short of either end
           ;; of its card, rounded or not, so the rules of all cards line up;
           ;; between panes of one card it runs on to their dividing line.
           (internal (/= (nth (if right 2 0) (window-pixel-edges))
                         (nth (if right 2 0) (my/islands--card-edges))))
           (end (or image
                    (and top (not internal)
                         (propertize " " 'face '(:box nil :overline nil :underline nil)
                                     'display `(space :width (,my/islands-radius)))))))
      (if right
          (concat (propertize " " 'display
                              `(space :align-to (- (+ right right-fringe right-margin)
                                                   (,(+ inset (if end my/islands-radius 0))))
                                     ,@size)
                              ;; Without text, the line's rules go too.
                              'face (and fixed '(:box nil :overline nil :underline nil)))
                  end (my/islands--canvas-space inset size))
        (concat (my/islands--canvas-space inset size) end)))))

(defun my/islands--wrap (format row)
  "Return mode-line construct FORMAT between the corners of ROW."
  (list (my/islands--corner row nil) format (my/islands--corner row t)))

(defun my/islands--tab-line (format)
  "Put the window's top corners around tab line FORMAT."
  (my/islands--wrap format 'tab-line))

(defun my/islands--header (format)
  "Put the window's top corners around header line FORMAT."
  (my/islands--wrap format 'header-line))

(defun my/islands--status (format)
  "Put the window's bottom corners around status line FORMAT.
With a window below it in its card, the row draws their rule instead."
  (my/islands--wrap (if (my/islands--stacked-above-p) (my/islands--rule-edge) format)
                    'mode-line))

(defun my/islands--stacked-above-p (&optional window)
  "Return non-nil when another window of WINDOW's card lies below it."
  (and (display-graphic-p)
       my/ui-mode-line-pixels
       (/= (nth 3 (window-pixel-edges window))
           (nth 3 (my/islands--card-edges window)))))

(defun my/islands--rule-edge ()
  "Return a mode line drawing the rule to the window below it.
Windows stack with no divider, whose ends could not stop short of the
card's edges; this rule stops a corner's width short, as a top row's does."
  (concat (my/islands--space my/islands-radius my/ui-mode-line-pixels)
          (propertize " " 'face `(:overline ,(face-foreground 'my/island-rule nil t)
                                  :underline nil :box nil)
                      'display `(space :align-to ,(my/ui-line-end)
                                       :height (,my/ui-mode-line-pixels)
                                       :ascent 75))))

(defun my/islands--space (width height)
  "Return a blank WIDTH pixels wide and HEIGHT high, without the row's rules."
  (propertize " " 'face '(:overline nil :underline nil :box nil)
              'display `(space :width (,width) :height (,height) :ascent 75)))

(defvar-local my/islands--fringe-cookie nil
  "Face remapping that paints this side window buffer's fringes on the canvas.")

(defvar-local my/islands--rule-cookie nil
  "Face remapping that lets a stacked side window's rule row be one pixel high.")

(defvar-local my/islands--gap-cookie nil
  "Face remapping that lets a bottom card's gap row be as short as the gap.
A row is at least as tall as its face's font.")

(defun my/islands--apply-windows (frame)
  "Give FRAME's side windows a canvas fringe toward the editor, or remove it.
With the one-pixel divider it makes the gap between the cards.  The fringe
at the frame's edge goes, so the card stays white up to it."
  (when (and (display-graphic-p frame) (not (frame-parent frame)))
    (dolist (window (window-list frame 'no-minibuffer))
      (when my/islands-mode
        (my/islands--surface-buffer (window-buffer window)))
      (when-let* ((side (my/islands--side-p window)))
        (with-current-buffer (window-buffer window)
          (cond
           ((and my/islands-mode (eq (car side) 'bottom))
            ;; The gap above is a canvas strip in the window's top row; the
            ;; card's panes keep a white pixel of right fringe each, so a row
            ;; filling a pane is not cut and the panes meet at a fine line.
            (unless (window-parameter window 'tab-line-format)
              (set-window-parameter window 'tab-line-format '(:eval (my/islands--gap-row))))
            (unless my/islands--gap-cookie
              (setq my/islands--gap-cookie
                    (face-remap-add-relative 'tab-line :height 10 :box nil
                                             :background (my/islands--canvas))))
            (unless (equal (seq-take (window-fringes window) 2) '(0 1))
              (set-window-fringes window 0 1)))
           (my/islands-mode
            (let* ((gap (max 1 (1- my/islands-gap)))
                   (fringes (if (eq (car side) 'left) (list 0 gap) (list gap 0))))
              (unless my/islands--fringe-cookie
                (setq my/islands--fringe-cookie
                      (face-remap-add-relative 'fringe :background (my/islands--canvas))))
              (unless (equal (seq-take (window-fringes window) 2) fringes)
                (set-window-fringes window (car fringes) (cadr fringes))))
            ;; Below another window of the card, a rule stands in for the
            ;; divider; the row above the header draws it, so that the
            ;; header's images do not break it.
            (if (/= (nth 1 (window-pixel-edges window))
                    (nth 1 (my/islands--card-edges window)))
                (progn
                  (unless (window-parameter window 'tab-line-format)
                    (set-window-parameter window 'tab-line-format
                                          '(:eval (my/islands--rule-row))))
                  (unless my/islands--rule-cookie
                    (setq my/islands--rule-cookie
                          (face-remap-add-relative 'tab-line :height 10 :box nil
                                                   :underline nil
                                                   :background (my/islands--card)))))
              (when (window-parameter window 'tab-line-format)
                (set-window-parameter window 'tab-line-format nil))
              (when my/islands--rule-cookie
                (face-remap-remove-relative my/islands--rule-cookie)
                (setq my/islands--rule-cookie nil))))
           (t
            (when my/islands--rule-cookie
              (face-remap-remove-relative my/islands--rule-cookie)
              (setq my/islands--rule-cookie nil))
            (when my/islands--fringe-cookie
              (face-remap-remove-relative my/islands--fringe-cookie)
              (setq my/islands--fringe-cookie nil)
              ;; The sidebar uses the frame's fringes again.
              (when (derived-mode-p 'dired-mode)
                (set-window-fringes window nil nil)))
            (when (window-parameter window 'tab-line-format)
              (set-window-parameter window 'tab-line-format nil))
            (when my/islands--gap-cookie
              (face-remap-remove-relative my/islands--gap-cookie)
              (setq my/islands--gap-cookie nil)))))))))

(defun my/islands--gap-row ()
  "Return the canvas strip above a bottom card: its gap to the editor.
Windows have no divider below them, so it is the whole gap."
  (propertize " " 'face `(:background ,(my/islands--canvas) :box nil
                          :overline nil :underline nil :height 1)
              'display `(space :align-to right :height (,my/islands-gap))))

(defconst my/islands--rule-row-pixels 3
  "Height of the rule row above a stacked side window.
It is the shortest row its font allows, which leaves the canvas end full.")

(defun my/islands--rule-row ()
  "Return the short row above a side window stacked below another.
Its rule, along the row's top, stops a corner's width short of either
end of the card."
  (let* ((end (+ (cdr (my/islands--insets)) my/islands-radius))
         (height `(:height (,my/islands--rule-row-pixels)))
         (plain '(:box nil :overline nil :underline nil :height 1)))
    (concat (propertize " " 'face plain
                        'display `(space :width (,my/islands-radius) ,@height))
            (propertize " " 'face `(,@plain :overline ,(face-foreground 'my/island-rule nil t))
                        'display `(space :align-to (- (+ right right-fringe right-margin) (,end))
                                         ,@height))
            (propertize " " 'face plain
                        'display `(space :width (,my/islands-radius) ,@height))
            (propertize " " 'face `(:background ,(my/islands--canvas) ,@plain)
                        'display `(space :align-to (+ right right-fringe right-margin) ,@height)))))

;; A divider is one pixel wide, too narrow to press reliably: the pixels
;; beside it drag it as well.

(defconst my/islands-edge-grip 6
  "Pixels on either side of a vertical divider that also drag it.
As wide as the empty margin beside the tool windows' rows.")

(defconst my/islands-edge-grip-fringe 4
  "Pixels of a left fringe that drag the divider beside it.
The change markers, which take clicks, start right after them.")

(defun my/islands--edge-window (event)
  "Return the window whose right edge mouse EVENT pressed beside, or nil."
  (when (eq (car-safe event) 'down-mouse-1)
    (let ((window (posn-window (event-start event)))
          (mouse (mouse-pixel-position)))
      (when (and (windowp window) (not (window-minibuffer-p window))
                 (eq (car mouse) (window-frame window))
                 (cadr mouse) (cddr mouse))
        (let* ((x (cadr mouse))
               (edges (window-pixel-edges window))
               (left (nth 0 edges))
               (right (- (nth 2 edges) (window-right-divider-width window))))
          (cond
           ((and (> left 0)
                 (< (- x left) (if (> (car (window-fringes window)) 0)
                                   my/islands-edge-grip-fringe
                                 my/islands-edge-grip)))
            (window-at-x-y (- left 1) (cddr mouse)))
           ((and (>= x (- right my/islands-edge-grip))
                 (not (window-at-side-p window 'right)))
            window)))))))

(defun my/islands-drag-edge (event)
  "Drag the divider beside the press of mouse EVENT, until its release."
  (interactive "e")
  (when-let* ((window (my/islands--edge-window event)))
    (let ((last-x (car (mouse-absolute-pixel-position)))
          (window-resize-pixelwise t)
          ;; As `mouse-drag-line' marks its drags.
          (track-mouse 'dragging)
          done)
      (while (not done)
        (let ((next (read-event)))
          (cond
           ((mouse-movement-p next)
            (let* ((x (car (mouse-absolute-pixel-position)))
                   (delta (- x last-x)))
              (unless (zerop delta)
                (ignore-errors (adjust-window-trailing-edge window delta t t))
                (setq last-x x)
                (redisplay t))))
           ((memq (car-safe next) '(switch-frame select-window)))
           ((and (mouse-event-p next) (eq (event-basic-type next) 'mouse-1))
            (setq done t))
           (t (push next unread-command-events)
              (setq done t))))))))

(defvar my/islands--edge-map
  (let ((map (make-sparse-keymap))
        (item `(menu-item "" my/islands-drag-edge
                          :filter ,(lambda (command)
                                     (and (my/islands--edge-window last-input-event)
                                          command)))))
    (define-key map [down-mouse-1] item)
    (define-key map [left-fringe down-mouse-1] item)
    (define-key map [right-fringe down-mouse-1] item)
    map)
  "Keymap claiming presses beside a divider, ahead of the buffers' own.")

(add-to-list 'emulation-mode-map-alists
             `((my/islands-mode . ,my/islands--edge-map)))

(defun my/islands--apply-frame (frame)
  "Give top-level FRAME the canvas background and title bar, or remove them."
  ;; The initial frame takes `default-frame-alist' again after init.
  (setf (alist-get 'ns-transparent-titlebar default-frame-alist)
        (and my/islands-mode t))
  (when (and (display-graphic-p frame) (not (frame-parent frame)))
    ;; The title bar shows the frame's background: the canvas.
    (set-frame-parameter frame 'ns-transparent-titlebar (and my/islands-mode t))
    (set-face-background 'default
                         (if my/islands-mode (my/islands--canvas) (my/islands--card))
                         frame)))

(defun my/islands--set-faces (enable)
  "Paint the gaps in the canvas color when ENABLE, else restore the theme's."
  (dolist (face '(window-divider window-divider-first-pixel
                  window-divider-last-pixel))
    (set-face-attribute face nil :foreground
                        (if enable (my/islands--canvas) 'unspecified)))
  (unless enable
    ;; The theme's own colors come back once the overrides are gone.
    (enable-theme (car custom-enabled-themes))))

(defun my/islands--reapply-faces (&rest _)
  "Paint the canvas again after a theme is enabled over it."
  (when my/islands-mode
    (my/islands--record-card)
    (my/islands--set-faces t)
    (my/islands--set-surface t)
    (mapc #'my/islands--apply-frame (frame-list))))

(define-minor-mode my/islands-mode
  "Draw windows as rounded islands on a gray canvas."
  :global t :group 'my/islands
  (if my/islands-mode
      (progn
        (unless my/islands--saved
          (setq my/islands--saved
                (list window-divider-default-places
                      window-divider-default-right-width
                      window-divider-default-bottom-width)))
        (setq my/ui-line-end-inset #'my/islands--line-end-inset
              window-divider-default-places t
              window-divider-default-right-width 1
              ;; Stacked windows draw their own rule, which can stop short of
              ;; a card's edges; gaps below a card are its neighbor's strip.
              window-divider-default-bottom-width 0)
        (window-divider-mode 1)
        (my/islands--record-card)
        (my/islands--set-faces t)
        (my/islands--set-surface t)
        (add-hook 'after-change-major-mode-hook #'my/islands--surface-buffer)
        (add-hook 'minibuffer-setup-hook #'my/islands--canvas-fringe -90)
        (add-hook 'minibuffer-inactive-mode-hook #'my/islands--canvas-fringe)
        (advice-add 'tab-line-format :filter-return #'my/islands--tab-line)
        (advice-add 'my/ui-status-line :filter-return #'my/islands--status)
        (with-eval-after-load 'init-sidebar
          (when my/islands-mode
            (advice-add 'my/sidebar-header :filter-return #'my/islands--header)
            (advice-add 'my/sidebar-status-line :filter-return #'my/islands--status)))
        (add-hook 'window-state-change-functions #'my/islands--apply-windows)
        (add-hook 'enable-theme-functions #'my/islands--reapply-faces)
        (add-hook 'after-make-frame-functions #'my/islands--apply-frame 90))
    (when my/islands--saved
      (pcase-setq `(,window-divider-default-places
                    ,window-divider-default-right-width
                    ,window-divider-default-bottom-width)
                  my/islands--saved)
      (setq my/islands--saved nil)
      (window-divider-mode 1))
    (setq my/ui-line-end-inset 0)
    (my/islands--set-faces nil)
    (my/islands--set-surface nil)
    (remove-hook 'after-change-major-mode-hook #'my/islands--surface-buffer)
    (remove-hook 'minibuffer-setup-hook #'my/islands--canvas-fringe)
    (remove-hook 'minibuffer-inactive-mode-hook #'my/islands--canvas-fringe)
    (advice-remove 'tab-line-format #'my/islands--tab-line)
    (advice-remove 'my/ui-status-line #'my/islands--status)
    (advice-remove 'my/sidebar-header #'my/islands--header)
    (advice-remove 'my/sidebar-status-line #'my/islands--status)
    (remove-hook 'window-state-change-functions #'my/islands--apply-windows)
    (remove-hook 'enable-theme-functions #'my/islands--reapply-faces)
    (remove-hook 'after-make-frame-functions #'my/islands--apply-frame))
  (mapc #'my/islands--apply-frame (frame-list))
  (mapc #'my/islands--apply-windows (frame-list))
  (my/ui--forget-glyph-scales)
  (force-mode-line-update t))

(provide 'init-islands)
;;; init-islands.el ends here
