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

(defun my/completion--category (candidate)
  "Return (CATEGORY . TARGET) for CANDIDATE of the running completion.
Mixed lists such as `consult-buffer' tag each candidate with its own."
  (or (get-text-property 0 'multi-category candidate)
      (cons (completion-metadata-get vertico--metadata 'category) candidate)))

(declare-function my/palette-text-width "init-palette" ())
(declare-function my/palette-text-end "init-palette" ())

(defconst my/completion-annotation-height 0.85
  "Height of detailed annotations relative to the candidates.")

(defvar-local my/completion--roots nil
  "Project roots of directories, cached for this minibuffer, or nil.")

(defun my/completion--root (directory)
  "Return the root of DIRECTORY's project, or nil; remote ones are not looked up."
  (unless my/completion--roots
    (setq my/completion--roots (make-hash-table :test #'equal)))
  (with-memoization (gethash directory my/completion--roots)
    (unless (file-remote-p directory)
      (when-let* ((project (project-current nil directory)))
        (file-name-as-directory (expand-file-name (project-root project)))))))

(defun my/completion--forget-roots ()
  "Look up project roots afresh in this minibuffer, whose buffer is reused."
  (setq my/completion--roots nil))
(add-hook 'minibuffer-setup-hook #'my/completion--forget-roots)

(defun my/completion--current-root ()
  "Return the root of the project the minibuffer was opened in, or nil.
It is the frame's workspace (init-workspace.el), else the project of the
buffer that was current."
  (let ((window (minibuffer-selected-window)))
    (if-let* ((root (and window (frame-parameter (window-frame window) 'my/workspace-root))))
        (file-name-as-directory (expand-file-name root))
      (my/completion--root
       (expand-file-name (buffer-local-value 'default-directory
                                             (window-buffer (or window (selected-window)))))))))

(defun my/completion--short-directory (directory)
  "Return DIRECTORY as a candidate shows it.
In the current project it is relative to the project's root, and empty
at the root; in another project it starts with that project's name.
Elsewhere it is abbreviated, and relative directories stay as they are."
  (if (not (file-name-absolute-p directory))
      (directory-file-name directory)
    (let* ((directory (file-name-as-directory (expand-file-name directory)))
           (root (my/completion--root directory)))
      (directory-file-name
       (cond ((not root) (abbreviate-file-name directory))
             ((equal root (my/completion--current-root))
              (if (equal root directory) "" (file-relative-name directory root)))
             (t (concat (file-name-nondirectory (directory-file-name root)) "/"
                        (file-relative-name directory root))))))))

(defun my/completion--text-end ()
  "Return the `:align-to' position where right-aligned candidate text ends.
Marginalia runs annotators in the original buffer, so ask the minibuffer."
  (or (when-let* (((fboundp 'my/palette-text-end))
                  (window (active-minibuffer-window)))
        (with-current-buffer (window-buffer window)
          (my/palette-text-end)))
      'right))

(defun my/completion--after-name (name directory)
  "Return NAME with DIRECTORY at the right, faded, smaller and shortened from
the left to fit.  DIRECTORY is shown as `my/completion--short-directory' says."
  (let* ((room (or (and (fboundp 'my/palette-text-width) (my/palette-text-width))
                   80))
         (width (max 12 (- room (string-width name) 6)))
         (directory (copy-sequence
                     (my/ui-fit-left (my/completion--short-directory directory) width))))
    (if (string-empty-p directory)
        name
      (add-face-text-property 0 (length directory) 'shadow t directory)
      (add-face-text-property 0 (length directory)
                              `(:height ,my/completion-annotation-height) t directory)
      (concat name
              (my/ui-right-space directory (my/completion--text-end) (current-buffer))
              directory))))

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

(defun my/completion--quiet-annotation (suffix)
  "Return the Marginalia annotation SUFFIX smaller, aligned right by pixels.
Marginalia aligns by columns, which a smaller or proportional font
breaks."
  (if-let* (((> (length suffix) 0))
            (align (text-property-any 0 (length suffix) 'marginalia--align t suffix)))
      (let ((suffix (copy-sequence suffix)))
        (add-face-text-property 0 (length suffix)
                                `(:height ,my/completion-annotation-height) t suffix)
        (put-text-property align (1+ align) 'display
                           (get-text-property
                            0 'display (my/ui-right-space (substring suffix (1+ align))
                                                          (my/completion--text-end)
                                                          (current-buffer)))
                           suffix)
        suffix)
    suffix))

(defun my/completion-format-file (format candidate &rest args)
  "Call FORMAT with CANDIDATE and ARGS, showing names before directories.
Buffers of files or directories follow their name with the directory too.
Matched lines of code stay in the code font where the list uses the
interface font (init-palette.el)."
  (pcase-let ((`(,category . ,target) (my/completion--category candidate)))
    (pcase category
      ((or 'file 'project-file)
       ;; The icon is the file's, not that of the directory now at the end.
       (let ((icon (expui-icons-name-for-file candidate)))
         (setq candidate (copy-sequence (my/completion-name-first candidate)))
         (put-text-property 0 (length candidate) 'my/completion-icon icon candidate)))
      ('buffer
       (when-let* ((directory (my/completion--buffer-directory target)))
         (setq candidate (my/completion--after-name
                          candidate (abbreviate-file-name directory)))))
      ((or 'consult-grep 'consult-xref)
       (setq candidate (copy-sequence candidate))
       (add-face-text-property 0 (length candidate) 'fixed-pitch t candidate))))
  (pcase-let ((`(,prefix ,suffix . ,rest) args))
    (apply format candidate prefix (my/completion--quiet-annotation suffix) rest)))
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
      (my/ui-at-right keys (my/completion--text-end)))))

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
;; files, text, lines and symbols are kinds of one window: init-search.el.
(keymap-global-set "C-x b" #'consult-buffer)
(keymap-global-set "s-e" #'consult-buffer)            ; Recent files
(keymap-global-set "M-g i" #'consult-imenu)

(provide 'init-completion)
;;; init-completion.el ends here
