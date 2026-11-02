;;; init-completion.el --- Minibuffer completion and search -*- lexical-binding: t; -*-

;;; Commentary:
;; Vertico lists candidates, Orderless matches space-separated parts in any
;; order, Marginalia adds quiet annotations and Consult supplies search
;; commands with previews.  All of them extend `completing-read', so prompts
;; from Emacs, project.el, xref and lsp-bridge share one interface.
;; palette-islands.el decides where that interface appears; init-lsp.el adds the
;; language-server pickers.

;;; Code:

(require 'vertico)
(require 'vertico-directory)
(require 'orderless)
(require 'marginalia)
(require 'consult)
(require 'consult-xref)
(require 'consult-imenu)
(require 'ui-layout)

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

;;;; Matching

;; "ui lay" finds lisp/ui/ui-layout.el; word prefixes such as "evp" find
;; eval-print-last-sexp, and initials such as "pff" project-find-file.
;; File names try partial completion (/u/s/l) first.

(defun my/completion-word-prefixes (component)
  "Match COMPONENT as prefixes of successive words, as JetBrains does.
Each character continues the word matched so far or starts a later one:
\"evp\" finds eval-print, and initials, one character a word, still
match.  Each character is a group, which orderless highlights alone."
  (when (> (length component) 0)
    (concat "\\<\\(" (regexp-quote (substring component 0 1)) "\\)"
            (mapconcat (lambda (char)
                         (let ((char (regexp-quote (string char))))
                           (concat "\\(?:\\(" char "\\)\\|.*\\<\\(" char "\\)\\)")))
                       (substring component 1) ""))))

(setq completion-styles '(orderless basic)
      completion-category-defaults nil
      completion-category-overrides '((file (styles partial-completion)))
      completion-pcm-leading-wildcard t
      orderless-matching-styles '(orderless-literal orderless-regexp
                                  my/completion-word-prefixes))

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

(declare-function palette-islands-candidates-text-end "palette-islands-candidates" ())

;; Commands show only their keys, like a command palette, and the panel's
;; footer their documentation; files show none; buffers only whether they
;; are modified, as their icon tells the type and their directory follows
;; the name.  M-A cycles files, buffers and structure to detailed
;; annotations, smaller than the names they describe.
(defface my/completion-key '((t (:inherit (fixed-pitch shadow))))
  "Keys of a command's binding, as JetBrains shows shortcuts in its lists."
  :group 'faces)

(defconst my/completion-key-gap 5
  "Pixels between the keys of a binding.")

(defun my/completion-keys (key)
  "Return the key sequence KEY with a little space between its keys."
  (mapconcat (lambda (label) (propertize label 'face 'my/completion-key))
             (split-string (key-description key) " ")
             (propertize " " 'display `(space :width (,my/completion-key-gap)))))

(defun my/completion-annotate-binding (cand)
  "Annotate command CAND with its keys at the right edge.
The list may use a proportional font, so the keys align by pixels."
  (when-let* ((symbol (intern-soft cand))
              (key (and (commandp symbol)
                        (where-is-internal symbol nil 'first-only))))
    (let ((keys (my/completion-keys key)))
      (my/ui-at-right keys (palette-islands-candidates-text-end)))))

(defun my/completion-annotate-buffer (cand)
  "Annotate buffer CAND with a dot if its file is modified."
  (when-let* ((buffer (get-buffer cand))
              ((buffer-file-name buffer))
              ((buffer-modified-p buffer)))
    (marginalia--fields ("●" :face 'marginalia-modified))))

(defun my/completion-annotate-detail (cand)
  "Annotate CAND of a mixed list, such as `consult-buffer', in detail.
Buffers and files get the detailed annotations of their own lists."
  (pcase-let ((`(,category . ,target) (get-text-property 0 'multi-category cand)))
    (pcase category
      ('buffer (marginalia-annotate-buffer target))
      ('file (marginalia-annotate-file target)))))

;; Each list has two states, short and detailed: Emacs's own annotations
;; would add a third that runs off the panel.
(setq marginalia-align 'right
      marginalia-field-width 40)
(setf (alist-get 'command marginalia-annotators)
      '(my/completion-annotate-binding)
      (alist-get 'buffer marginalia-annotators)
      '(my/completion-annotate-buffer marginalia-annotate-buffer)
      (alist-get 'multi-category marginalia-annotators)
      '(marginalia-annotate-multi-category my/completion-annotate-detail)
      (alist-get 'file marginalia-annotators)
      '(none marginalia-annotate-file)
      (alist-get 'project-file marginalia-annotators)
      '(none marginalia-annotate-project-file))
(defun my/completion-cycle-annotations ()
  "Show the next annotations of this list, if it has others.
Quietly: a message would show inside the floating panel's input."
  (interactive)
  (let ((inhibit-message t))
    (ignore-errors (marginalia-cycle))))
(keymap-set minibuffer-local-map "M-A" #'my/completion-cycle-annotations)
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
 :preview-key '(:debounce 0.3 any)
 ;; Go to the line on RET, not while typing its number.
 consult-goto-line
 :preview-key nil)

;; JetBrains macOS keys, matching s-1 for the project sidebar.  Searches of
;; files, text, lines and symbols are kinds of one window: init-search-config.el.
(keymap-global-set "C-x b" #'consult-buffer)
(keymap-global-set "s-e" #'consult-buffer)            ; Recent files
(keymap-global-set "M-g i" #'consult-imenu)

(provide 'init-completion)
;;; init-completion.el ends here
