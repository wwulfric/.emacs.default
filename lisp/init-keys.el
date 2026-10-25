;;; init-keys.el --- Finding and learning the configuration's shortcuts -*- lexical-binding: t; -*-

;;; Commentary:
;; Three ways to learn the keys this configuration adds:
;;
;; - s-? lists them in the minibuffer panel, grouped by area, each with
;;   what it does; typing filters by description, command or key, and RET
;;   runs one.  The list is read from the keymaps each time, so it follows
;;   every new binding.  Global keys are those that differ from Emacs's
;;   own, which this file remembers when it loads, before anything else
;;   binds a key; keymaps that packages define and the configuration only
;;   adds to are remembered the same way with `my/keys-remember'.
;; - A command run by a click or by M-x, though it has a key, names its
;;   key in the echo area, a few times a session, as IntelliJ's Key
;;   Promoter does.
;; - which-key lists what can follow a prefix key such as C-x or C-c.
;;
;; `my/keys-update-readme' writes the same list into README.md.

;;; Code:

(require 'seq)
(require 'subr-x)

(declare-function my/completion-keys "init-completion" (key))
(declare-function my/completion--text-end "init-completion" ())
(declare-function my/ui-at-right "ui-layout" (text &optional edge buffer))

;;;; Bindings in a keymap

(defconst my/keys--ignored-events
  '(menu-bar tool-bar tab-bar header-line mode-line tab-line vertical-line
    horizontal-scroll-bar vertical-scroll-bar left-fringe right-fringe
    left-margin right-margin compose-last-chars help-echo select-window
    switch-frame delete-frame iconify-frame make-frame-visible focus-in
    focus-out ns-drag-file ns-drag-text ns-show-prefs ns-open-file-line
    ns-change-font ns-spi-service-call ns-toggle-toolbar)
  "Events whose bindings are no keys one types.")

(defun my/keys--pointer-event-p (event)
  "Return non-nil if EVENT comes from a mouse, touchpad or window frame."
  (and (symbolp (event-basic-type event))
       (or (memq (event-basic-type event) my/keys--ignored-events)
           (string-match-p "mouse\\|wheel\\|drag\\|touch\\|pinch\\|swipe"
                           (symbol-name (event-basic-type event))))))

(defun my/keys--walk (map function &optional own prefix depth)
  "Call FUNCTION with each key of MAP and its binding.
Prefix keys are followed; with OWN, a parent keymap's bindings are left
out.  PREFIX and DEPTH are for the recursion."
  (let ((depth (or depth 0)))
    (when (< depth 4)
      (funcall (if own #'map-keymap-internal #'map-keymap)
               (lambda (event binding)
                 (unless (or (consp event) (my/keys--pointer-event-p event))
                   (let ((key (vconcat prefix (vector event)))
                         (binding (if (and (consp binding) (stringp (car binding)))
                                      (cdr binding)
                                    binding)))
                     (if (and (keymapp binding) (not (eq event 'remap)))
                         ;; A keymap not loaded yet, such as kmacro's, is left alone.
                         (let ((map (if (symbolp binding) (indirect-function binding) binding)))
                           (when (eq (car-safe map) 'keymap)
                             (my/keys--walk map function own key (1+ depth))))
                       (if (eq event 'remap)
                           (when (keymapp binding)
                             (map-keymap (lambda (old new)
                                           (funcall function (vector 'remap old) new))
                                         binding))
                         (funcall function key binding))))))
               map))))

(defun my/keys--table (map &optional own)
  "Return a table of MAP's keys, as descriptions, to their bindings."
  (let ((table (make-hash-table :test #'equal)))
    (my/keys--walk map (lambda (key binding)
                         (puthash (key-description key) binding table))
                   own)
    table))

;;;; What Emacs binds itself

(defvar my/keys-baselines nil
  "Keymaps as packages defined them, as (SYMBOL . TABLE).
Only keys that differ from these count as the configuration's.")

(defun my/keys-remember (symbol)
  "Remember the keymap in SYMBOL as it is now, before the configuration adds keys."
  (setf (alist-get symbol my/keys-baselines)
        (my/keys--table (symbol-value symbol))))

;; Once: reloading this file must not take the configuration's keys for Emacs's.
(unless (alist-get 'global-map my/keys-baselines)
  (my/keys-remember 'global-map))

;;;; The configuration's keys

(defvar my/keys-global-groups
  '(("\\`git-islands-\\|\\`magit-\\|\\`diff-hl-" . "Git")
    ("\\`my/sidebar-" . "Sidebar")
    ("\\`my/search\\|\\`consult-\\|imenu\\|\\`ibuffer\\|\\`project-" . "Search")
    ("\\`xref-\\|lsp" . "Code")
    ("\\`my/workspace\\|\\`my/welcome-" . "Workspaces")
    ("\\`tab-line-\\|kill-this-buffer" . "Tabs"))
  "Groups of global keys, by a regexp their command's name matches.
Keys whose command matches none are under Editing.")

(defvar my/keys-local-maps
  '(("Sidebar" init-sidebar my/sidebar-mode-map)
    ("Start page" init-welcome my/welcome-mode-map)
    ("Commit tool window" git-islands-commit-panel git-islands-commit-mode-map)
    ("Commit message" git-islands-commit-panel git-islands-message-mode-map)
    ("Git log" git-islands-log git-islands-log-mode-map)
    ("Commit details" git-islands-log git-islands-details-mode-map)
    ("Branches pane" git-islands-log git-islands-refs-mode-map)
    ("Diff" git-islands-diff git-islands-diff-mode-map)
    ("Conflicts" git-islands-merge git-islands-conflicts-mode-map)
    ("Merge" git-islands-merge3 git-islands-merge-pane-mode-map)
    ("Annotate" git-islands-annotate git-islands-annotate-mode-map)
    ("Changed lines" diff-hl diff-hl-mode-map))
  "Keys that apply in one place, as (TITLE FEATURE KEYMAP).
The keymap's own keys are listed, or only those differing from what
`my/keys-remember' saw, if it saw the keymap.")

(defvar my/keys-ignored-commands '(server-edit)
  "Commands whose keys Emacs binds itself, though after this file loads.")

(defun my/keys--global-group (command)
  "Return the group of the global key running COMMAND."
  (or (and (symbolp command)
           (cdr (seq-find (lambda (group) (string-match-p (car group) (symbol-name command)))
                          my/keys-global-groups)))
      "Editing"))

(defun my/keys--changed (symbol own)
  "Return the keys of keymap SYMBOL the configuration bound, as (KEY . COMMAND).
OWN leaves out the keymap's parents."
  (let ((baseline (alist-get symbol my/keys-baselines))
        keys)
    (my/keys--walk (symbol-value symbol)
                   (lambda (key binding)
                     (when (and (commandp binding)
                                (not (memq binding '(self-insert-command undefined ignore)))
                                (not (memq binding my/keys-ignored-commands))
                                (not (and baseline
                                          (eq binding (gethash (key-description key) baseline)))))
                       (push (cons key binding) keys)))
                   own)
    (nreverse keys)))

(defun my/keys--expand-remaps (keys)
  "Return KEYS with each remapping replaced by the keys of what it remaps."
  (mapcan (pcase-lambda (`(,key . ,command))
            (if (eq (aref key 0) 'remap)
                (mapcar (lambda (old-key) (cons old-key command))
                        (seq-remove (lambda (k) (seq-some #'my/keys--pointer-event-p k))
                                    (where-is-internal (aref key 1) nil nil t t)))
              (list (cons key command))))
          keys))

(defun my/keys--before-p (a b)
  "Return non-nil if key A sorts before key B.
One-stroke Command keys come first, then shorter keys, then by name."
  (let ((da (key-description a)) (db (key-description b)))
    (let ((sa (if (string-prefix-p "s-" da) 0 1))
          (sb (if (string-prefix-p "s-" db) 0 1)))
      (cond ((/= sa sb) (< sa sb))
            ((/= (length a) (length b)) (< (length a) (length b)))
            (t (string< da db))))))

(defun my/keys--same-p (a b)
  "Return non-nil if commands A and B are one entry: the same, or unnamed alike."
  (or (eq a b)
      (and (not (symbolp a)) (not (symbolp b))
           (equal (my/keys-describe a) (my/keys-describe b)))))

(defun my/keys--entries (group keys)
  "Return GROUP's entries from KEYS, one per command, as (GROUP COMMAND KEYS).
Unnamed commands that say the same, such as one per digit, share one."
  (let (entries)
    (pcase-dolist (`(,key . ,command) (my/keys--expand-remaps keys))
      (if-let* ((entry (seq-find (lambda (e) (my/keys--same-p (nth 1 e) command)) entries)))
          (setf (nth 2 entry) (append (nth 2 entry) (list key)))
        (push (list group command (list key)) entries)))
    (dolist (entry entries)
      (setf (nth 2 entry) (sort (nth 2 entry) #'my/keys--before-p)))
    (sort (nreverse entries)
          (lambda (a b) (my/keys--before-p (car (nth 2 a)) (car (nth 2 b)))))))

(defun my/keys-entries ()
  "Return the configuration's keys as (GROUP COMMAND KEYS), grouped.
Global keys come first, by area, then those of each place."
  (let ((global (my/keys--changed 'global-map nil))
        groups)
    (pcase-dolist (`(,key . ,command) global)
      (let ((group (my/keys--global-group command)))
        (push (cons key command) (alist-get group groups nil nil #'equal))))
    (append
     (mapcan (lambda (group)
               (when-let* ((keys (alist-get group groups nil nil #'equal)))
                 (my/keys--entries group (nreverse keys))))
             (append (mapcar #'cdr my/keys-global-groups) '("Editing")))
     (mapcan (pcase-lambda (`(,title ,feature ,symbol))
               (when (or (boundp symbol) (require feature nil t))
                 (when (and (boundp symbol) (keymapp (symbol-value symbol)))
                   (my/keys--entries (concat "In the " title)
                                     (my/keys--changed symbol t)))))
             my/keys-local-maps))))

(defun my/keys-describe (command)
  "Return what COMMAND does, from the first line of its documentation."
  ;; Substituted: quotes become curly and \\[command] its key.
  (let ((doc (ignore-errors (documentation command))))
    (cond ((and doc (not (string-empty-p doc)))
           (string-remove-suffix "." (car (split-string doc "\n"))))
          ((symbolp command)
           (capitalize (replace-regexp-in-string
                        "-" " " (replace-regexp-in-string "\\`.*/" "" (symbol-name command)))))
          (t "An unnamed command"))))

(defun my/keys-command-name (command)
  "Return COMMAND's name, or a placeholder for an anonymous one."
  (if (symbolp command) (symbol-name command) "anonymous command"))

;;;; The reference

(defun my/keys--candidate (entry)
  "Return the candidate showing ENTRY, a (GROUP COMMAND KEYS)."
  (pcase-let* ((`(,group ,command ,keys) entry)
               (descriptions (mapconcat #'key-description keys " ")))
    (concat (propertize (my/keys-describe command)
                        'my/keys-entry entry
                        'my/completion-detail (format "%s  ·  %s"
                                                      (my/keys-command-name command)
                                                      descriptions))
            ;; Matched but not shown: the command's name and its keys.
            (propertize (format " %s %s %s" (my/keys-command-name command) descriptions group)
                        'display ""))))

(defun my/keys--annotate (candidate)
  "Return CANDIDATE's keys at the right edge of the panel."
  (when-let* ((entry (get-text-property 0 'my/keys-entry candidate)))
    (my/ui-at-right (mapconcat #'my/completion-keys (nth 2 entry)
                               ;; In pixels, as the alignment measures them.
                               (propertize " " 'display '(space :width (14))))
                    (my/completion--text-end))))

(defun my/keys-reference ()
  "List the configuration's keyboard shortcuts; run the one chosen.
A key that applies only in one place, such as the Git log, shows what it
does there instead of running."
  (interactive)
  (let* ((candidates (mapcar #'my/keys--candidate (my/keys-entries)))
         (table (lambda (string predicate action)
                  (if (eq action 'metadata)
                      `(metadata (category . my-key)
                                 (group-function
                                  . ,(lambda (candidate transform)
                                       (if transform candidate
                                         (nth 0 (get-text-property 0 'my/keys-entry candidate)))))
                                 (annotation-function . my/keys--annotate)
                                 (display-sort-function . identity)
                                 (cycle-sort-function . identity))
                    (complete-with-action action candidates string predicate))))
         (choice (completing-read "Keyboard Shortcuts: " table nil t))
         (entry (get-text-property 0 'my/keys-entry
                                   (or (car (member choice candidates)) ""))))
    (when entry
      (pcase-let ((`(,group ,command ,_keys) entry))
        (if (and (string-prefix-p "In the " group) (symbolp command))
            (describe-function command)
          (setq this-command command)
          (call-interactively command))))))

(keymap-global-set "s-?" #'my/keys-reference)

;;;; The key promoter

(defcustom my/keys-promote-times 3
  "How many times a session a command run without its key names the key."
  :type 'integer
  :group 'convenience)

(defvar my/keys--promoted (make-hash-table :test #'eq)
  "Commands to the times their key was named this session.")

(defun my/keys--typed-key (command)
  "Return a key that runs COMMAND here and is typed, not clicked, or nil."
  (seq-find (lambda (key) (not (seq-some #'my/keys--pointer-event-p key)))
            (where-is-internal command nil)))

(defun my/keys--name-key (command key)
  "Say in the echo area that KEY runs COMMAND, if not too often already."
  (when (< (gethash command my/keys--promoted 0) my/keys-promote-times)
    (puthash command (1+ (gethash command my/keys--promoted 0)) my/keys--promoted)
    (let ((message-log-max nil))
      (message "%s  %s" (my/completion-keys key) (my/keys-describe command)))))

(defun my/keys--promote (command keys)
  "Name the key of COMMAND if KEYS, which ran it, came from a click."
  (when-let* (((symbolp command))
              ((commandp command))
              ((seq-some #'my/keys--pointer-event-p keys))
              (key (my/keys--typed-key command)))
    (my/keys--name-key command key)))

(defun my/keys-promote ()
  "Name the key of a command just run by a click, as Key Promoter does."
  (my/keys--promote this-command (this-command-keys-vector)))

(add-hook 'post-command-hook #'my/keys-promote)

;; M-x says the key too, the same way, rather than Emacs's own sentence.
(setq suggest-key-bindings t)
(defun my/keys--after-extended-command (function &rest args)
  "Run FUNCTION with ARGS, then name the key of the command it ran."
  (let ((suggest-key-bindings nil))
    (prog1 (apply function args)
      (when-let* ((command this-command)
                  ((symbolp command))
                  (key (my/keys--typed-key command)))
        (my/keys--name-key command key)))))
(advice-add 'execute-extended-command :around #'my/keys--after-extended-command)

;;;; Prefix keys

;; which-key's own popups would take a bottom side window, where the Git
;; tool window lives, or the echo area, where the status bar does; it
;; floats above the status bar instead, in the minibuffer panel's colors.
(require 'which-key)
(require 'posframe)

(defconst my/keys-which-key-padding 12
  "Pixels of padding on each side of the which-key popup.")

(defun my/keys--which-key-dimensions ()
  "Return the most which-key may fill, as (LINES . COLUMNS)."
  (cons (max 4 (/ (frame-height) 3))
        (min 140 (- (frame-width) 8))))

(defun my/keys--which-key-position (info)
  "Place the which-key popup, described by INFO, centered above the status bar."
  (pcase-let ((`(,x . ,y) (posframe-poshandler-frame-bottom-center info)))
    (cons x (- y (* 2 (frame-char-height))))))

(defun my/keys--which-key-show (dimensions)
  "Show which-key's buffer in a floating popup DIMENSIONS, (LINES . COLUMNS), big."
  (when (posframe-workable-p)
    (posframe-show which-key--buffer
                   :poshandler #'my/keys--which-key-position
                   :height (car dimensions)
                   :width (cdr dimensions)
                   :left-fringe my/keys-which-key-padding
                   :right-fringe my/keys-which-key-padding
                   :border-width 1
                   :border-color (face-background 'my/palette-border nil t)
                   :background-color (face-background 'my/palette nil t)
                   :foreground-color (face-foreground 'my/palette nil t)
                   :lines-truncate t)))

(defun my/keys--which-key-hide ()
  "Hide the which-key popup."
  (when (buffer-live-p which-key--buffer)
    (posframe-hide which-key--buffer)))

(setq which-key-popup-type 'custom
      which-key-custom-show-popup-function #'my/keys--which-key-show
      which-key-custom-hide-popup-function #'my/keys--which-key-hide
      which-key-custom-popup-max-dimensions-function
      (lambda (_width) (my/keys--which-key-dimensions))
      which-key-idle-delay 0.6
      which-key-idle-secondary-delay 0.05
      which-key-sort-order #'which-key-key-order-alpha
      which-key-add-column-padding 2
      which-key-max-description-length 40)
(which-key-mode 1)

;;;; README

(defun my/keys-markdown ()
  "Return the configuration's keys as Markdown tables, one per group."
  (let (groups)
    (dolist (entry (my/keys-entries))
      (push entry (alist-get (car entry) groups nil nil #'equal)))
    (mapconcat
     (pcase-lambda (`(,group . ,entries))
       (concat "### " group "\n\n| Key | Action |\n|---|---|\n"
               (mapconcat (pcase-lambda (`(,_ ,command ,keys))
                            (format "| %s | %s |"
                                    (mapconcat (lambda (key) (format "`%s`" (key-description key)))
                                               keys " ")
                                    (replace-regexp-in-string
                                     "|" "\\\\|" (my/keys-describe command))))
                          (reverse entries) "\n")
               "\n"))
     (reverse groups) "\n")))

(defun my/keys-update-readme ()
  "Write the configuration's keys into README.md, between its key markers."
  (interactive)
  (let ((file (expand-file-name "README.md"
                                (locate-dominating-file (locate-library "init-keys") "init.el"))))
    (with-temp-file file
      (insert-file-contents file)
      (goto-char (point-min))
      (let ((start (progn (search-forward "<!-- keys:start -->") (point)))
            (end (progn (search-forward "<!-- keys:end -->") (match-beginning 0))))
        (delete-region start end)
        (goto-char start)
        (insert "\n" (my/keys-markdown) "\n")))
    (message "Wrote the keys into %s" (abbreviate-file-name file))))

(provide 'init-keys)
;;; init-keys.el ends here
