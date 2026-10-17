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

(defun my/completion--category (candidate)
  "Return (CATEGORY . TARGET) for CANDIDATE of the running completion.
Mixed lists such as `consult-buffer' tag each candidate with its own."
  (or (get-text-property 0 'multi-category candidate)
      (cons (completion-metadata-get vertico--metadata 'category) candidate)))

(declare-function my/palette-text-width "init-palette" ())

(defun my/completion--after-name (name directory)
  "Return NAME followed by DIRECTORY, faded and shortened from the left to fit."
  (let* ((room (or (and (fboundp 'my/palette-text-width) (my/palette-text-width))
                   80))
         (width (max 12 (- room (string-width name) 4)))
         (directory (if (> (string-width directory) width)
                        (concat "…" (substring directory (- 1 width)))
                      (copy-sequence directory))))
    (add-face-text-property 0 (length directory) 'shadow t directory)
    (concat name "  " directory)))

(defun my/completion-name-first (candidate)
  "Return file CANDIDATE as its name followed by its faded directory.
Names are what one scans for, as in JetBrains' Search Everywhere."
  (let ((start (string-match-p "[^/]*/?\\'" candidate)))
    (if (and start (> start 0))
        (my/completion--after-name (substring candidate start)
                                   (substring candidate 0 start))
      candidate)))

(defun my/completion-icon (candidate)
  "Return the icon of CANDIDATE, a file, buffer or tagged item, or nil.
The icons are those of the sidebar and the tabs; init-palette.el places
them below its search icon.  Other pickers name an icon in the
`my/completion-icon' property of their candidates."
  (when (expui-icons-svg-p)
    (if-let* ((name (get-text-property 0 'my/completion-icon candidate)))
        (expui-icons-icon name)
      (pcase-let ((`(,category . ,target) (my/completion--category candidate)))
        (pcase category
          ((or 'file 'project-file) (expui-icons-icon-for-file target))
          ('buffer (when-let* ((buffer (get-buffer target)))
                     (expui-icons-icon-for-buffer buffer))))))))

(defun my/completion--buffer-directory (name)
  "Return the directory of the file or Dired buffer NAME, or nil."
  (when-let* ((buffer (get-buffer name)))
    (if-let* ((file (buffer-file-name buffer)))
        (file-name-directory file)
      (and (provided-mode-derived-p (buffer-local-value 'major-mode buffer)
                                    'dired-mode)
           (buffer-local-value 'default-directory buffer)))))

(defun my/completion--summary (symbol)
  "Return the first line of SYMBOL's documentation, or nil."
  (when-let* ((doc (ignore-errors
                     (if (fboundp symbol)
                         (documentation symbol)
                       (documentation-property symbol 'variable-documentation))))
              ((not (string-empty-p doc))))
    (car (split-string doc "\n"))))

(defun my/completion-detail (candidate)
  "Return the full location or description of CANDIDATE.
Files, buffers, matches and xrefs have a location; commands, functions
and variables the first line of their documentation.  init-palette.el
shows it below the list.  Other pickers put it in the
`my/completion-detail' property of their candidates."
  (or (get-text-property 0 'my/completion-detail candidate)
      (pcase-let ((`(,category . ,target) (my/completion--category candidate)))
        (pcase category
          ((or 'command 'function 'variable 'symbol)
           (when-let* ((symbol (intern-soft target)))
             (my/completion--summary symbol)))
          ('consult-grep
           (when (string-match "\\`\\([^:\n]+\\):\\([0-9]+\\):" target)
             (format "%s:%s" (abbreviate-file-name
                              (expand-file-name (match-string 1 target)))
                     (match-string 2 target))))
          ('consult-xref
           (when-let* ((xref (get-text-property 0 'consult-xref target))
                       (location (xref-item-location xref)))
             (format "%s:%s" (abbreviate-file-name (xref-location-group location))
                     (xref-location-line location))))
          ((or 'file 'project-file)
           (abbreviate-file-name (expand-file-name target)))
          ('buffer (when-let* ((buffer (get-buffer target))
                               (file (or (buffer-file-name buffer)
                                         (my/completion--buffer-directory target))))
                     (abbreviate-file-name file)))))))

(defun my/completion-format-file (format candidate &rest args)
  "Call FORMAT with CANDIDATE and ARGS, showing names before directories.
Buffers of files or directories follow their name with the directory too."
  (pcase-let ((`(,category . ,target) (my/completion--category candidate)))
    (pcase category
      ((or 'file 'project-file)
       (setq candidate (my/completion-name-first candidate)))
      ('buffer
       (when-let* ((directory (my/completion--buffer-directory target)))
         (setq candidate (my/completion--after-name
                          candidate (abbreviate-file-name directory)))))))
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

;; Commands show only their keys, like a command palette; files show none;
;; buffers only whether they are modified, as their icon tells the type and
;; their directory follows the name.  M-A cycles to the detailed annotations.
(defun my/completion-annotate-buffer (cand)
  "Annotate buffer CAND with a dot if its file is modified."
  (when-let* ((buffer (get-buffer cand))
              ((buffer-file-name buffer))
              ((buffer-modified-p buffer)))
    (marginalia--fields ("●" :face 'marginalia-modified))))

(setq marginalia-align 'right
      marginalia-field-width 40)
(setf (alist-get 'command marginalia-annotators)
      '(marginalia-annotate-binding marginalia-annotate-command builtin none)
      (alist-get 'buffer marginalia-annotators)
      '(my/completion-annotate-buffer marginalia-annotate-buffer builtin none)
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
