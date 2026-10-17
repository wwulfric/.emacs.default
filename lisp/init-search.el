;;; init-search.el --- One search window for several kinds of results -*- lexical-binding: t; -*-

;;; Commentary:
;; As in VS Code's quick open, s-p searches files, and a prefix typed into
;; the empty input switches the kind of results:
;;
;;   >  commands     @  this file's structure     #  symbols of the project
;;   :  line         %  text in the project
;;
;; The prefix stays, faded, at the start of the input; Backspace in the empty
;; input removes it, back to files.  Text searches may start with any
;; character, so there another prefix needs that Backspace first.  Tabs in
;; the panel's header (init-palette.el) show the kind and switch on click,
;; keeping the input.  The keys of each picker open the window on its tab.
;; Each kind is the picker of its own file: init-completion.el, init-lsp.el
;; and Consult.

;;; Code:

(declare-function my/palette-set-tabs "init-palette" (tabs))
(declare-function my/palette-set-prefix "init-palette" (prefix))
(declare-function my/palette-set-action "init-palette" (key description))
(declare-function my/file-symbols "init-lsp" ())
(declare-function my/lsp-workspace-symbol "init-lsp" ())
(defvar lsp-bridge-imenu-function)
(defvar lsp-bridge-mode-map)
(defvar lsp-bridge-source-mode-map)

(defvar my/search-kinds
  '((files nil "Files" project-find-file)
    (commands ">" "Commands" execute-extended-command)
    (structure "@" "Structure" my/file-symbols)
    (symbols "#" "Symbols" my/lsp-workspace-symbol)
    (line ":" "Line" consult-goto-line)
    (text "%" "Text" consult-ripgrep))
  "Kinds of results, as (KIND PREFIX LABEL COMMAND).")

(defvar my/search--kind nil
  "Kind of the search window being opened.")

(defvar my/search--input nil
  "Input that the search window being opened starts with.")

(defvar my/search--structure-input nil
  "Input for the structure that a language server is still listing.")

(defvar-local my/search--current nil
  "Kind of results in this minibuffer.")

(defvar-local my/search--parent-map nil
  "Keymap of this minibuffer below `my/search-map'.")


(defconst my/search-tab-gap 20
  "Pixels between the tabs of the search window.")

;;;; Switching

(defun my/search--switch (kind input)
  "Close this search window and open it on KIND with INPUT."
  (throw 'my/search-switch (list kind input)))

(defun my/search--run (kind input &optional command)
  "Show KIND with INPUT by COMMAND, or by KIND's own, following switches."
  (let ((next (list kind input command)))
    (while next
      (setq next
            (catch 'my/search-switch
              (pcase-let ((`(,kind ,input ,command) next))
                (let ((my/search--kind kind)
                      (my/search--input input))
                  (when (eq kind 'structure)
                    (setq my/search--structure-input input))
                  (let* ((command (or command (nth 3 (assq kind my/search-kinds))))
                         ;; Consult reads its per-command settings, such as
                         ;; previews, by `this-command'.
                         (this-command command))
                    (minibuffer-with-setup-hook (:append #'my/search--setup)
                      (call-interactively command)))))
              nil)))))

(defvar consult-async-split-style)
(defvar consult-async-split-styles-alist)

(defun my/search--typed ()
  "Return what was typed into this search window.
Text searches start with Consult's separator, such as #, which is not."
  (let ((input (minibuffer-contents-no-properties))
        (initial (and (eq my/search--current 'text)
                      (plist-get (alist-get consult-async-split-style
                                            consult-async-split-styles-alist)
                                 :initial))))
    (if (and initial (string-prefix-p (string initial) input))
        (substring input 1)
      input)))

(defun my/search--prefix ()
  "Switch kinds when a prefix is typed into the empty input.
Text searches keep it: they may start with any character."
  (unless (eq my/search--current 'text)
    (when-let* ((typed (my/search--typed))
                ((= (length typed) 1))
                (kind (car (seq-find (lambda (entry) (equal (nth 1 entry) typed))
                                     my/search-kinds)))
                ((not (eq kind my/search--current))))
      (my/search--switch kind nil))))

(defun my/search-backspace ()
  "Delete backwards, or remove the prefix of an empty input, back to files."
  (interactive)
  (if (and (not (eq my/search--current 'files))
           (string-empty-p (my/search--typed)))
      (my/search--switch 'files nil)
    (call-interactively (or (and my/search--parent-map
                                 (lookup-key my/search--parent-map (kbd "DEL")))
                            #'delete-backward-char))))

(defvar-keymap my/search-map
  "DEL" #'my/search-backspace)

;;;; Tabs

(defun my/search--tabs (current)
  "Return the header tabs of the search window, CURRENT being open."
  (mapconcat
   (pcase-lambda (`(,kind ,prefix ,label ,_))
     (let ((map (make-sparse-keymap)))
       ;; Act on press, as the sidebar's toolbar does; this also keeps the
       ;; press from starting a header-line drag.
       (define-key map [header-line down-mouse-1]
                   (lambda () (interactive)
                     (my/search--switch kind (minibuffer-contents-no-properties))))
       (define-key map [header-line mouse-1] #'ignore)
       (propertize label
                   'face (if (eq kind current) 'my/palette-tab-active 'my/palette-tab)
                   'mouse-face 'highlight 'pointer 'hand 'local-map map
                   'help-echo (if prefix
                                  (format "Search %s, or type %s" (downcase label) prefix)
                                (format "Search %s" (downcase label))))))
   my/search-kinds
   (propertize " " 'display `(space :width (,my/search-tab-gap)))))

(defun my/search--setup ()
  "Prepare the minibuffer of a search window."
  (setq my/search--current my/search--kind
        my/search--parent-map (current-local-map))
  (use-local-map (make-composed-keymap my/search-map my/search--parent-map))
  (when (fboundp 'my/palette-set-tabs)
    (my/palette-set-tabs (my/search--tabs my/search--kind))
    (my/palette-set-prefix (nth 1 (assq my/search--kind my/search-kinds)))
    (when (eq my/search--kind 'files)
      (my/palette-set-action "> @ # : %" "Switch")))
  (add-hook 'post-command-hook #'my/search--prefix nil t)
  (when my/search--input
    (insert my/search--input)))

;;;; Commands

(defun my/search ()
  "Search files; a first > @ # : or % searches another kind."
  (interactive)
  (my/search--run 'files nil))

(defmacro my/search--define (kind)
  "Define `my/search-KIND', opening the search window on KIND."
  `(defun ,(intern (format "my/search-%s" kind)) ()
     ,(format "Open the search window on %s." kind)
     (interactive)
     (my/search--run ',kind nil)))

(my/search--define files)
(my/search--define commands)
(my/search--define structure)
(my/search--define symbols)
(my/search--define line)
(my/search--define text)

;; A language server lists the structure later, outside the first call.
(defun my/search--structure-reply ()
  "Show the structure that a language server listed, as a search kind."
  (interactive)
  (my/search--run 'structure (prog1 my/search--structure-input
                               (setq my/search--structure-input nil))
                  #'consult-imenu))
(setq lsp-bridge-imenu-function #'my/search--structure-reply)

;; VS Code and JetBrains macOS keys.
(keymap-global-set "s-p" #'my/search)
(keymap-global-set "M-x" #'my/search-commands)
(keymap-global-set "s-O" #'my/search-files)              ; Go to file
(keymap-global-set "s-F" #'my/search-text)               ; Find in files
(keymap-global-set "s-l" #'my/search-line)               ; Go to line
(keymap-global-set "M-g g" #'my/search-line)
(keymap-global-set "s-t" #'my/search-structure)          ; File structure
(keymap-global-set "s-<f12>" #'my/search-structure)
(dolist (map (list lsp-bridge-mode-map lsp-bridge-source-mode-map))
  (keymap-set map "s-o" #'my/search-symbols))            ; Symbol

(provide 'init-search)
;;; init-search.el ends here
