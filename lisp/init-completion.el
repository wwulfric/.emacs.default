;;; init-completion.el --- Minibuffer completion and search -*- lexical-binding: t; -*-

;;; Commentary:
;; Vertico lists candidates, Orderless matches space-separated parts in any
;; order, Marginalia adds quiet annotations and Consult supplies search
;; commands with previews.  All of them extend `completing-read', so prompts
;; from Emacs, project.el, xref and lsp-bridge share one interface.
;; init-palette.el decides where that interface appears; init-lsp.el adds the
;; language-server pickers.

;;; Code:

(require 'vertico)
(require 'vertico-directory)
(require 'orderless)
(require 'marginalia)
(require 'consult)
(require 'consult-xref)
(require 'consult-imenu)
(require 'expui-icons)

;;;; Vertico

(setq vertico-count 10
      vertico-count-format nil
      enable-recursive-minibuffers t
      ;; M-x lists only commands that apply to the current buffer.
      read-extended-command-predicate #'command-completion-default-include-p
      minibuffer-prompt-properties
      '(read-only t cursor-intangible t face minibuffer-prompt))
(add-hook 'minibuffer-setup-hook #'cursor-intangible-mode)
(vertico-mode 1)

;; Edit paths as with ido: RET enters a directory, DEL removes a component,
;; and typing ~/ or / after a path starts over.
(keymap-set vertico-map "RET" #'vertico-directory-enter)
(keymap-set vertico-map "DEL" #'vertico-directory-delete-char)
(keymap-set vertico-map "M-DEL" #'vertico-directory-delete-word)
(add-hook 'rfn-eshadow-update-overlay-hook #'vertico-directory-tidy)

;; Group titles are small and faded instead of a ruled line.
(setq vertico-group-format "%s")

(defun my/completion-dim-directory (candidate)
  "Dim the directory part of file CANDIDATE so its name stands out."
  (let ((end (string-match-p "[^/]*/?\\'" candidate)))
    (when (and end (> end 0))
      (add-face-text-property 0 end 'shadow t candidate))
    candidate))

(defun my/completion-icon (candidate)
  "Return the icon of file or buffer CANDIDATE, or nil.
The icons are those of the sidebar and the tabs; init-palette.el places
them below its search icon."
  (when (expui-icons-svg-p)
    (pcase-let ((`(,category . ,target)
                 ;; Mixed lists such as `consult-buffer' tag each candidate.
                 (or (get-text-property 0 'multi-category candidate)
                     (cons (completion-metadata-get vertico--metadata 'category)
                           candidate))))
      (pcase category
        ((or 'file 'project-file) (expui-icons-icon-for-file target))
        ('buffer (when-let* ((buffer (get-buffer target)))
                   (expui-icons-icon-for-buffer buffer)))))))

(defun my/completion-format-file (format candidate &rest args)
  "Call FORMAT with CANDIDATE and ARGS, dimming directories of file candidates."
  (when (memq (completion-metadata-get vertico--metadata 'category)
              '(file project-file))
    (setq candidate (my/completion-dim-directory (copy-sequence candidate))))
  (apply format candidate args))
(advice-add 'vertico--format-candidate :around #'my/completion-format-file)

;;;; Matching

;; "ui pal" finds lisp/ui/init-palette.el; initials such as "pff" find
;; project-find-file.  File names try partial completion (/u/s/l) first.
(setq completion-styles '(orderless basic)
      completion-category-defaults nil
      completion-category-overrides '((file (styles partial-completion)))
      completion-pcm-leading-wildcard t
      orderless-matching-styles '(orderless-literal orderless-regexp
                                  orderless-initialism))

;; Results already matched by another program, e.g. a language server.
(defun my/completion-passthrough-try (string _table _predicate point)
  "Keep STRING and POINT as they are."
  (cons string point))

(defun my/completion-passthrough-all (_string table predicate _point)
  "Return every candidate of TABLE accepted by PREDICATE."
  (when-let* ((candidates (all-completions "" table predicate)))
    (nconc candidates 0)))

(add-to-list 'completion-styles-alist
             '(my/passthrough my/completion-passthrough-try
                              my/completion-passthrough-all
                              "Show candidates matched elsewhere unchanged."))

;;;; Annotations

;; Commands show only their keys, like a command palette; files show none.
;; M-A cycles to the detailed annotations.
(setq marginalia-align 'right
      marginalia-field-width 40)
(setf (alist-get 'command marginalia-annotators)
      '(marginalia-annotate-binding marginalia-annotate-command builtin none)
      (alist-get 'file marginalia-annotators)
      '(none marginalia-annotate-file builtin)
      (alist-get 'project-file marginalia-annotators)
      '(none marginalia-annotate-project-file builtin))
(keymap-set minibuffer-local-map "M-A" #'marginalia-cycle)
(marginalia-mode 1)

;;;; Search

;; Searches inside a buffer preview at once.  Choices that open files or
;; switch buffers preview on M-. only.
(setq consult-narrow-key "<")
(consult-customize
 consult-buffer consult-project-buffer consult-recent-file consult-bookmark
 consult-xref
 :preview-key "M-."
 consult-ripgrep consult-git-grep consult-grep
 :preview-key '(:debounce 0.3 any))

;; JetBrains macOS keys, matching s-1 for the project sidebar.
(keymap-global-set "C-x b" #'consult-buffer)
(keymap-global-set "s-e" #'consult-buffer)            ; Recent files
(keymap-global-set "s-O" #'project-find-file)         ; Go to file
(keymap-global-set "s-F" #'consult-ripgrep)           ; Find in files
(keymap-global-set "s-l" #'consult-goto-line)         ; Go to line
(keymap-global-set "M-g g" #'consult-goto-line)
(keymap-global-set "M-g i" #'consult-imenu)

(provide 'init-completion)
;;; init-completion.el ends here
