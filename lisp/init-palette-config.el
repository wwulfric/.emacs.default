;;; init-palette-config.el --- The floating panel in this configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; palette-islands.el is the panel; this file answers what it asks of the editor
;; (palette-islands-env.el) with this configuration's islands and completion.

;;; Code:

(require 'palette-islands)

(declare-function my/islands--card "init-islands" ())
(declare-function my/completion-icon "init-completion" (candidate))
(declare-function my/completion-detail "init-completion" (candidate))
(defvar my/islands-mode)

(defun my/palette-config-background ()
  "Return the islands' card color when they are on, else nil."
  (and (bound-and-true-p my/islands-mode) (my/islands--card)))

(setq palette-islands-background-function #'my/palette-config-background
      palette-islands-icon-function #'my/completion-icon
      palette-islands-detail-function #'my/completion-detail)
(add-to-list 'palette-islands-titles '(my/file-symbols . "File Structure"))
(add-to-list 'palette-islands-ignore-commands 'my/welcome-filter)

(palette-islands-mode 1)

(provide 'init-palette-config)
;;; init-palette-config.el ends here
