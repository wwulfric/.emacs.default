;; -*- lexical-binding: t; -*-
(require 'yasnippet)
(yas-global-mode 1)

(setq lsp-bridge-python-command (concat (global/load-file-path) "../.venv/bin/python"))

(require 'lsp-bridge)

;; ACM normally regenerates popup colors after load-theme (and daemon frame
;; creation).  Let Ink's explicit faces win while it is the active top theme.
(defun my/acm-init-theme-colors (original &optional force)
  "Preserve Ink's popup palette when ORIGINAL is asked to FORCE a reset."
  (if (and force (eq (car custom-enabled-themes) 'ink))
      (dolist (frame (frame-list))
        (dolist (face '(acm-frame-default-face acm-frame-border-face
                       acm-frame-select-face))
          (face-spec-recalc face frame)))
    (funcall original force)))
(advice-add 'acm-frame-init-colors :around #'my/acm-init-theme-colors)

;; Completion menus, their documentation and hover documentation share the
;; minibuffer panel's padding and row spacing (init-palette.el).
(defvar my/palette-padding)
(defvar my/palette-line-spacing)

(defun my/acm-frame-style (frame)
  "Pad and space the rows of acm popup FRAME like the minibuffer panel."
  (modify-frame-parameters frame `((left-fringe . ,my/palette-padding)
                                   (right-fringe . ,my/palette-padding)
                                   (line-spacing . ,my/palette-line-spacing)))
  (set-face-background 'fringe (face-background 'acm-frame-default-face nil t) frame)
  frame)
(advice-add 'acm-frame-make-frame :filter-return #'my/acm-frame-style)

(defun my/lsp-hover-from-top (&rest _)
  "Show hover documentation from its start, the signature, as plain text.
Its buffer is filled with point at the end, which a frame shorter than the
text would scroll to; its Markdown mode also resets the buffer's cursor
and wrapping settings."
  (when-let* ((frame lsp-bridge-popup-documentation-frame)
              ((frame-live-p frame))
              (window (frame-root-window frame)))
    (with-current-buffer (window-buffer window)
      (setq-local cursor-type nil
                  cursor-in-non-selected-windows nil
                  word-wrap t
                  ;; The padding fringes stay blank where lines wrap.
                  fringe-indicator-alist '((continuation nil nil))))
    (set-window-point window 1)
    (set-window-start window 1)))
(advice-add 'lsp-bridge-popup-documentation--callback :after #'my/lsp-hover-from-top)

;; Keep local language-server settings outside the vendored lsp-bridge tree.
(setq lsp-bridge-user-langserver-dir
      (expand-file-name "langserver" (file-name-directory
                                     (or load-file-name buffer-file-name))))

;; Cmd-click: jump to the definition, or list usages when clicking the
;; definition itself, as in JetBrains IDEs.
;; macOS maps Command to Super by default.
(defvar my/lsp-click-context nil)

(defun my/lsp-click-clear-context ()
  (setq my/lsp-click-context nil))

(defun my/lsp-click (event)
  "Find the clicked symbol's definition, or its usages if already there."
  (interactive "e")
  (mouse-set-point event)
  (my/lsp-click-clear-context)
  (let ((bounds (bounds-of-thing-at-point 'symbol)))
    (when bounds
      (when (and buffer-file-name (lsp-bridge-has-lsp-server-p))
        ;; Sync the click BEFORE find_define.  Otherwise post-command-hook
        ;; sends change_cursor afterwards and invalidates its response.
        (unless (equal lsp-bridge-last-cursor-position (point))
          (lsp-bridge-call-file-api "change_cursor" (lsp-bridge--position))
          (setq-local lsp-bridge-last-cursor-position (point)))
        (setq my/lsp-click-context
              (list (current-buffer) (point) (buffer-chars-modified-tick)
                    bounds)))
      (lsp-bridge-find-def))))

(defun my/lsp-click-maybe-usages (original filename filehost position)
  "Turn a definition response at the clicked symbol into its usages.
Otherwise call ORIGINAL with FILENAME, FILEHOST and POSITION to jump."
  (let ((context my/lsp-click-context))
    (my/lsp-click-clear-context)
    (if (and context
             (eq (current-buffer) (nth 0 context))
             (= (point) (nth 1 context))
             (= (buffer-chars-modified-tick) (nth 2 context))
             ;; Only compare local file positions here.
             (equal filehost "")
             buffer-file-name
             (not (file-remote-p buffer-file-name))
             (file-equal-p filename buffer-file-name)
             (let ((target (acm-backend-lsp-position-to-point position))
                   (bounds (nth 3 context)))
               (and (<= (car bounds) target) (< target (cdr bounds)))))
        (lsp-bridge-find-references)
      (funcall original filename filehost position))))

;; A later user command must not reuse an earlier click's context.
(add-hook 'pre-command-hook #'my/lsp-click-clear-context)
(advice-add 'lsp-bridge-define--jump :around #'my/lsp-click-maybe-usages)
(define-key lsp-bridge-mode-map (kbd "<s-down-mouse-1>") #'ignore)
(define-key lsp-bridge-mode-map (kbd "<s-mouse-1>") #'my/lsp-click)
;; Read-only dependency sources use the same gesture without starting HLS.
(define-key lsp-bridge-source-mode-map (kbd "<s-down-mouse-1>") #'ignore)
(define-key lsp-bridge-source-mode-map (kbd "<s-mouse-1>") #'my/lsp-click)

(global-lsp-bridge-mode)
;; (setq lsp-bridge-enable-hover-diagnostic t)

;; python
(setq lsp-bridge-python-lsp-server "ruff")
(setq lsp-bridge-python-multi-lsp-server "basedpyright_ruff")

;; java
(require 'lsp-bridge-jdtls) ;; 根据项目自动生成自定义配置，添加必要的启动参数
(setq lsp-bridge-enable-auto-import t) ;; 开启自动导入依赖，目前没有code action。补全时可以通过这个导入相应的依赖，建议开启。

;; java / kotlin: IntelliJ's own language server replaces jdtls once
;; installed with M-x intellij-server-install (it needs an IntelliJ IDEA
;; Ultimate license, found through Toolbox).
(setq intellij-server-directory (my/var-file "intellij-server/"))
(require 'intellij-server-lsp-bridge)

;; haskell
(require 'haskell-mode-autoloads)
(setq lsp-bridge-source-enable t)

;; markdown
(require 'markdown-ts-mode)
(setq lsp-bridge-markdown-lsp-server "marksman")
(setq markdown-command "pandoc")

;;;; Pickers
;; Choices about the symbol at point open beside it (init-palette.el);
;; project-wide searches use the palette at the top of the frame.

(require 'xref)
(require 'ui-layout)
(require 'consult-xref)
(defvar my/palette-placement)
(declare-function my/palette-set-status "init-palette" (status))
(declare-function my/palette-set-action "init-palette" (key description))
(declare-function my/palette-text-width "init-palette" ())

(defun my/xref-at-point (fetcher alist &optional prompt)
  "Choose among the xrefs of FETCHER beside the symbol at point.
ALIST is passed to `consult-xref'; PROMPT replaces its default prompt."
  (let ((my/palette-placement 'point)
        (consult--customize-alist
         (if prompt
             (cons (cons #'consult-xref
                         (append (list :prompt prompt)
                                 (alist-get #'consult-xref consult--customize-alist)))
                   consult--customize-alist)
           consult--customize-alist)))
    (consult-xref fetcher alist)))

(setq xref-show-xrefs-function #'my/xref-at-point
      xref-show-definitions-function #'my/xref-at-point)

;; Implementations and references arrive as the text of lsp-bridge's
;; reference buffer.  Show them as xrefs at point; C-c C-o opens that buffer,
;; which can edit and replace every match.
(defvar my/lsp-locations-kind "Usages")

(defun my/lsp-locations-implementations (&rest _)
  (setq my/lsp-locations-kind "Implementations"))

(defun my/lsp-locations-references (&rest _)
  (setq my/lsp-locations-kind "Usages"))

(dolist (command '(lsp-bridge-find-impl lsp-bridge-find-impl-other-window))
  (advice-add command :before #'my/lsp-locations-implementations))
(advice-add 'lsp-bridge-find-references :before #'my/lsp-locations-references)

;; Code lines are colored like their file: from its buffer when it is open,
;; otherwise by its major mode in a scratch buffer without mode hooks.
(defvar my/lsp-locations-fontify-limit 300
  "Most locations whose code is colored like their file.")

(defvar my/lsp-locations--scratch nil
  "Scratch buffers that color code, as (MODE . BUFFER).")

(defun my/lsp-locations--mode (file)
  "Return the major mode that visiting FILE would use, or nil."
  (let ((mode (assoc-default file auto-mode-alist #'string-match)))
    (when (symbolp mode)
      (when (fboundp 'major-mode-remap)
        (setq mode (major-mode-remap mode)))
      (and mode (fboundp mode) mode))))

(defun my/lsp-locations--faces (string)
  "Return STRING with its faces only: no invisible or display properties."
  (let ((plain (substring-no-properties string)) (start 0))
    (while (< start (length string))
      (let ((next (next-single-property-change start 'face string (length string))))
        (when-let* ((face (get-text-property start 'face string)))
          (put-text-property start next 'face face plain))
        (setq start next)))
    plain))

(defun my/lsp-locations--fontify (file row text)
  "Return TEXT, line ROW of FILE, with the faces of FILE's major mode.
Plain TEXT if coloring fails, so the list still opens."
  (condition-case nil
      (my/lsp-locations--faces (my/lsp-locations--fontify-1 file row text))
    (error text)))

(defun my/lsp-locations--fontify-1 (file row text)
  "Return line ROW of FILE colored, from its buffer or from TEXT."
  (if-let* ((buffer (find-buffer-visiting file)))
      (with-current-buffer buffer
        (save-excursion
          (save-restriction
            (widen)
            (goto-char (point-min))
            (forward-line (1- row))
            (let ((beg (line-beginning-position)) (end (line-end-position)))
              (font-lock-ensure beg end)
              (buffer-substring beg end)))))
    (if-let* ((mode (my/lsp-locations--mode file)))
        (let ((scratch (alist-get mode my/lsp-locations--scratch)))
          (unless (buffer-live-p scratch)
            (setq scratch (generate-new-buffer (format " *color %s*" mode)))
            (with-current-buffer scratch
              ;; Mode hooks would start language servers and editing modes.
              (delay-mode-hooks (funcall mode))
              (setq buffer-undo-list t))
            (setf (alist-get mode my/lsp-locations--scratch) scratch))
          (with-current-buffer scratch
            (erase-buffer)
            (insert text)
            (font-lock-ensure)
            (buffer-string)))
      text)))

(defun my/lsp-locations-summary (file row text &optional plain)
  "Return line ROW of FILE from TEXT, its match marked, indentation removed.
TEXT carries lsp-bridge's terminal colors.  Unless PLAIN, color the code."
  (let ((clean "") (start 0) match-start match-end)
    (while (string-match "\e\\[\\([0-9;]*\\)m" text start)
      (setq clean (concat clean (substring text start (match-beginning 0))))
      (pcase (match-string 1 text)
        ("94" (setq match-start (length clean)))
        ("0" (when (and match-start (not match-end))
               (setq match-end (length clean)))))
      (setq start (match-end 0)))
    (setq clean (concat clean (substring text start)))
    (let ((code (if plain clean (my/lsp-locations--fontify file row clean))))
      (when (and match-start match-end (<= match-end (length code)))
        (add-face-text-property match-start match-end 'xref-match nil code))
      (substring code (progn (string-match "\\`[ \t]*" code) (match-end 0))))))

(defun my/lsp-locations-parse (content)
  "Return xrefs for lsp-bridge reference CONTENT, or nil if a file is not local."
  (let ((count 0) file items)
    (catch 'remote
      (dolist (line (split-string content "\n"))
        (cond
         ((string-match "\\`\e\\[95m\\(.*\\)\e\\[0m\\'" line)
          (setq file (match-string 1 line))
          (unless (and (file-name-absolute-p file) (file-exists-p file))
            (throw 'remote nil)))
         ((and file (string-match "\\`\\([0-9]+\\):\\([0-9]+\\):" line))
          (let ((row (string-to-number (match-string 1 line)))
                (column (string-to-number (match-string 2 line))))
            (push (xref-make (my/lsp-locations-summary
                              file row (substring line (match-end 0))
                              (> (setq count (1+ count))
                                 my/lsp-locations-fontify-limit))
                             (xref-make-file-location file row column))
                  items)))))
      (nreverse items))))

(defvar-keymap my/lsp-locations-map
  "C-c C-o" (lambda () (interactive) (throw 'my/lsp-locations 'panel)))

(defun my/lsp-locations-popup (original content counter position)
  "Show lsp-bridge locations beside the symbol at point.
ORIGINAL displays CONTENT, COUNTER and POSITION in lsp-bridge's buffer."
  (let ((items (and (> counter 0) (display-graphic-p)
                    (my/lsp-locations-parse content))))
    (when (or (not items)
              (eq 'panel
                  (catch 'my/lsp-locations
                    (minibuffer-with-setup-hook
                        (:append (lambda ()
                                   (use-local-map
                                    (make-composed-keymap my/lsp-locations-map
                                                          (current-local-map)))
                                   ;; The buffer is the only way to edit
                                   ;; every match, so name its key.
                                   (my/palette-set-action "C-c C-o" "Edit all")))
                      (my/xref-at-point
                       (lambda () items) nil
                       (format "%s of %s: " my/lsp-locations-kind
                               (or (thing-at-point 'symbol t) ""))))
                    nil)))
      (funcall original content counter position))))

(advice-add 'lsp-bridge-references--popup :around #'my/lsp-locations-popup)

;; Rename edits the symbol where it is.
(defun my/lsp-rename-at-point (original &rest args)
  "Read the new name for ORIGINAL with ARGS beside the symbol."
  (let ((my/palette-placement 'point))
    (apply original args)))
(advice-add 'lsp-bridge-rename :around #'my/lsp-rename-at-point)

;; Workspace symbols: the language server matches while you type.
(defconst my/lsp-symbol-kinds
  ["" "file" "module" "namespace" "package" "class" "method" "property"
   "field" "constructor" "enum" "interface" "function" "variable" "constant"
   "string" "number" "boolean" "array" "object" "key" "null" "enum member"
   "struct" "event" "operator" "type parameter"]
  "Names of LSP SymbolKind values.")

(defconst my/lsp-symbol-icons
  [nil nil "nodes/module" "nodes/package" "nodes/package" "nodes/class"
   "nodes/method" "nodes/property" "nodes/field" "nodes/constructor"
   "nodes/enum" "nodes/interface" "nodes/function" "nodes/variable"
   "nodes/constant" "nodes/constant" "nodes/constant" "nodes/constant"
   "nodes/variable" "nodes/class" "nodes/property" "nodes/constant"
   "nodes/constant" "nodes/record" "nodes/field" "nodes/function" "nodes/type"]
  "JetBrains icons of LSP SymbolKind values, as in the IDE's symbol search.")

(defvar my/lsp-symbol--session nil "Minibuffer of the running symbol search.")
(defvar my/lsp-symbol--window nil "Window whose language server is searched.")
(defvar my/lsp-symbol--root nil "Directory that result paths are shown relative to.")
(defvar my/lsp-symbol--candidates nil)
(defvar my/lsp-symbol--index nil "Candidate string to symbol information.")
(defvar my/lsp-symbol--query nil)
(defvar my/lsp-symbol--timer nil)
(defvar my/lsp-symbol-history nil)

(defun my/lsp-symbol--table (string predicate action)
  "Complete STRING with PREDICATE and ACTION among the server's results."
  (if (eq action 'metadata)
      '(metadata (category . lsp-symbol)
                 (display-sort-function . identity)
                 (cycle-sort-function . identity))
    (complete-with-action action my/lsp-symbol--candidates string predicate)))

(add-to-list 'completion-category-overrides '(lsp-symbol (styles my/passthrough)))

(defconst my/lsp-symbol-name-width 40
  "Widest name column in characters; longer names are cut short.")

(defconst my/lsp-symbol-column-gap 16
  "Pixels between the name and place columns.")

(defvar my/palette-indent)

(defun my/lsp-symbol--width (name)
  "Return the width of NAME in pixels, in the panel's interface font."
  (string-pixel-width (propertize name 'face 'my/ui-font)))

(defun my/lsp-symbol--update (infos)
  "Show the symbols INFOS in the running search.
Names and places form columns, and an icon tells the kind; the panel's
bottom line spells out the kind and the full place of the selected one."
  (let* ((root (expand-file-name my/lsp-symbol--root))
         (index (make-hash-table :test #'equal))
         (rows
          (seq-map
           (lambda (info)
             (let* ((location (plist-get info :location))
                    (file (lsp-bridge-pick-file-path
                           (format "%s" (plist-get location :uri))))
                    (start (plist-get (plist-get location :range) :start))
                    (kind (or (plist-get info :kind) 0)))
               (list (plist-get info :name)
                     (if (< -1 kind (length my/lsp-symbol-kinds))
                         (aref my/lsp-symbol-kinds kind) "")
                     (format "%s:%d"
                             (if (string-prefix-p root file)
                                 (substring file (length root))
                               (abbreviate-file-name file))
                             (1+ (plist-get start :line)))
                     (cons file start)
                     (and (< -1 kind (length my/lsp-symbol-icons))
                          (aref my/lsp-symbol-icons kind))
                     (format "%s:%d" (abbreviate-file-name file)
                             (1+ (plist-get start :line))))))
           infos))
         (name-width (min my/lsp-symbol-name-width
                          (apply #'max 0 (mapcar (lambda (row) (string-width (nth 0 row)))
                                                 rows))))
         (names (mapcar (lambda (row)
                          (truncate-string-to-width (nth 0 row) name-width nil nil "…"))
                        rows))
         ;; The interface font is proportional: align the places by pixels,
         ;; after the panel's indentation.
         (column (+ (if (boundp 'my/palette-indent) my/palette-indent 0)
                    (apply #'max 0 (mapcar #'my/lsp-symbol--width names))
                    my/lsp-symbol-column-gap))
         ;; Places keep their end, the file and line, within the panel.
         (place-width (max 12 (- (or (and (buffer-live-p my/lsp-symbol--session)
                                          (fboundp 'my/palette-text-width)
                                          (with-current-buffer my/lsp-symbol--session
                                            (my/palette-text-width)))
                                     100)
                                 name-width 3)))
         (candidates nil))
    (pcase-dolist (`(,_ ,kind ,place ,target ,icon ,full) rows)
      (let ((candidate
             (concat (pop names)
                     (my/ui-space-to column)
                     (propertize (my/ui-fit-left place place-width)
                                 'face 'completions-annotations))))
        (add-text-properties 0 1 `(my/completion-icon ,icon
                                   my/completion-detail
                                   ,(if (string-empty-p kind) full
                                      (concat kind " · " full)))
                             candidate)
        (unless (gethash candidate index)
          (puthash candidate target index)
          (push candidate candidates))))
    (setq my/lsp-symbol--index index
          my/lsp-symbol--candidates (nreverse candidates))
    (when (buffer-live-p my/lsp-symbol--session)
      (with-current-buffer my/lsp-symbol--session
        ;; An empty list says why: nothing typed, or nothing indexed yet.
        (when (fboundp 'my/palette-set-status)
          (my/palette-set-status
           (cond ((string-empty-p (or my/lsp-symbol--query ""))
                  (propertize "Type to search symbols in the project" 'face 'shadow))
                 ((null candidates)
                  (propertize "No symbols found. The server may still be indexing."
                              'face 'shadow)))))
        (when (bound-and-true-p vertico--input)
          (setq vertico--input t)
          (vertico--exhibit))))))

(defun my/lsp-symbol--request (query)
  "Ask the language server for symbols matching QUERY."
  (if (string-empty-p query)
      (my/lsp-symbol--update nil)
    ;; Only while nothing is listed, so typing does not resize the panel.
    (when (and (fboundp 'my/palette-set-status) (null my/lsp-symbol--candidates)
               (buffer-live-p my/lsp-symbol--session))
      (with-current-buffer my/lsp-symbol--session
        (my/palette-set-status (propertize "Searching…" 'face 'shadow))))
    (when (window-live-p my/lsp-symbol--window)
      (with-current-buffer (window-buffer my/lsp-symbol--window)
        (lsp-bridge-call-file-api "workspace_symbol" query)))))

(defun my/lsp-symbol--schedule ()
  "Request symbols for the input once typing pauses."
  (let ((query (string-trim (minibuffer-contents-no-properties))))
    (unless (equal query my/lsp-symbol--query)
      (setq my/lsp-symbol--query query)
      (when (timerp my/lsp-symbol--timer) (cancel-timer my/lsp-symbol--timer))
      (setq my/lsp-symbol--timer
            (run-with-idle-timer 0.15 nil #'my/lsp-symbol--request query)))))

(defun my/lsp-symbol--receive (original info)
  "Send INFO to the running search, or to ORIGINAL when there is none."
  (if my/lsp-symbol--session
      (my/lsp-symbol--update info)
    (funcall original info)))
(advice-add 'lsp-bridge-workspace--list-symbols :around #'my/lsp-symbol--receive)

(defun my/lsp-workspace-symbol ()
  "Go to a symbol anywhere in the project; the server matches as you type."
  (interactive)
  (unless (and (bound-and-true-p lsp-bridge-mode) (lsp-bridge-has-lsp-server-p))
    (user-error "No language server for this buffer"))
  (setq my/lsp-symbol--window (selected-window)
        my/lsp-symbol--root (if-let* ((project (project-current)))
                                (project-root project)
                              default-directory)
        my/lsp-symbol--candidates nil
        my/lsp-symbol--index (make-hash-table :test #'equal)
        my/lsp-symbol--query nil)
  (let ((choice
         (unwind-protect
             (minibuffer-with-setup-hook
                 (lambda ()
                   (setq my/lsp-symbol--session (current-buffer))
                   (add-hook 'post-command-hook #'my/lsp-symbol--schedule nil t))
               (completing-read "Symbol: " #'my/lsp-symbol--table nil t
                                (when (use-region-p)
                                  (buffer-substring-no-properties
                                   (region-beginning) (region-end)))
                                'my/lsp-symbol-history))
           (setq my/lsp-symbol--session nil)
           (when (timerp my/lsp-symbol--timer) (cancel-timer my/lsp-symbol--timer)))))
    (when-let* ((target (gethash choice my/lsp-symbol--index)))
      (lsp-bridge-jump-to-file (car target) (cdr target)))))

(require 'lsp-bridge-imenu)

(defun my/file-symbols ()
  "Go to a symbol of this file, from the language server when there is one."
  (interactive)
  (if (and (bound-and-true-p lsp-bridge-mode) (lsp-bridge-has-lsp-server-p)
           (not (memq major-mode lsp-bridge-raw-imenu-modes)))
      (lsp-bridge-imenu)
    (consult-imenu)))

;; JetBrains macOS keys.  Cmd-click stays on s-mouse-1.  File structure and
;; project symbols are kinds of the search window: init-search.el.
(dolist (map (list lsp-bridge-mode-map lsp-bridge-source-mode-map))
  (keymap-set map "s-b" #'lsp-bridge-find-def)          ; Declaration
  (keymap-set map "M-s-b" #'lsp-bridge-find-impl)       ; Implementations
  (keymap-set map "M-<f7>" #'lsp-bridge-find-references) ; Usages
  (keymap-set map "S-<f6>" #'lsp-bridge-rename))         ; Rename


(provide 'init-lsp)
