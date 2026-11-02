;;; init-search-config.el --- The search window in this configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; palette-islands-search.el is the window; this file answers what it asks of
;; the editor (palette-islands-env.el): the kinds searched, from Consult and the
;; language server, and the keys that open them.

;;; Code:

(require 'palette-islands-search)

(declare-function my/file-symbols "init-lsp" ())
(declare-function my/lsp-workspace-symbol "init-lsp" ())
(declare-function consult-imenu "consult-imenu" ())
(defvar lsp-bridge-imenu-function)
(defvar lsp-bridge-mode-map)
(defvar lsp-bridge-source-mode-map)

(setq palette-islands-search-kinds
      '((files nil "Files" project-find-file)
        (commands ">" "Commands" execute-extended-command)
        (structure "@" "Structure" my/file-symbols)
        (symbols "#" "Symbols" my/lsp-workspace-symbol)
        (line ":" "Line" consult-goto-line)
        (text "%" "Text" consult-ripgrep)))

(palette-islands-search-define symbols)

;; A language server lists the structure later, outside the first call.
(defun my/search-structure-reply ()
  "Show the structure that a language server listed, as a search kind."
  (interactive)
  (palette-islands-search-run
   'structure
   (prog1 palette-islands-search-structure-input
     (setq palette-islands-search-structure-input nil))
   #'consult-imenu))
(setq lsp-bridge-imenu-function #'my/search-structure-reply)

;; VS Code and JetBrains macOS keys.
(keymap-global-set "s-p" #'palette-islands-search)
(keymap-global-set "M-x" #'palette-islands-search-commands)
(keymap-global-set "s-O" #'palette-islands-search-files)              ; Go to file
(keymap-global-set "s-F" #'palette-islands-search-text)               ; Find in files
(keymap-global-set "s-l" #'palette-islands-search-line)               ; Go to line
(keymap-global-set "M-g g" #'palette-islands-search-line)
(keymap-global-set "s-t" #'palette-islands-search-structure)          ; File structure
(keymap-global-set "s-<f12>" #'palette-islands-search-structure)
(dolist (map (list lsp-bridge-mode-map lsp-bridge-source-mode-map))
  (keymap-set map "s-o" #'palette-islands-search-symbols))            ; Symbol

(provide 'init-search-config)
;;; init-search-config.el ends here
