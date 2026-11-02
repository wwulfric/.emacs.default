;;; init-palette-config.el --- The floating panel in this configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; palette-islands.el is the panel; this file answers what it asks of the editor
;; (palette-islands-env.el) with this configuration's islands and workspaces.

;;; Code:

(require 'palette-islands)

(declare-function my/islands--card "init-islands" ())
(defvar my/islands-mode)

(defun my/palette-config-background ()
  "Return the islands' card color when they are on, else nil."
  (and (bound-and-true-p my/islands-mode) (my/islands--card)))

(defun my/palette-config-project-root ()
  "Return the root of the frame's workspace (init-workspace.el), or nil."
  (when-let* ((window (minibuffer-selected-window)))
    (frame-parameter (window-frame window) 'my/workspace-root)))

(setq palette-islands-background-function #'my/palette-config-background
      palette-islands-project-root-function #'my/palette-config-project-root)
(add-to-list 'palette-islands-titles '(my/file-symbols . "File Structure"))
(add-to-list 'palette-islands-ignore-commands 'my/welcome-filter)

(palette-islands-mode 1)

(provide 'init-palette-config)
;;; init-palette-config.el ends here
