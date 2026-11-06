;;; init-tool-islands.el --- Tool windows drawn as the sidebar is -*- lexical-binding: t; -*-

;;; Commentary:
;; The tool windows (Commit, Git log, Find, Problems) draw their lists,
;; headers and buttons with the tool-islands package, in lisp/tool-islands.
;; Here they take the sidebar's rows, pills and fonts, and the islands'
;; corners and card color.

;;; Code:

(require 'tool-islands)

(declare-function my/islands--header "init-islands" (format))
(declare-function my/islands--card "init-islands" ())
(declare-function my/ui-header-space "frame-setting" (width))
(declare-function my/ui-line-end-inset "ui-layout" ())
(defvar my/islands-mode)
(defvar my/sidebar-row-height)
(defvar my/sidebar-source-icons)
(defvar my/ui-header-height)
(defvar my/ui-header-ascent)

(defun my/tool-islands-header (format)
  "Return header FORMAT inside the islands' corners when they are on."
  (if (bound-and-true-p my/islands-mode) (my/islands--header format) format))

(defun my/tool-islands-background ()
  "Return the islands' card color when they are on, else nil."
  (and (bound-and-true-p my/islands-mode) (my/islands--card)))

(setq tool-islands-header-function #'my/tool-islands-header
      tool-islands-background-function #'my/tool-islands-background
      tool-islands-row-height my/sidebar-row-height
      tool-islands-header-height my/ui-header-height
      tool-islands-header-ascent my/ui-header-ascent
      tool-islands-header-space-function #'my/ui-header-space
      tool-islands-line-end-inset #'my/ui-line-end-inset
      tool-islands-source-icons my/sidebar-source-icons
      tool-islands-hl-margin 6
      tool-islands-hl-radius 6
      tool-islands-button-render-function #'tool-islands-button-rounded
      tool-islands-button-radius nil
      tool-islands-button-padding 12)

;; Header titles use typography only; the sidebar title inherits default's
;; background, which would cover the header's card color.
(face-spec-set 'tool-islands-title '((t :inherit my/ui-font :weight medium))
               'face-defface-spec)
(pcase-dolist (`(,face . ,config-face)
               '((tool-islands-font . my/ui-font)
                 (tool-islands-text . my/sidebar-file-name)
                 (tool-islands-neutral-icon . my/sidebar-neutral-icon)
                 (tool-islands-source-icon . my/sidebar-source-icon)
                 (tool-islands-hl-line . my/sidebar-hl-line)
                 (tool-islands-hl-line-inactive . my/sidebar-hl-line-inactive)
                 (tool-islands-toolbar-hover . my/sidebar-toolbar-hover)))
  ;; In place of the package's own default, whose colors would win.
  (face-spec-set face `((t :inherit ,config-face)) 'face-defface-spec))

(provide 'init-tool-islands)
;;; init-tool-islands.el ends here
