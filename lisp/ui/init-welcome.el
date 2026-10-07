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
  "Key names in the hint line." :group 'my/welcome)
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

(defun my/welcome-relative-time (time)
  "Describe float TIME relative to now."
  (if (not time) ""
    (let ((seconds (- (float-time) time)))
      (cond ((< seconds 60) "刚刚")
            ((< seconds 3600) (format "%d 分钟前" (/ seconds 60)))
            ((< seconds 86400) (format "%d 小时前" (/ seconds 3600)))
            ((< seconds 172800) "昨天")
            ((< seconds 604800) (format "%d 天前" (/ seconds 86400)))
            ((< seconds 2592000) (format "%d 周前" (/ seconds 604800)))
            (t (format-time-string "%Y-%m-%d" time))))))

(defun my/welcome-fit (string width)
  "Truncate STRING to WIDTH columns with an ellipsis, padding with spaces."
  (truncate-string-to-width (or string "") width nil ?\s "…"))

(defun my/welcome-fit-left (string width)
  "Like `my/welcome-fit' but keep the end of STRING, as for paths."
  (let ((columns (string-width string)))
    (my/welcome-fit (if (<= columns width) string
                      (concat "…" (truncate-string-to-width
                                   string columns (- columns (1- width)))))
                    width)))

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
                             "不可用")
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
     (propertize " " 'display
                 `(space :align-to (- ,(+ my/welcome-indent content)
                                      (,(string-pixel-width info)))))
     info)))

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
            (propertize " " 'display
                        `(space :align-to (- ,(+ my/welcome-indent content)
                                             (,(string-pixel-width right)))))
            right)))

(defun my/welcome-hints (pairs)
  "Format PAIRS of key and description as a hint line."
  (mapconcat (lambda (pair)
               (concat (propertize (car pair) 'face 'my/welcome-key) " "
                       (propertize (cdr pair) 'face 'shadow)))
             pairs "   "))

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
         (body (+ 9 (max 1 (length projects)) (if files (+ 3 (length files)) 0))))
    (setq my/welcome-entries projects
          my/welcome-indent indent)
    (erase-buffer)
    (insert (make-string (max 1 (/ (- height body) 3)) ?\n))
    (let ((title "Emacs")
          (subtitle (format "%s · %d 个项目" emacs-version (length all))))
      (my/welcome-insert-centered (propertize title 'face 'my/welcome-title))
      (my/welcome-insert-centered (propertize subtitle 'face 'my/welcome-subtitle)))
    (insert "\n")
    (my/welcome-insert-line
     indent (my/welcome-heading-line
             "最近项目"
             (if (string-empty-p my/welcome-filter) "/ 过滤"
               (format "过滤：%s" my/welcome-filter))
             content))
    (my/welcome-insert-line indent (propertize (make-string content ?─) 'face 'my/welcome-rule))
    (if projects
        (cl-loop for root in projects
                 for index from 1
                 do (my/welcome-insert-line indent (my/welcome-project-row root index content)
                                            (cons 'project root) content))
      (my/welcome-insert-line
       indent (propertize (if all "没有匹配的项目" "还没有项目，按 o 打开一个目录")
                          'face 'shadow)))
    (when files
      (insert "\n")
      (my/welcome-insert-line indent (propertize "最近文件" 'face 'my/welcome-heading))
      (dolist (file files)
        (my/welcome-insert-line indent
                                (concat "     " (propertize (my/welcome-fit-left
                                                            (abbreviate-file-name file)
                                                            (- content 5))
                                                           'face 'my/welcome-path))
                                (cons 'file file) content)))
    (insert "\n")
    (my/welcome-insert-line indent (propertize (make-string content ?─) 'face 'my/welcome-rule))
    (my/welcome-insert-line indent (my/welcome-hints '(("RET" . "打开") ("1-9" . "快速打开")
                                                       ("C-u RET" . "新窗口打开")
                                                       ("o" . "打开目录…"))))
    (my/welcome-insert-line indent (my/welcome-hints '(("*" . "置顶") ("d" . "从列表移除")
                                                       ("/" . "过滤") ("g" . "刷新")
                                                       ("q" . "关闭"))))
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
       (user-error "目录不可用：%s" root))
     (my/workspace-open root nil new-frame))
    (`(file . ,file) (find-file file))
    (_ (user-error "这一行没有可打开的内容"))))

(defun my/welcome-open (&optional new-frame)
  "Open the selected row; with NEW-FRAME open the project in a new frame."
  (interactive "P")
  (my/welcome-open-target (my/welcome-target) new-frame))

(defun my/welcome-open-nth (n)
  "Open the Nth listed project."
  (if-let* ((root (nth (1- n) my/welcome-entries)))
      (my/welcome-open-target (cons 'project root))
    (user-error "没有第 %d 个项目" n)))

(defun my/welcome-click (event)
  "Open the row clicked in EVENT."
  (interactive "e")
  (mouse-set-point event)
  (when (my/welcome-target) (my/welcome-open)))

(defun my/welcome-open-directory (directory)
  "Open DIRECTORY's project, or DIRECTORY itself, as a workspace."
  (interactive (list (read-directory-name "打开目录：" "~/" nil t)))
  (my/workspace-open (my/workspace-root-of directory)))

(defun my/welcome-project-at-point ()
  "Return the project root of the current row or signal a user error."
  (pcase (my/welcome-target)
    (`(project . ,root) root)
    (_ (user-error "请先选中一个项目"))))

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
    (message "已从列表移除 %s" (my/welcome-display-path root))))

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
          (read-string "过滤项目：" my/welcome-filter))
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
    (when (and root (fboundp 'my/dirvish-show))
      (my/dirvish-show root))))

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

(provide 'init-welcome)
;;; init-welcome.el ends here
