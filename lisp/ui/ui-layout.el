;;; ui-layout.el --- Pixel spacing and alignment for interface text -*- lexical-binding: t; -*-

;;; Commentary:
;; Interface text uses proportional fonts, smaller heights and CJK glyphs,
;; which column counts get wrong.  These helpers build `display' spaces
;; measured in pixels, shorten text by its displayed width, and keep glyphs
;; from fallback fonts (emoji, symbols) from making a row taller than the
;; others.  Components own what they lay out; this file only measures.

;;; Code:

(require 'seq)

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

(defun my/ui--forget-glyph-scales (&rest _)
  "Measure glyphs again after fonts change."
  (clrhash my/ui--glyph-scale-cache))

(add-hook 'after-setting-font-hook #'my/ui--forget-glyph-scales)
(add-hook 'enable-theme-functions #'my/ui--forget-glyph-scales)

(provide 'ui-layout)
;;; ui-layout.el ends here
