;;; init-typography.el --- Font roles for code and Chinese prose -*- lexical-binding: t; -*-

;;; Commentary:
;; Keep the frame's ASCII font unchanged.  Prose opts into `variable-pitch';
;; code, tables and paths explicitly inherit `fixed-pitch'.  Separate fontsets
;; reserve Heiti SC for code CJK and PingFang SC for prose.  Only the former
;; receives a family-specific relative scale to match PT Mono's character grid.

;;; Code:

(require 'seq)
(require 'fontset)

(defconst my/typography-font-height 140
  "Nominal fontset size in tenths of a point; faces follow the frame size.")

(defvar my/typography-code-rescale-entry nil
  "Owned code-CJK rescale entry; existing user rules remain untouched.")

(defface my-writing-heading-font '((t (:inherit variable-pitch :weight normal)))
  "Prose heading font; use a real medium weight when the family provides it."
  :group 'faces)

(defun my/typography-first-family (candidates available)
  "Return the first of CANDIDATES present in AVAILABLE font families."
  (seq-find (lambda (family) (member family available)) candidates))

(defun my/typography-medium-weight-p (family frame)
  "Return non-nil if FAMILY has an actual medium-weight font on FRAME."
  (seq-some (lambda (font) (memq (font-get font :weight) '(medium 100)))
            (list-fonts (font-spec :family family) frame)))

(defun my/typography-set-code-rescale (family)
  "Reserve a relative scale for code-only FAMILY, or remove it when nil.
Reloading replaces only our own rule and preserves pre-existing rules."
  (when my/typography-code-rescale-entry
    (setq face-font-rescale-alist
          (delq my/typography-code-rescale-entry face-font-rescale-alist)
          my/typography-code-rescale-entry nil))
  (when family
    ;; CoreText: PT Mono's Latin cell is 0.6 em; Heiti's Han cell is 1 em.
    ;; Keep the ratio relative so text-scale can enlarge both scripts together.
    (setq my/typography-code-rescale-entry
          (cons (font-spec :family family) 1.2))
    (push my/typography-code-rescale-entry face-font-rescale-alist)))

(defun my/typography-fontset (family cjk role)
  "Make a ROLE fontset with FAMILY for Latin and CJK for Chinese text."
  (let ((fontset (create-fontset-from-ascii-font
                  (format "%s-%s" family (/ my/typography-font-height 10.0))
                  ;; This becomes one XLFD field; an extra hyphen is invalid.
                  nil (concat "ink" role))))
    (when cjk
      (dolist (characters '(han kana bopomofo
                           (#x3000 . #x303f) (#xff00 . #xffef)))
        ;; Leave size/weight unspecified so headings and text scaling work.
        (set-fontset-font fontset characters (font-spec :family cjk))))
    fontset))

(defun my/typography-apply (frame)
  "Apply code/prose font roles to a top-level graphical FRAME."
  (when (and (display-graphic-p frame) (not (frame-parent frame)))
    (with-selected-frame frame
      (let* ((families (font-family-list frame))
             (fixed (or (my/typography-first-family
                         '("PT Mono" "Menlo" "Monaco" "DejaVu Sans Mono") families)
                        (face-attribute 'default :family frame)))
             (cjk (my/typography-first-family
                   '("PingFang SC" "Hiragino Sans GB" "Heiti SC"
                     "Noto Sans CJK SC" "Noto Sans SC" "LXGW WenKai") families))
             (prose (or cjk (my/typography-first-family
                             '("Helvetica Neue" "Arial" "DejaVu Sans") families)
                        fixed))
             ;; A separate family keeps code-grid scaling out of prose faces.
             (fixed-cjk (if (and (equal fixed "PT Mono")
                                 (member "Heiti SC" families)
                                 (not (equal prose "Heiti SC")))
                            "Heiti SC" cjk)))
        (my/typography-set-code-rescale
         (and (equal fixed "PT Mono") (equal fixed-cjk "Heiti SC")
              (not (equal prose fixed-cjk)) fixed-cjk))
        (let ((fixed-fontset (my/typography-fontset fixed fixed-cjk "fixed"))
              (prose-fontset (my/typography-fontset prose cjk "prose")))
          (set-face-attribute 'fixed-pitch frame
                              :family fixed :height 1.0
                              :weight 'normal :slant 'normal :fontset fixed-fontset)
          (set-face-attribute 'variable-pitch frame
                              :family prose :height 1.0
                              :weight 'normal :slant 'normal :fontset prose-fontset)
          (set-face-attribute 'my-writing-heading-font frame
                              :inherit 'variable-pitch
                              :weight (if (my/typography-medium-weight-p prose frame)
                                          'medium 'normal))
          ;; This only chooses non-ASCII fallback; code retains its current font.
          (set-face-attribute 'default frame :fontset fixed-fontset))))))

(defun my/typography-refresh (&optional _theme)
  "Apply font roles to existing frames, including after a theme reload."
  (dolist (frame (frame-list))
    (my/typography-apply frame)))

(add-hook 'after-make-frame-functions #'my/typography-apply)
(add-hook 'enable-theme-functions #'my/typography-refresh)
(my/typography-refresh)

(provide 'init-typography)
;;; init-typography.el ends here
