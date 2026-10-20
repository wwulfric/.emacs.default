;;; init-islands.el --- Windows as rounded islands on a canvas -*- lexical-binding: t; -*-

;;; Commentary:
;; As in JetBrains' Islands theme, the frame is a gray canvas holding white
;; cards with rounded corners: the editor area, however it is split, is
;; one card and each side window (the Dirvish sidebar) another.
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
;; For Dirvish's session accessors, which are macros.
(eval-when-compile (require 'dirvish nil t))

(defvar my/islands-mode)
(defvar my/ui-header-ascent)

(defgroup my/islands nil "Windows as rounded islands." :group 'convenience)

(defface my/island-canvas '((t (:background "#ECEEF1")))
  "Canvas around and between the islands." :group 'my/islands)

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
  "Return non-nil when WINDOW is a side window, a card of its own."
  (memq (window-parameter window 'window-side) '(left right)))

(defun my/islands--insets (&optional window)
  "Return WINDOW's canvas fringes, as (LEFT . RIGHT) pixels."
  (if (my/islands--side-p window)
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
         (area (if (my/islands--side-p window) edges
                 (window-pixel-edges (window-main-window frame))))
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
           ;; A top row's rule stops a corner's width short of either end,
           ;; rounded or not, so the rules of all cards line up.
           (end (or image
                    (and top (propertize " " 'face '(:box nil :overline nil :underline nil)
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
  "Put the window's bottom corners around status line FORMAT."
  (my/islands--wrap format 'mode-line))

(defun my/islands--dirvish-bars (dv &rest _)
  "Round the bottom of Dirvish side session DV's status bar."
  (when (and (fboundp 'dv-type) (eq (dv-type dv) 'side))
    (setf (dv-mode-line dv)
          `((:eval (my/islands--corner 'mode-line nil))
            ,(dv-mode-line dv)
            (:eval (my/islands--corner 'mode-line t))))))

(defvar-local my/islands--fringe-cookie nil
  "Face remapping that paints this side window buffer's fringes on the canvas.")

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
          (if my/islands-mode
              (let* ((gap (max 1 (1- my/islands-gap)))
                     (fringes (if (eq (car side) 'left) (list 0 gap) (list gap 0))))
                (unless my/islands--fringe-cookie
                  (setq my/islands--fringe-cookie
                        (face-remap-add-relative 'fringe :background (my/islands--canvas))))
                (unless (equal (seq-take (window-fringes window) 2) fringes)
                  (set-window-fringes window (car fringes) (cadr fringes))))
            (when my/islands--fringe-cookie
              (face-remap-remove-relative my/islands--fringe-cookie)
              (setq my/islands--fringe-cookie nil)
              ;; Dirvish's sidebar sets its own; the Dired one uses the frame's.
              (when (derived-mode-p 'dired-mode)
                (if (boundp 'dirvish-window-fringe)
                    (set-window-fringes window (1+ dirvish-window-fringe) 1)
                  (set-window-fringes window nil nil))))))))))

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
              window-divider-default-bottom-width 1)
        (window-divider-mode 1)
        (my/islands--record-card)
        (my/islands--set-faces t)
        (my/islands--set-surface t)
        (add-hook 'after-change-major-mode-hook #'my/islands--surface-buffer)
        (add-hook 'minibuffer-setup-hook #'my/islands--canvas-fringe -90)
        (add-hook 'minibuffer-inactive-mode-hook #'my/islands--canvas-fringe)
        (advice-add 'tab-line-format :filter-return #'my/islands--tab-line)
        (advice-add 'my/ui-status-line :filter-return #'my/islands--status)
        (with-eval-after-load 'init-dirvish
          (when my/islands-mode
            (advice-add 'my/dirvish-side-header :filter-return #'my/islands--header)
            (advice-add 'my/dirvish-side-bars :after #'my/islands--dirvish-bars)))
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
    (advice-remove 'my/dirvish-side-header #'my/islands--header)
    (advice-remove 'my/dirvish-side-bars #'my/islands--dirvish-bars)
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
