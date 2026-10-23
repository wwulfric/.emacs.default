;;; init-welcome.el --- Project start page -*- lexical-binding: t; -*-

;;; Commentary:
;; Shown when Emacs starts without file arguments, and with C-x p w.
;; Lists recent projects (pinned first) and recent files outside them.
;; Colors come from ink-theme.el; this file owns layout and interaction.

;;; Code:

(require 'cl-lib)
(require 'recentf)
(require 'subr-x)
(require 'init-workspace)
(require 'ui-layout)

(defgroup my/welcome nil "Project start page." :group 'convenience)

(defface my/welcome-title '((t (:inherit default :weight bold :height 1.6)))
  "Start page title." :group 'my/welcome)
(defface my/welcome-subtitle '((t (:inherit shadow)))
  "Version line under the title." :group 'my/welcome)
(defface my/welcome-heading '((t (:inherit shadow :weight bold)))
  "Section headings." :group 'my/welcome)
(defface my/welcome-rule '((t (:inherit shadow)))
  "Section separator lines." :group 'my/welcome)
(defface my/welcome-name '((t (:inherit default :weight bold)))
  "Project names." :group 'my/welcome)
(defface my/welcome-path '((t (:inherit shadow)))
  "Project and file paths." :group 'my/welcome)
(defface my/welcome-meta '((t (:inherit shadow)))
  "Branch, last use and tab counts." :group 'my/welcome)
(defface my/welcome-pin '((t (:inherit warning :weight normal)))
  "Pinned project marker." :group 'my/welcome)
(defface my/welcome-unavailable '((t (:inherit shadow :slant italic)))
  "Projects whose directory cannot be found." :group 'my/welcome)
(defface my/welcome-key '((t (:inherit fixed-pitch :weight bold)))
  "Key caps in the hint grid." :group 'my/welcome)
(defface my/welcome-hint '((t (:inherit shadow)))
  "What each key in the hint grid does." :group 'my/welcome)
(defface my/welcome-row '((t (:inherit highlight)))
  "Highlight of the selected row, limited to the content column."
  :group 'my/welcome)

(defconst my/welcome-buffer-name "*Welcome*")
(defvar my/welcome-max-width 96 "Widest content column, in characters.")
(defvar my/welcome-recent-files 6 "Most recent files listed.")
(defvar my/welcome-line-height 1.5
  "Height of every line, in default line heights.
Chinese text uses a taller fallback font; a common strut keeps rows even.")

(defvar-local my/welcome-filter "" "Space-separated words every row must contain.")
(defvar-local my/welcome-entries nil "Project roots in display order.")
(defvar-local my/welcome-indent 0 "Left margin of the content column.")
(defvar-local my/welcome--row-overlay nil)

;;;; Formatting helpers

(defun my/welcome-ago (count unit)
  "Describe COUNT (a float) of UNIT ago, such as \"3 days ago\"."
  (let ((count (truncate count)))
    (format "%d %s%s ago" count unit (if (= count 1) "" "s"))))

(defun my/welcome-relative-time (time)
  "Describe float TIME relative to now."
  (if (not time) ""
    (let ((seconds (- (float-time) time)))
      (cond ((< seconds 60) "just now")
            ((< seconds 3600) (format "%d min ago" (/ seconds 60)))
            ((< seconds 86400) (my/welcome-ago (/ seconds 3600) "hour"))
            ((< seconds 172800) "yesterday")
            ((< seconds 604800) (my/welcome-ago (/ seconds 86400) "day"))
            ((< seconds 2592000) (my/welcome-ago (/ seconds 604800) "week"))
            (t (format-time-string "%Y-%m-%d" time))))))

(defun my/welcome-fit (string width)
  "Truncate STRING to WIDTH columns with an ellipsis, padding with spaces."
  (truncate-string-to-width (or string "") width nil ?\s "…"))

(defun my/welcome-fit-left (string width)
  "Like `my/welcome-fit' but keep the end of STRING, as for paths."
  (my/welcome-fit (my/ui-fit-left (or string "") width) width))

(defun my/welcome-display-path (path)
  "Return PATH abbreviated, without a trailing slash."
  (directory-file-name (abbreviate-file-name path)))

(defun my/welcome-available-p (root)
  "Return non-nil when ROOT can be opened.  Remote roots are not probed."
  (or (file-remote-p root) (file-directory-p root)))

(defun my/welcome-match-p (&rest strings)
  "Return non-nil when STRINGS contain every word of the current filter."
  (let ((haystack (downcase (string-join strings " "))))
    (seq-every-p (lambda (word) (string-search (downcase word) haystack))
                 (split-string my/welcome-filter nil t))))

;;;; Rendering

(defun my/welcome-project-row (root index content)
  "Return the row for project ROOT at 1-based INDEX in CONTENT columns."
  (let* ((meta (my/workspace-meta-get root))
         (name (or (plist-get meta :name) (my/workspace-root-name root)))
         (available (my/welcome-available-p root))
         (branch (plist-get meta :branch))
         (info (propertize (if available
                               (my/welcome-relative-time (or (plist-get meta :opened)
                                                             (plist-get meta :saved)))
                             "unavailable")
                           'face (if available 'my/welcome-meta 'my/welcome-unavailable)))
         (show-branch (>= content 78))
         (path-width (max 10 (- content 2 3 20 2 (if show-branch 16 0) 2 12))))
    (concat
     (if (plist-get meta :pinned) (propertize "★ " 'face 'my/welcome-pin) "  ")
     (propertize (if (<= index 9) (format "%d  " index) "   ") 'face 'shadow)
     (propertize (my/welcome-fit name 20)
                 'face (if available 'my/welcome-name 'my/welcome-unavailable))
     "  "
     (propertize (my/welcome-fit-left (my/welcome-display-path root) path-width)
                 'face 'my/welcome-path)
     "  "
     (if show-branch
         (propertize (my/welcome-fit (and branch (concat "⎇ " branch)) 14)
                     'face 'my/welcome-meta)
       "")
     ;; Right-align by pixels so the time ends at the rule's right edge.
     (my/ui-at-right info (+ my/welcome-indent content)))))

(defun my/welcome-recent-files (roots)
  "Return recent local files outside every project in ROOTS."
  (let ((bases (mapcar #'expand-file-name roots))
        files)
    (catch 'done
      (dolist (file recentf-list)
        (let ((expanded (expand-file-name file)))
          (unless (or (file-remote-p file)
                      (seq-some (lambda (base) (string-prefix-p base expanded)) bases))
            (push file files)
            (when (>= (length files) my/welcome-recent-files)
              (throw 'done nil))))))
    (nreverse files)))

(defun my/welcome-insert-line (indent text &optional target width)
  "Insert TEXT after INDENT spaces, padded to WIDTH columns.
TARGET makes the line selectable; only its content column reacts to the
mouse and shows the selection."
  (let ((start (point)))
    (insert (make-string indent ?\s) text)
    ;; Align by pixels: CJK glyphs are not exactly two columns wide.
    (when width
      (insert (propertize " " 'display `(space :align-to ,(+ indent width)))))
    (when target
      (put-text-property (+ start indent) (point) 'mouse-face 'highlight)
      (add-text-properties start (point) (list 'my/welcome-target target
                                               'help-echo (cdr target))))
    (insert (propertize " " 'display `(space :width 0 :height ,my/welcome-line-height))
            "\n")))

(defun my/welcome--update-row ()
  "Highlight the content column of the row at point.
A click or motion that leaves the list snaps back to the nearest row, so
one row is always selected."
  (unless (my/welcome-target)
    (let ((here (point)) before after)
      (save-excursion
        (when-let* ((match (text-property-search-backward 'my/welcome-target nil nil t)))
          (setq before (prop-match-beginning match))))
      (save-excursion
        (when-let* ((match (text-property-search-forward 'my/welcome-target nil nil t)))
          (setq after (prop-match-beginning match))))
      (when-let* ((target (cond ((and before after)
                                 (if (<= (- here before) (- after here)) before after))
                                (t (or before after)))))
        (goto-char target)
        (beginning-of-line))))
  (unless (overlayp my/welcome--row-overlay)
    (setq my/welcome--row-overlay (make-overlay (point-min) (point-min)))
    (overlay-put my/welcome--row-overlay 'face 'my/welcome-row))
  (if (my/welcome-target)
      (let ((start (+ (line-beginning-position) my/welcome-indent)))
        (move-overlay my/welcome--row-overlay start
                      (next-single-property-change start 'my/welcome-target
                                                   nil (line-end-position))))
    (delete-overlay my/welcome--row-overlay)))

(defun my/welcome-insert-centered (text)
  "Insert TEXT centered by its pixel width, which accounts for face height
and CJK glyphs that a column count gets wrong."
  (insert (propertize " " 'display
                      `(space :align-to (- center (,(/ (string-pixel-width text) 2)))))
          text
          (propertize " " 'display `(space :width 0 :height ,my/welcome-line-height))
          "\n"))

(defun my/welcome-heading-line (left right content)
  "Return a heading with LEFT and RIGHT text spread over CONTENT columns."
  (let ((right (propertize right 'face 'shadow)))
    (concat (propertize left 'face 'my/welcome-heading)
            (my/ui-at-right right (+ my/welcome-indent content)))))

(defconst my/welcome-hint-list
  '(("RET" . "Open") ("C-u RET" . "Open in new window") ("1-9" . "Quick open")
    ("o" . "Open directory…") ("/" . "Filter") ("g" . "Refresh")
    ("*" . "Pin") ("d" . "Remove from list") ("q" . "Close"))
  "Key hints under the lists, in reading order.")

(defun my/welcome-hint-lines (pairs content)
  "Lay out PAIRS of key and description as a grid in CONTENT columns.
The key caps of a column share one width, keys centered, so caps and
descriptions line up; columns are as many as fit, at most three."
  (let ((widest (lambda (strings) (apply #'max 0 (mapcar #'string-width strings))))
        rows step key-widths)
    (cl-loop for columns from 3 downto 1
             do (setq rows (seq-partition pairs columns)
                      step (/ content columns)
                      ;; A key cap is the key with a space on each side.
                      key-widths (cl-loop for column below columns
                                          for cells = (delq nil (mapcar (lambda (row) (nth column row)) rows))
                                          collect (cons (+ 2 (funcall widest (mapcar #'car cells)))
                                                        (funcall widest (mapcar #'cdr cells)))))
             until (cl-every (lambda (widths) (<= (+ (car widths) 1 (cdr widths) 2) step))
                             key-widths))
    (cl-loop for row in rows
             collect
             (cl-loop for (key . description) in row
                      for column from 0
                      for start = (+ my/welcome-indent (* column step))
                      for slot = (car (nth column key-widths))
                      for pad = (- slot (string-width key))
                      for edge = (+ start slot)
                      concat (propertize " " 'display `(space :align-to ,start))
                      concat (propertize (concat (make-string (/ pad 2) ?\s) key
                                                 (make-string (- pad (/ pad 2)) ?\s))
                                         'face 'my/welcome-key)
                      ;; Place by position, not after the cap, whose box may
                      ;; overflow its slot by a pixel or two.
                      concat (propertize " " 'display `(space :align-to ,(1+ edge)))
                      concat (propertize description 'face 'my/welcome-hint)))))

(defun my/welcome-render ()
  "Redraw the start page, keeping the selected row when possible."
  (let* ((inhibit-read-only t)
         (window (get-buffer-window (current-buffer)))
         (width (if window (window-max-chars-per-line window) 80))
         (height (if window (window-body-height window) 40))
         (content (min my/welcome-max-width (max 40 (- width 4))))
         (indent (max 2 (/ (- width content) 2)))
         (selected (get-text-property (line-beginning-position) 'my/welcome-target))
         (all (my/workspace-projects))
         (projects (seq-filter (lambda (root)
                                 (my/welcome-match-p
                                  root (or (plist-get (my/workspace-meta-get root) :name) "")))
                               all))
         (files (seq-filter #'my/welcome-match-p (my/welcome-recent-files all)))
         (body (+ 10 (max 1 (length projects)) (if files (+ 3 (length files)) 0))))
    (setq my/welcome-entries projects
          my/welcome-indent indent)
    (erase-buffer)
    (insert (make-string (max 1 (/ (- height body) 3)) ?\n))
    (let ((title "Emacs")
          (subtitle (format "%s · %d project%s" emacs-version (length all)
                            (if (= (length all) 1) "" "s"))))
      (my/welcome-insert-centered (propertize title 'face 'my/welcome-title))
      (my/welcome-insert-centered (propertize subtitle 'face 'my/welcome-subtitle)))
    (insert "\n")
    (my/welcome-insert-line
     indent (my/welcome-heading-line
             "Recent Projects"
             (if (string-empty-p my/welcome-filter) "/ Filter"
               (format "Filter: %s" my/welcome-filter))
             content))
    (my/welcome-insert-line indent (propertize (make-string content ?─) 'face 'my/welcome-rule))
    (if projects
        (cl-loop for root in projects
                 for index from 1
                 do (my/welcome-insert-line indent (my/welcome-project-row root index content)
                                            (cons 'project root) content))
      (my/welcome-insert-line
       indent (propertize (if all "No matching projects" "No projects yet. Press o to open a directory.")
                          'face 'shadow)))
    (when files
      (insert "\n")
      (my/welcome-insert-line indent (propertize "Recent Files" 'face 'my/welcome-heading))
      (dolist (file files)
        (my/welcome-insert-line indent
                                (concat "     " (propertize (my/welcome-fit-left
                                                            (abbreviate-file-name file)
                                                            (- content 5))
                                                           'face 'my/welcome-path))
                                (cons 'file file) content)))
    (insert "\n")
    (my/welcome-insert-line indent (propertize (make-string content ?─) 'face 'my/welcome-rule))
    (dolist (line (my/welcome-hint-lines my/welcome-hint-list content))
      (my/welcome-insert-line indent line))
    (goto-char (point-min))
    (let ((match (and selected (text-property-search-forward 'my/welcome-target selected t))))
      (goto-char (if match (prop-match-beginning match) (point-min)))
      (unless match (my/welcome-next 1)))
    (when window (set-window-point window (point)))
    (my/welcome--update-row)))

(defun my/welcome--on-resize (window)
  "Re-center the start page shown in WINDOW."
  (with-current-buffer (window-buffer window)
    (when (derived-mode-p 'my/welcome-mode)
      (with-selected-window window (my/welcome-render)))))

;;;; Commands

(defun my/welcome-target ()
  "Return the (KIND . VALUE) target of the current row."
  (get-text-property (line-beginning-position) 'my/welcome-target))

(defun my/welcome-next (&optional n)
  "Move to the Nth next selectable row; stay put at the last one."
  (interactive "p")
  (let ((step (if (< (or n 1) 0) -1 1))
        (target (point)))
    (dotimes (_ (abs (or n 1)))
      (save-excursion
        (goto-char target)
        (while (and (zerop (forward-line step))
                    (not (eobp))
                    (not (get-text-property (point) 'my/welcome-target))))
        (when (get-text-property (point) 'my/welcome-target)
          (setq target (point)))))
    (goto-char target)
    (beginning-of-line)))

(defun my/welcome-previous (&optional n)
  "Move to the Nth previous selectable row."
  (interactive "p")
  (my/welcome-next (- (or n 1))))

(defun my/welcome-open-target (target &optional new-frame)
  "Open TARGET, a project or a file; NEW-FRAME opens a project in a new frame."
  (pcase target
    (`(project . ,root)
     (unless (my/welcome-available-p root)
       (user-error "Directory unavailable: %s" root))
     (my/workspace-open root nil new-frame))
    (`(file . ,file) (find-file file))
    (_ (user-error "Nothing to open on this line"))))

(defun my/welcome-open (&optional new-frame)
  "Open the selected row; with NEW-FRAME open the project in a new frame."
  (interactive "P")
  (my/welcome-open-target (my/welcome-target) new-frame))

(defun my/welcome-open-nth (n)
  "Open the Nth listed project."
  (if-let* ((root (nth (1- n) my/welcome-entries)))
      (my/welcome-open-target (cons 'project root))
    (user-error "No project %d" n)))

(defun my/welcome-click (event)
  "Open the row clicked in EVENT."
  (interactive "e")
  (mouse-set-point event)
  (when (my/welcome-target) (my/welcome-open)))

(defun my/welcome-open-directory (directory)
  "Open DIRECTORY's project, or DIRECTORY itself, as a workspace."
  (interactive (list (read-directory-name "Open directory: " "~/" nil t)))
  (my/workspace-open (my/workspace-root-of directory)))

(defun my/welcome-project-at-point ()
  "Return the project root of the current row or signal a user error."
  (pcase (my/welcome-target)
    (`(project . ,root) root)
    (_ (user-error "Select a project first"))))

(defun my/welcome-toggle-pin ()
  "Pin the selected project to the top, or unpin it."
  (interactive)
  (let ((root (my/welcome-project-at-point)))
    (my/workspace-meta-update root :pinned (not (plist-get (my/workspace-meta-get root) :pinned)))
    (my/welcome-render)))

(defun my/welcome-remove ()
  "Remove the selected project from the list; its saved workspace is kept."
  (interactive)
  (let ((root (my/welcome-project-at-point)))
    (my/welcome-next 1)
    (when (equal (my/welcome-target) (cons 'project root))
      (my/welcome-previous 1))
    (my/workspace-forget root)
    (my/welcome-render)
    (message "Removed %s from the list" (my/welcome-display-path root))))

(defun my/welcome-filter ()
  "Narrow the list while typing; an empty input or C-g clears the filter."
  (interactive)
  (let ((buffer (current-buffer)))
    (condition-case nil
        (minibuffer-with-setup-hook
            (lambda ()
              (add-hook 'after-change-functions
                        (lambda (&rest _)
                          (let ((text (minibuffer-contents-no-properties)))
                            (with-current-buffer buffer
                              (setq my/welcome-filter text)
                              (my/welcome-render))))
                        nil t))
          (read-string "Filter projects: " my/welcome-filter))
      (quit (with-current-buffer buffer
              (setq my/welcome-filter "")
              (my/welcome-render))))))

(defun my/welcome-quit ()
  "Leave the start page for the previous buffer or an empty editor."
  (interactive)
  (let ((root (frame-parameter nil 'my/workspace-root)))
    (if (window-prev-buffers)
        (switch-to-prev-buffer)
      (switch-to-buffer (my/workspace-empty-buffer (or root "~/"))))
    (when (and root (fboundp 'my/sidebar-show))
      (my/sidebar-show root))))

;;;; Mode

(defvar-keymap my/welcome-mode-map
  :parent special-mode-map
  "RET" #'my/welcome-open
  "n" #'my/welcome-next
  "p" #'my/welcome-previous
  "<down>" #'my/welcome-next
  "<up>" #'my/welcome-previous
  "o" #'my/welcome-open-directory
  "/" #'my/welcome-filter
  "*" #'my/welcome-toggle-pin
  "d" #'my/welcome-remove
  "q" #'my/welcome-quit
  "<mouse-1>" #'my/welcome-click
  "<mouse-2>" #'my/welcome-click)

(dotimes (index 9)
  (let ((n (1+ index)))
    (keymap-set my/welcome-mode-map (number-to-string n)
                (lambda () (interactive) (my/welcome-open-nth n)))))

(put 'my/welcome-mode 'tab-line-exclude t)

(define-derived-mode my/welcome-mode special-mode "Welcome"
  "Start page listing recent projects and files."
  (setq-local cursor-type nil
              truncate-lines t
              mode-line-format nil
              tab-line-exclude t
              revert-buffer-function (lambda (&rest _) (my/welcome-render)))
  (when (bound-and-true-p tab-line-mode) (tab-line-mode -1))
  (add-hook 'post-command-hook #'my/welcome--update-row nil t)
  (add-hook 'window-size-change-functions #'my/welcome--on-resize nil t))

(defun my/welcome-show ()
  "Show the start page in the selected window."
  (interactive)
  (when (and (null (my/workspace-projects)) recentf-list)
    (my/workspace-seed-from-recentf))
  (let ((buffer (get-buffer-create my/welcome-buffer-name)))
    (with-current-buffer buffer
      (unless (derived-mode-p 'my/welcome-mode) (my/welcome-mode))
      (setq my/welcome-filter ""))
    (my/workspace--hide-sidebar)
    (switch-to-buffer buffer)
    (my/welcome-render)
    buffer))

(keymap-set project-prefix-map "w" #'my/welcome-show)

;;;; Empty editor

;; A project with no open file shows what JetBrains' empty editor does: a
;; centered list of ways to open something, with this config's keys.

(defconst my/welcome-empty-actions
  '(("Search Everywhere" . my/search)
    ("Go to File" . my/search-files)
    ("Recent Files" . consult-buffer)
    ("Find in Files" . my/search-text)
    ("Find Action" . my/search-commands)
    ("Project View" . my/sidebar-toggle)
    ("Switch Project" . project-switch-project))
  "Rows of the empty editor as (LABEL . COMMAND); unbound commands are left out.")

(defconst my/welcome-empty-gap 24 "Pixels between a label and its keys.")

(defconst my/welcome-key-glyphs
  '(("C" . "⌃") ("M" . "⌥") ("S" . "⇧") ("s" . "⌘"))
  "Modifier glyphs, in the order macOS writes them.")

(defun my/welcome-key-label (keys)
  "Describe KEYS the way macOS menus do, such as ⇧⌘O."
  (mapconcat
   (lambda (chord)
     (let ((mods '()))
       (while (string-match "\\`\\([CMSs]\\)-\\(.+\\)" chord)
         (push (match-string 1 chord) mods)
         (setq chord (match-string 2 chord)))
       (setq chord (string-trim chord "<" ">"))
       ;; An upper-case letter is typed with Shift.
       (when (and (= (length chord) 1) (not (equal (upcase chord) (downcase chord)))
                  (equal chord (upcase chord)))
         (push "S" mods))
       (concat (mapconcat (lambda (glyph) (if (member (car glyph) mods) (cdr glyph) ""))
                          my/welcome-key-glyphs "")
               (pcase chord
                 ("RET" "↩") ("return" "↩") ("TAB" "⇥") ("SPC" "Space")
                 ((pred (string-match-p "\\`f[0-9]+\\'")) (upcase chord))
                 (_ (if (= (length chord) 1) (upcase chord) chord))))))
   (split-string (key-description keys))
   " "))

(defun my/welcome-best-key (command)
  "Return COMMAND's shortest binding, preferring one with Command (super)."
  (car (sort (where-is-internal command nil nil t)
             (lambda (a b)
               (let ((sa (memq 'super (event-modifiers (aref a 0))))
                     (sb (memq 'super (event-modifiers (aref b 0)))))
                 (if (eq (not sa) (not sb)) (< (length a) (length b)) sa))))))

(defun my/welcome-empty-rows ()
  "Return the empty editor's rows as (LABEL . KEYS) strings."
  (cl-loop for (label . command) in my/welcome-empty-actions
           for keys = (and (fboundp command) (my/welcome-best-key command))
           when keys
           collect (cons (propertize label 'face 'my/welcome-hint)
                         (my/ui-fit-tall-glyphs
                          (propertize (my/welcome-key-label keys) 'face 'my/welcome-key)))))

(defun my/welcome-empty-render ()
  "Draw the empty editor's rows centered in its window."
  (let* ((inhibit-read-only t)
         (window (get-buffer-window (current-buffer)))
         (height (if window (window-body-height window) 30))
         (rows (my/welcome-empty-rows))
         (pixels (lambda (strings)
                   (apply #'max 0 (mapcar (lambda (string) (string-pixel-width string (current-buffer)))
                                          strings))))
         (labels (funcall pixels (mapcar #'car rows)))
         (keys (funcall pixels (mapcar #'cdr rows)))
         (half (/ (+ labels my/welcome-empty-gap keys) 2))
         (strut (propertize " " 'display `(space :width 0 :height ,my/welcome-line-height))))
    (erase-buffer)
    (insert (make-string (max 1 (floor (- height (* (length rows) my/welcome-line-height)) 2))
                         ?\n))
    (pcase-dolist (`(,label . ,key) rows)
      (insert (propertize " " 'display `(space :align-to (- center (,half))))
              label
              (propertize " " 'display `(space :align-to (+ center (,(- (+ labels my/welcome-empty-gap) half)))))
              key strut "\n"))
    (goto-char (point-min))))

(defun my/welcome-empty--on-resize (window)
  "Re-center the empty editor shown in WINDOW."
  (with-current-buffer (window-buffer window)
    (when (derived-mode-p 'my/welcome-empty-mode)
      (with-selected-window window (my/welcome-empty-render)))))

(put 'my/welcome-empty-mode 'tab-line-exclude t)

(define-derived-mode my/welcome-empty-mode special-mode "Empty"
  "What an editor window shows when its project has no open file."
  (setq-local cursor-type nil
              truncate-lines t
              mode-line-format nil
              tab-line-exclude t
              revert-buffer-function (lambda (&rest _) (my/welcome-empty-render)))
  (when (bound-and-true-p tab-line-mode) (tab-line-mode -1))
  (add-hook 'window-size-change-functions #'my/welcome-empty--on-resize nil t))

(defun my/welcome-empty-buffer (directory &optional except)
  "Return the empty editor for DIRECTORY, other than the buffer EXCEPT.
Its name starts with a space, so buffer lists and tab strips leave it out."
  (let* ((directory (file-name-as-directory (expand-file-name directory)))
         (buffer (or (seq-find (lambda (buffer)
                                 (and (not (eq buffer except))
                                      (eq (buffer-local-value 'major-mode buffer)
                                          'my/welcome-empty-mode)
                                      (equal (buffer-local-value 'default-directory buffer)
                                             directory)))
                               (buffer-list))
                     (generate-new-buffer
                      (format " *Empty Editor: %s*" (abbreviate-file-name directory))))))
    (with-current-buffer buffer
      (unless (derived-mode-p 'my/welcome-empty-mode)
        (my/welcome-empty-mode)
        (setq default-directory directory))
      (my/welcome-empty-render))
    buffer))

(provide 'init-welcome)
;;; init-welcome.el ends here
