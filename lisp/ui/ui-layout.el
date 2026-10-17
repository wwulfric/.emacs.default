;;; ui-layout.el --- Pixel spacing and alignment for interface text -*- lexical-binding: t; -*-

;;; Commentary:
;; Interface text uses proportional fonts, smaller heights and CJK glyphs,
;; which column counts get wrong.  These helpers build `display' spaces
;; measured in pixels, shorten text by its displayed width, and keep glyphs
;; from fallback fonts (emoji, symbols) from making a row taller than the
;; others.  Components own what they lay out; this file only measures.

;;; Code:

(require 'seq)

(defvar my/ui-line-end-inset 0
  "Pixels kept free at the right end of header and mode lines.
A number, or a function returning one for the window being drawn.
Rounded window corners (init-islands.el) are drawn there.")

(defun my/ui-line-end-inset ()
  "Return the pixels kept free at the right end of this window's lines."
  (if (functionp my/ui-line-end-inset)
      (funcall my/ui-line-end-inset)
    my/ui-line-end-inset))

(defun my/ui-line-end ()
  "Return the `:align-to' position where header and mode line text ends."
  `(- (+ right right-fringe right-margin) (,(my/ui-line-end-inset))))

(defun my/ui-space (width)
  "Return a space WIDTH pixels wide."
  (propertize " " 'display `(space :width (,(max 0 width)))))

(defun my/ui-space-to (x)
  "Return a space reaching X pixels from the start of the text area."
  (propertize " " 'display `(space :align-to (,x))))

(defun my/ui-right-space (text &optional edge buffer)
  "Return a space that ends where TEXT, following it, meets EDGE.
EDGE is an `:align-to' position, `right' by default.  TEXT is measured
with BUFFER's face remapping, as `string-pixel-width' does."
  (propertize " " 'display
              `(space :align-to (- ,(or edge 'right)
                                   (,(string-pixel-width text buffer))))))

(defun my/ui-at-right (text &optional edge buffer)
  "Return TEXT preceded by the space that aligns it to EDGE.
EDGE and BUFFER are as in `my/ui-right-space'."
  (concat (my/ui-right-space text edge buffer) text))

(defun my/ui-fit-left (text width)
  "Return TEXT shortened from the left to WIDTH columns, keeping its end.
The end of a path or place names the file, so it is the part to keep."
  (let ((columns (string-width text)))
    (if (<= columns width)
        text
      (concat "…" (truncate-string-to-width
                   text columns (- columns (max 0 (1- width))))))))

;;;; Tall glyphs

;; A glyph from a fallback font whose ascent or descent exceeds the text
;; font's makes its whole row taller.  Lists that count rows to size a
;; panel then jump when such a glyph scrolls in.  Scaling only those glyphs,
;; to the largest size that still fits the row, keeps every row one height.
;; Only emoji and symbols are considered: CJK text keeps its size.

(defconst my/ui--glyph-scales '(0.9 0.8 0.7 0.6 0.5)
  "Scales tried, largest first, for a glyph taller than its row.")

(defvar my/ui--glyph-scale-cache (make-hash-table :test #'equal)
  "Scale for (CHAR FACE-REMAPPING FONT): a number, or t when it fits.")

(defun my/ui--glyph-candidate-p (char)
  "Return non-nil when CHAR may come from a taller fallback font."
  (and (>= char #x2000)
       (memq (aref char-script-table char) '(emoji symbol))))

(defun my/ui--row-height (string remapping)
  "Return the pixel height of one row showing STRING under REMAPPING."
  (with-temp-buffer
    (setq-local face-remapping-alist remapping
                line-spacing nil)
    (insert string)
    (cdr (buffer-text-pixel-size nil nil t))))

(defun my/ui--glyph-scale (char face remapping)
  "Return the scale that fits CHAR in a row of FACE, or nil when it fits."
  (let* ((key (list char face remapping (face-attribute 'default :font)))
         (known (gethash key my/ui--glyph-scale-cache)))
    (if known
        (and (numberp known) known)
      (let* ((sample (lambda (scale)
                       (let ((glyph (propertize (string char) 'face face)))
                         (when scale
                           (put-text-property 0 1 'display `(height ,scale) glyph))
                         (my/ui--row-height
                          (concat (propertize "0" 'face face) glyph) remapping))))
             (line (my/ui--row-height (propertize "0" 'face face) remapping))
             (scale (unless (<= (funcall sample nil) line)
                      (or (seq-find (lambda (scale) (<= (funcall sample scale) line))
                                    my/ui--glyph-scales)
                          (car (last my/ui--glyph-scales))))))
        (puthash key (or scale t) my/ui--glyph-scale-cache)
        scale))))

(defun my/ui-fit-tall-glyphs (string &optional buffer)
  "Return STRING with glyphs taller than its rows scaled down to fit.
Rows are measured with BUFFER's face remapping, the current buffer's by
default.  Characters that already have a `display' property are kept.
STRING is returned unchanged when nothing needs scaling."
  (if (or (not (display-graphic-p))
          (not (multibyte-string-p string))
          (not (string-match-p "[^\0-῿]" string)))
      string
    (let ((remapping (buffer-local-value 'face-remapping-alist
                                         (or buffer (current-buffer))))
          copy)
      (dotimes (index (length string))
        (let ((char (aref string index)))
          (when-let* (((my/ui--glyph-candidate-p char))
                      ((not (get-text-property index 'display string)))
                      (scale (my/ui--glyph-scale
                              char (get-text-property index 'face string) remapping)))
            (unless copy (setq copy (copy-sequence string)))
            (put-text-property index (1+ index) 'display `(height ,scale) copy))))
      (or copy string))))

(defun my/ui-line-height (face &optional buffer)
  "Return the pixel height of a header or mode line drawn in FACE.
FACE may be a face name or attribute list; BUFFER's face remapping
applies, the current buffer's by default."
  (my/ui--row-height (propertize " " 'face face)
                     (buffer-local-value 'face-remapping-alist
                                         (or buffer (current-buffer)))))

;;;; Rounded corners

;; A child frame is an opaque rectangle on macOS: neither the native
;; rounded window style nor a transparent background applies to it.  A
;; panel that draws its own outline can still look rounded: images of its
;; corners paint the cut-off part in the color the panel sits on, while
;; everything between them stays native text.

(defvar my/ui--corner-cache (make-hash-table :test #'equal)
  "Corner strings by (CORNER RADIUS HEIGHT INSIDE OUTSIDE LINE ASCENT).")

(defun my/ui--svg-color (color)
  "Return COLOR, which may be an Emacs color name, as #RRGGBB."
  (if-let* ((values (and color (color-values color))))
      (apply #'format "#%02x%02x%02x" (mapcar (lambda (v) (/ v 257)) values))
    "none"))

(defun my/ui-corner (corner radius height inside outside line &optional ascent)
  "Return a string showing CORNER of a rounded box, RADIUS by HEIGHT pixels.
CORNER is `top-left', `top-right', `bottom-left' or `bottom-right'.  The
box is filled with INSIDE and outlined by a one-pixel LINE; the cut-off
corner shows OUTSIDE, the color the box sits on.  The image fills a row
HEIGHT pixels high and ignores the row's box, overline and underline.
ASCENT places it in the row as the image property does, `center' by
default; a row whose height comes from a spacer uses that spacer's ascent.
LINE nil draws no outline."
  (let ((key (list corner radius height inside outside line ascent)))
    (or (gethash key my/ui--corner-cache)
        (puthash
         key
         (let* ((r radius) (h height) (a (- r 0.5))
                ;; Drawn as the top-left corner, then mirrored.
                (transform (pcase corner
                             ('top-left "")
                             ('top-right (format "translate(%d 0) scale(-1 1)" r))
                             ('bottom-left (format "translate(0 %d) scale(1 -1)" h))
                             ('bottom-right (format "translate(%d %d) scale(-1 -1)" r h))))
                (svg (format "<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d'>\
<rect width='%d' height='%d' fill='%s'/>\
<g transform='%s'>\
<path d='M0,%d V%d A%d,%d 0 0 1 %d,0 H%d V%d Z' fill='%s'/>\
<path d='M0.5,%d V%d A%s,%s 0 0 1 %d,0.5' fill='none' stroke='%s' stroke-width='1'/>\
</g></svg>"
                             r h r h (my/ui--svg-color outside) transform
                             h r r r r r h (my/ui--svg-color inside)
                             h r a a r (my/ui--svg-color line))))
           (propertize " " 'face '(:box nil :overline nil :underline nil)
                       'display (create-image svg 'svg t :ascent (or ascent 'center))))
         my/ui--corner-cache))))

(defun my/ui-rounded-line (text radius height inside outside line top)
  "Return TEXT between the two corners of a rounded header or mode line.
TOP chooses the top corners, else the bottom ones.  RADIUS, HEIGHT,
INSIDE, OUTSIDE and LINE are as in `my/ui-corner'."
  (concat (my/ui-corner (if top 'top-left 'bottom-left)
                        radius height inside outside line)
          text
          (propertize " " 'display
                      `(space :align-to (- (+ right right-fringe right-margin)
                                           (,radius))))
          (my/ui-corner (if top 'top-right 'bottom-right)
                        radius height inside outside line)))

(defun my/ui--forget-glyph-scales (&rest _)
  "Measure glyphs and draw corners again after fonts or colors change."
  (clrhash my/ui--glyph-scale-cache)
  (clrhash my/ui--corner-cache))

(add-hook 'after-setting-font-hook #'my/ui--forget-glyph-scales)
(add-hook 'enable-theme-functions #'my/ui--forget-glyph-scales)

(provide 'ui-layout)
;;; ui-layout.el ends here
