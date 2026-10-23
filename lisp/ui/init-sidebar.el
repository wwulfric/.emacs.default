;;; init-sidebar.el --- Project file sidebar on plain Dired -*- lexical-binding: t; -*-

;;; Commentary:
;; The sidebar is an ordinary Dired buffer in a left side window, with
;; `my/sidebar-mode' on top: folders expand in place, rows show New UI
;; chevrons and icons, and the header holds a tool window's toolbar.
;; Keep project navigation separate from lsp-bridge's language server roots.

;;; Code:

(require 'cl-lib)
(require 'project)
(require 'dired)
(require 'face-remap)
(require 'mwheel)
(require 'ui-layout)

;;;; Listing

;; Only GNU ls sorts with options such as --sort and lists folders first.
;; macOS ships BSD ls, so use coreutils' gls when it is installed
;; (brew install coreutils).  The shell's PATH is imported after this file
;; loads, hence the Homebrew locations.
(defvar my/sidebar-gnu-ls nil
  "Non-nil when `insert-directory-program' accepts GNU ls options.")
(setq my/sidebar-gnu-ls
      (pcase system-type
        ('gnu/linux t)
        ('darwin
         (when-let* ((gls (or (executable-find "gls")
                              (seq-find #'file-executable-p
                                        '("/opt/homebrew/bin/gls"
                                          "/usr/local/bin/gls")))))
           (setq insert-directory-program gls)
           t))))
;; BSD ls also lacks --dired.
(setq dired-use-ls-dired my/sidebar-gnu-ls)

;; Show dotfiles, but omit the synthetic . and .. entries.
(setq dired-listing-switches
      (if my/sidebar-gnu-ls "-lA --group-directories-first" "-lA"))

(defun my/sidebar-no-line-numbers ()
  "Disable line numbers before a directory buffer is first displayed."
  (display-line-numbers-mode -1))
(add-hook 'dired-mode-hook #'my/sidebar-no-line-numbers)

;;;; Mode

(defface my/sidebar-file-name
  '((t (:inherit my/ui-font :height 1.0)))
  "Proportional sidebar text." :group 'dired)

(defvar-local my/sidebar-font-face-cookie nil)
(defvar-local my/sidebar-header-face-cookie nil)
(defvar-local my/sidebar-hl nil
  "Overlays highlighting the selected rows; see Selection below.")
(defvar-local my/sidebar-hl-rows nil
  "Name overlays of the rows last drawn in a selection face.")
(defvar-local my/sidebar-region-face-cookie nil)
(defvar-local my/sidebar-compact-ends nil
  "Last folders of the compacted rows listed; see Packages below.")

(defun my/sidebar-hide-header ()
  "Hide Dired's directory line; the sidebar's header names the project."
  (save-excursion
    (goto-char (point-min))
    (when (dired-get-subdir)
      (with-silent-modifications
        (put-text-property (point) (line-beginning-position 2) 'invisible t)))))

(defvar my/sidebar-mode-map (make-sparse-keymap)
  "Keys of the sidebar, ahead of Dired's.")

(define-minor-mode my/sidebar-mode
  "Show a Dired buffer as the frame's project sidebar."
  :keymap my/sidebar-mode-map
  (if my/sidebar-mode
      (progn
        (dired-hide-details-mode 1)
        ;; Follow the buffer's normal text face, including after theme changes.
        (face-remap-set-base 'dired-directory 'default)
        (unless my/sidebar-font-face-cookie
          (setq my/sidebar-font-face-cookie
                (face-remap-add-relative 'default 'my/sidebar-file-name)))
        ;; Emacs 31 splits the spacing above and below, centering the text;
        ;; older versions put it all below.
        (setq-local line-spacing
                    (if (< emacs-major-version 31) 0.35 '(0.175 . 0.175)))
        ;; A row a pixel too wide is clipped, never wrapped.
        (setq-local truncate-lines t)
        ;; Shortened names end in an ellipsis drawn in their own face.
        (add-to-invisibility-spec '(my/sidebar-tail . t))
        ;; A JVM type's row hides its file's extension.
        (add-to-invisibility-spec 'my/sidebar-ext)
        (setq-local buffer-display-table
                    (let ((table (make-display-table)))
                      (set-display-table-slot table 'selective-display
                                              (vector (make-glyph-code ?…)))
                      table))
        ;; The sidebar is no editor buffer, so it gets no tab.
        (setq-local tab-line-exclude t)
        (when (bound-and-true-p tab-line-mode) (tab-line-mode -1))
        ;; New files go into the folder of the line at point.
        (setq-local dired-create-empty-file-in-current-directory t)
        (setq-local revert-buffer-function #'my/sidebar-tree-revert)
        ;; Dired listed the buffer before this mode was on.
        (my/sidebar-readin)
        (add-hook 'dired-after-readin-hook #'my/sidebar-readin nil t)
        (add-hook 'window-buffer-change-functions #'my/sidebar-rows-fit nil t)
        (add-hook 'window-size-change-functions #'my/sidebar-rows-fit nil t)
        (setq-local cursor-type nil)
        (setq-local scroll-preserve-screen-position nil)
        ;; Keep direct touchpad pixel scrolling; avoid queued wheel animations.
        (setq-local pixel-scroll-precision-interpolate-mice nil
                    pixel-scroll-precision-large-scroll-height nil
                    pixel-scroll-precision-use-momentum nil)
        (setq-local header-line-format '(:eval (my/sidebar-header))
                    mode-line-format '(:eval (my/sidebar-status-line)))
        ;; Share tab-line's font metrics and vertical padding.
        (unless my/sidebar-header-face-cookie
          (setq my/sidebar-header-face-cookie
                (face-remap-add-relative 'header-line
                                         :inherit 'tab-line :height 1.0 :box nil)))
        (add-hook 'post-command-hook #'my/sidebar-after-command nil t)
        ;; A region selects whole rows; see `my/sidebar-select'.
        (unless my/sidebar-region-face-cookie
          (setq my/sidebar-region-face-cookie
                (face-remap-add-relative 'region 'my/sidebar-hl-line)))
        (add-hook 'activate-mark-hook #'my/sidebar-select nil t)
        (add-hook 'deactivate-mark-hook #'my/sidebar-select nil t)
        (add-hook 'window-selection-change-functions #'my/sidebar-select nil t))
    (face-remap-reset-base 'dired-directory)
    (when my/sidebar-font-face-cookie
      (face-remap-remove-relative my/sidebar-font-face-cookie)
      (setq my/sidebar-font-face-cookie nil))
    (kill-local-variable 'line-spacing)
    (kill-local-variable 'truncate-lines)
    (remove-from-invisibility-spec '(my/sidebar-tail . t))
    (remove-from-invisibility-spec 'my/sidebar-ext)
    (kill-local-variable 'buffer-display-table)
    (kill-local-variable 'dired-create-empty-file-in-current-directory)
    (setq-local revert-buffer-function #'dired-revert)
    (remove-overlays (point-min) (point-max) 'my/sidebar-row t)
    (mapc #'delete-overlay my/sidebar-hl)
    (setq my/sidebar-hl nil)
    (when my/sidebar-region-face-cookie
      (face-remap-remove-relative my/sidebar-region-face-cookie)
      (setq my/sidebar-region-face-cookie nil))
    (remove-hook 'activate-mark-hook #'my/sidebar-select t)
    (remove-hook 'deactivate-mark-hook #'my/sidebar-select t)
    (kill-local-variable 'cursor-type)
    (kill-local-variable 'header-line-format)
    (kill-local-variable 'mode-line-format)
    (when my/sidebar-header-face-cookie
      (face-remap-remove-relative my/sidebar-header-face-cookie)
      (setq my/sidebar-header-face-cookie nil))
    (remove-hook 'post-command-hook #'my/sidebar-after-command t)
    (remove-hook 'window-selection-change-functions #'my/sidebar-select t)
    (remove-hook 'dired-after-readin-hook #'my/sidebar-readin t)
    (remove-hook 'window-buffer-change-functions #'my/sidebar-rows-fit t)
    (remove-hook 'window-size-change-functions #'my/sidebar-rows-fit t)))

(defun my/sidebar-readin ()
  "Prepare the lines Dired has just listed."
  (my/sidebar-hide-header)
  (setq my/sidebar-compact-ends nil)
  (with-silent-modifications
    (my/sidebar-compact (point-min) (point-max) default-directory))
  (my/sidebar-rows-draw (point-min) (point-max))
  (my/sidebar-tree-restore)
  (my/sidebar-snap)
  (my/sidebar-select))

(defun my/sidebar-buffer (directory)
  "Return the sidebar buffer listing DIRECTORY, creating it if needed.
It is a Dired buffer of its own, so `dired' never hands it to an editor."
  (let ((directory (file-name-as-directory (expand-file-name directory))))
    (or (seq-find (lambda (buffer)
                    (with-current-buffer buffer
                      (and my/sidebar-mode (derived-mode-p 'dired-mode)
                           ;; Dired abbreviates its `default-directory'.
                           (equal (expand-file-name default-directory) directory))))
                  (buffer-list))
        (let ((buffer (let (dired-buffers) (dired-noselect directory))))
          ;; Dired advertised the buffer inside the binding above; advertise it
          ;; for real so file operations still update the listing.
          (push (cons directory buffer) dired-buffers)
          (with-current-buffer buffer
            (rename-buffer (format " *sidebar: %s*" (abbreviate-file-name directory))
                           t)
            (my/sidebar-mode 1))
          buffer))))

(defun my/sidebar-dired-buffers ()
  "Return `dired-buffers' without the sidebars."
  (seq-remove (lambda (entry)
                (and (buffer-live-p (cdr entry))
                     (buffer-local-value 'my/sidebar-mode (cdr entry))))
              dired-buffers))

(defun my/sidebar-skip-in-dired (find &rest args)
  "Call FIND with ARGS while sidebar buffers are hidden from it.
Visiting a directory in an editor then makes a Dired buffer of its own."
  (let ((dired-buffers (my/sidebar-dired-buffers)))
    (apply find args)))
(advice-add 'dired-find-buffer-nocreate :around #'my/sidebar-skip-in-dired)

;;;; Tree

;; An expanded folder's entries follow its line, under an overlay that
;; records the folder and its depth.  Dired itself still sees one flat
;; directory, so the advice below tells it which folder a line belongs to.

(defconst my/sidebar-indent 16
  "Pixels each folder level indents its entries.")

(defvar my/sidebar-expand-limit 30
  "Most folders one `my/sidebar-tree-expand-all' lists; each starts a process.")

(defvar-local my/sidebar-tree-dirs nil
  "This sidebar's expanded folders, as directory file names.")

(defvar-local my/sidebar-tree-target nil
  "File to select after the next relisting, from a file operation.")

(defvar-local my/sidebar-tree-pending nil
  "Non-nil while a relisting of this sidebar is scheduled.")

(defun my/sidebar-tree-node (&optional position)
  "Return the innermost expanded folder's overlay at POSITION, or nil."
  (let (node)
    (dolist (overlay (overlays-at (or position (point))))
      (when-let* ((depth (overlay-get overlay 'my/sidebar-depth)))
        (when (or (not node) (> depth (overlay-get node 'my/sidebar-depth)))
          (setq node overlay))))
    node))

(defun my/sidebar-tree-depth (&optional position)
  "Return how many folders deep the line at POSITION is listed."
  (if-let* ((node (my/sidebar-tree-node position)))
      (overlay-get node 'my/sidebar-depth)
    0))

(defun my/sidebar-tree-expanded-p (&optional directory)
  "Return non-nil if DIRECTORY, by default the one at point, is expanded."
  (when-let* ((directory (or directory (dired-get-filename nil t))))
    (member directory my/sidebar-tree-dirs)))

(defun my/sidebar-tree-directory (current &optional localp)
  "Return the folder of the line at point, inside expanded folders too.
CURRENT is `dired-current-directory', called with LOCALP elsewhere."
  (if-let* ((node (and my/sidebar-mode (my/sidebar-tree-node))))
      (let ((directory (file-name-as-directory (overlay-get node 'my/sidebar-dir))))
        (if localp (dired-make-relative directory default-directory) directory))
    (funcall current localp)))
;; `dired-get-filename' builds every name from this.
(advice-add 'dired-current-directory :around #'my/sidebar-tree-directory)

(defun my/sidebar-tree-subdir (subdir)
  "Call SUBDIR, `dired-get-subdir', unless point is in an expanded folder.
No line there heads a Dired subdirectory."
  (unless (and my/sidebar-mode (my/sidebar-tree-node))
    (funcall subdir)))
(advice-add 'dired-get-subdir :around #'my/sidebar-tree-subdir)

(defun my/sidebar-tree-goto (file)
  "Move to the line of FILE if it is listed; return the name's position."
  (let ((file (directory-file-name (expand-file-name file)))
        found)
    (save-excursion
      (goto-char (point-min))
      (while (and (not found) (zerop (forward-line 1)))
        (when (equal (dired-get-filename nil t) file)
          (setq found (dired-move-to-filename)))))
    (when found (goto-char found))))

(defun my/sidebar-tree-goto-file (goto file)
  "Call GOTO for FILE, or find FILE inside expanded folders in a sidebar."
  (if my/sidebar-mode
      (my/sidebar-tree-goto file)
    (funcall goto file)))
;; Dired finds lines by name for marks, deletions and relisting.
(advice-add 'dired-goto-file :around #'my/sidebar-tree-goto-file)

(defun my/sidebar-tree-listing (directory switches)
  "Return the Dired lines of DIRECTORY listed with SWITCHES."
  (with-temp-buffer
    (dired-insert-directory (file-name-as-directory directory) switches)
    (goto-char (point-min))
    (when (looking-at-p "  total used in directory")
      (delete-line))
    (buffer-string)))

(defun my/sidebar-tree-expand ()
  "List the folder at point under its line."
  (let ((directory (dired-get-filename nil t)))
    (unless (and directory (file-directory-p directory))
      (user-error "Not a folder"))
    (unless (file-accessible-directory-p directory)
      (user-error "Cannot open %s" (abbreviate-file-name directory)))
    (unless (my/sidebar-tree-expanded-p directory)
      (let ((listing (my/sidebar-tree-listing directory dired-actual-switches))
            (depth (1+ (my/sidebar-tree-depth))))
        (save-excursion
          (forward-line 1)
          (let ((start (point)))
            (with-silent-modifications
              (insert listing)
              ;; Hideable details and hover faces need a Dired buffer.
              (dired-insert-set-properties start (point))
              (my/sidebar-compact start (point) directory))
            (unless (= start (point))
              ;; Rear-advance keeps a nested listing inserted at the end inside.
              (let ((node (make-overlay start (point) nil nil t)))
                (overlay-put node 'my/sidebar-dir directory)
                (overlay-put node 'my/sidebar-depth depth)
                (overlay-put node 'priority depth)
                (overlay-put node 'evaporate t)
                (overlay-put node 'line-prefix
                             (propertize " " 'display
                                         `(space :width (,(* depth my/sidebar-indent)))))
                (my/sidebar-rows-draw start (point))))))
        (push directory my/sidebar-tree-dirs)
        ;; The folder's chevron now points down.
        (my/sidebar-rows-draw (pos-bol) (pos-eol))))))

(defun my/sidebar-tree-collapse ()
  "Remove the listing under the folder at point."
  (let* ((directory (dired-get-filename nil t))
         (inside (file-name-as-directory directory)))
    (when-let* ((node (seq-find (lambda (overlay)
                                  (equal (overlay-get overlay 'my/sidebar-dir) directory))
                                (overlays-at (line-beginning-position 2)))))
      (with-silent-modifications
        (delete-region (overlay-start node) (overlay-end node))))
    (setq my/sidebar-tree-dirs
          (seq-remove (lambda (dir)
                        (or (equal dir directory) (string-prefix-p inside dir)))
                      my/sidebar-tree-dirs))
    (my/sidebar-rows-draw (pos-bol) (pos-eol))))

(defun my/sidebar-tree-toggle ()
  "Expand or collapse the folder at point."
  (interactive)
  (if (my/sidebar-tree-expanded-p)
      (my/sidebar-tree-collapse)
    (my/sidebar-tree-expand)))

(defun my/sidebar-tree-clear ()
  "Collapse every folder."
  (interactive)
  (with-silent-modifications
    (dolist (overlay (overlays-in (point-min) (point-max)))
      (when (eql (overlay-get overlay 'my/sidebar-depth) 1)
        (delete-region (overlay-start overlay) (overlay-end overlay)))))
  (setq my/sidebar-tree-dirs nil)
  ;; Every chevron points right again.
  (my/sidebar-rows-draw (point-min) (point-max))
  (goto-char (point-min))
  (dired-goto-next-file))

(defun my/sidebar-tree-reveal (file)
  "Expand the folders down to FILE and move to its line.
Return the name's position, or nil when FILE is not in the sidebar."
  (let ((root (expand-file-name default-directory))
        (file (directory-file-name (expand-file-name file))))
    (when (and (string-prefix-p root file) (not (equal (directory-file-name root) file)))
      (let ((directory root))
        (catch 'hidden
          (dolist (part (butlast (split-string (substring file (length root)) "/" t)))
            (setq directory (expand-file-name part directory))
            ;; A compacted row lists only the last folder of its chain.
            (unless (or (my/sidebar-tree-expanded-p directory)
                        (not (my/sidebar-tree-goto directory))
                        (ignore-errors (my/sidebar-tree-expand) t))
              (throw 'hidden nil)))
          (my/sidebar-tree-goto file))))))

(defun my/sidebar-tree-restore ()
  "Expand the folders again that were expanded before Dired relisted."
  (let ((dirs (sort (copy-sequence my/sidebar-tree-dirs)
                    (lambda (a b) (< (length a) (length b))))))
    (setq my/sidebar-tree-dirs nil)
    (save-excursion
      (dolist (directory dirs)
        (when (my/sidebar-tree-reveal directory)
          (ignore-errors (my/sidebar-tree-expand)))))))

(defun my/sidebar-tree-revert (&rest args)
  "Relist the sidebar, with ARGS for `dired-revert'.
Keep its expanded folders, marks and each window's line; a file operation
selects the file it touched instead."
  (let ((marks (dired-remember-marks (point-min) (point-max)))
        (places (mapcar (lambda (window)
                          (save-excursion
                            (goto-char (window-point window))
                            (list window (dired-get-filename nil t)
                                  (line-number-at-pos))))
                        (get-buffer-window-list nil nil t)))
        (target my/sidebar-tree-target))
    (setq my/sidebar-tree-target nil)
    (apply #'dired-revert args)
    ;; Dired marks before its readin hook expands the folders again.
    (with-silent-modifications (dired-mark-remembered marks))
    (pcase-dolist (`(,window ,file ,line) places)
      (unless (and target (my/sidebar-tree-goto target))
        (unless (and file (my/sidebar-tree-goto file))
          (goto-char (point-min))
          (forward-line (1- line))
          (dired-move-to-filename)))
      (set-window-point window (point))
      (my/sidebar-select window))))

(defun my/sidebar-tree-refresh (buffer)
  "Relist sidebar BUFFER if it is still live."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq my/sidebar-tree-pending nil)
      (revert-buffer))))

(defun my/sidebar-tree-follow-change (update directory file &rest args)
  "Call UPDATE for DIRECTORY, FILE and ARGS outside the sidebars.
Then relist the sidebars that list DIRECTORY: Dired edits listings line
by line, unaware of expanded folders."
  (prog1 (let ((dired-buffers (my/sidebar-dired-buffers)))
           (apply update directory file args))
    (let ((folder (directory-file-name (expand-file-name directory))))
      (dolist (buffer (buffer-list))
        (with-current-buffer buffer
          (when (and my/sidebar-mode
                     (or (equal folder (directory-file-name
                                        (expand-file-name default-directory)))
                         (member folder my/sidebar-tree-dirs)
                         ;; A folder inside a compacted row's chain.
                         (let ((inside (file-name-as-directory folder)))
                           (and (string-prefix-p (expand-file-name default-directory)
                                                 inside)
                                (seq-some (lambda (dir) (string-prefix-p inside dir))
                                          (append my/sidebar-tree-dirs
                                                  my/sidebar-compact-ends))))))
            (when file
              (setq my/sidebar-tree-target (expand-file-name file directory)))
            (unless my/sidebar-tree-pending
              (setq my/sidebar-tree-pending t)
              (run-at-time 0 nil #'my/sidebar-tree-refresh buffer))))))))
;; Dired adds, removes and relists entries in every listing through this.
(advice-add 'dired-fun-in-all-buffers :around #'my/sidebar-tree-follow-change)

(defun my/sidebar-tree-expand-all ()
  "Expand the folder at point and its subfolders, up to a limit."
  (interactive)
  (let ((budget my/sidebar-expand-limit))
    (cl-labels
        ((directory-p ()
           (when-let* ((file (dired-get-filename nil t)))
             ;; A symlink may lead back into the tree being expanded.
             (and (file-directory-p file) (not (file-symlink-p file)))))
         (expand ()
           (let ((depth (my/sidebar-tree-depth)))
             (unless (my/sidebar-tree-expanded-p)
               (condition-case nil
                   (progn (my/sidebar-tree-expand) (cl-decf budget))
                 (error nil)))
             (save-excursion
               (while (and (> budget 0)
                           (zerop (forward-line 1))
                           (> (my/sidebar-tree-depth) depth))
                 (when (and (= (my/sidebar-tree-depth) (1+ depth))
                            (directory-p))
                   (expand)))))))
      (if (directory-p) (expand) (message "Select a folder first")))
    (when (<= budget 0)
      (message "Expanded %d folders; deeper ones stay collapsed"
               my/sidebar-expand-limit))))

(defun my/sidebar-locate ()
  "Select the editor's file in the sidebar, showing the sidebar if needed.
From the sidebar, that is the last editor window's file."
  (interactive)
  (let* ((editor (if my/sidebar-mode (get-mru-window nil nil t) (selected-window)))
         (file (and editor (buffer-file-name (window-buffer editor)))))
    (if (not file)
        (message "No file is open in the editor")
      (unless (my/sidebar-window)
        (with-selected-window editor (my/sidebar-show)))
      (let ((window (my/sidebar-window)))
        (unless (with-selected-window window (my/sidebar-tree-reveal file))
          (message "%s is not in %s" (file-name-nondirectory file)
                   (abbreviate-file-name
                    (with-current-buffer (window-buffer window) default-directory))))
        (my/sidebar-select window)))))

;;;; Packages

;; As in JetBrains' Project view, folders under a JVM source root are
;; packages, and a chain of folders that each hold just one folder shows
;; as one row, `com.github.wolray.seq'.  The row's buffer text is the
;; chain's path, `com/github/wolray/seq', so Dired and the tree take the
;; row for the chain's last folder; only its drawing shows dots.

(defcustom my/sidebar-compact 'packages
  "Which chains of folders holding just one folder show as one row.
`packages' compacts packages under JVM source roots, as JetBrains'
Compact Middle Packages does; t compacts any folders but source roots;
nil lists every folder on a row of its own.  Relist the sidebar with
\\[revert-buffer] after changing it."
  :type '(choice (const :tag "Packages" packages)
                 (const :tag "All folders" t)
                 (const :tag "None" nil))
  :group 'dired)

(defconst my/sidebar-root-regexp
  "\\(?:\\`\\|/\\)src/\\([^/]+\\)/\\(java\\|kotlin\\|groovy\\|scala\\|resources\\)\\'"
  "Source roots of Maven and Gradle layouts, relative to the sidebar's folder.")

(defconst my/sidebar-package-regexp
  "\\(?:\\`\\|/\\)src/[^/]+/\\(?:java\\|kotlin\\|groovy\\|scala\\)/."
  "Files and folders inside a code root, relative to the sidebar's folder.")

(defun my/sidebar-relative (file)
  "Return FILE relative to the sidebar's folder, or nil outside it.
Remote folders return nil too: each check would cost a round trip."
  (let ((root (expand-file-name default-directory)))
    (and (not (file-remote-p root))
         (string-prefix-p root file)
         (substring file (length root)))))

(defun my/sidebar-root-icon (directory)
  "Return the icon of DIRECTORY if it is a source root, else nil."
  (when-let* ((relative (my/sidebar-relative directory))
              ((string-match my/sidebar-root-regexp relative)))
    (let ((test (string-match-p "[tT]est" (match-string 1 relative))))
      (if (equal (match-string 2 relative) "resources")
          (if test "nodes/testResourcesRoot" "nodes/resourcesRoot")
        (if test "nodes/testRoot" "nodes/sourceRoot")))))

(defun my/sidebar-package-p (file)
  "Return non-nil if FILE lies inside a code root; a folder there is a package."
  (when-let* ((relative (my/sidebar-relative file)))
    (string-match-p my/sidebar-package-regexp relative)))

(defun my/sidebar-folder-icon (directory)
  "Return the icon of DIRECTORY if it is a root, package or module, else nil."
  (or (my/sidebar-root-icon directory)
      (and (my/sidebar-package-p directory) "nodes/package")
      ;; A Maven or Gradle module.
      (and (my/sidebar-relative directory)
           (seq-some (lambda (build) (file-exists-p (expand-file-name build directory)))
                     '("pom.xml" "build.gradle" "build.gradle.kts"))
           "nodes/module")))

(defun my/sidebar-compact-chain (directory)
  "Return the folders DIRECTORY's row also shows, as names in order.
They are the one folder DIRECTORY holds and nothing else, the one folder
that holds, and so on; a source root or symbolic link ends the chain."
  (let (chain done)
    (while (not done)
      (let* ((entries (remove ".DS_Store"
                              (ignore-errors
                                (directory-files directory nil
                                                 directory-files-no-dot-files-regexp
                                                 t 3))))
             (next (and entries (null (cdr entries))
                        (expand-file-name (car entries) directory))))
        (if (and next (file-directory-p next) (not (file-symlink-p next))
                 (not (my/sidebar-root-icon next)))
            (progn (push (car entries) chain)
                   (setq directory next))
          (setq done t))))
    (nreverse chain)))

(defun my/sidebar-compact-start-p (directory)
  "Return non-nil if a row of DIRECTORY may show the folders under it."
  (pcase my/sidebar-compact
    ('packages (my/sidebar-package-p directory))
    ('nil nil)
    (_ (and (my/sidebar-relative directory)
            (not (my/sidebar-root-icon directory))))))

(defun my/sidebar-compact (start end directory)
  "Extend each folder's name from START to END by the chain under it.
DIRECTORY holds the entries on those lines, none of them expanded yet."
  (when my/sidebar-compact
    (let ((end (copy-marker end)))
      (save-excursion
        (goto-char start)
        (while (< (point) end)
          (when-let* ((name (and (dired-move-to-filename)
                                 (dired-get-filename 'no-dir t)))
                      ;; Already compacted, when Dired's readin runs twice.
                      ((not (string-search "/" name)))
                      (file (expand-file-name name directory))
                      ((file-directory-p file))
                      ((not (file-symlink-p file)))
                      ((my/sidebar-compact-start-p file))
                      (chain (my/sidebar-compact-chain file)))
            (dired-move-to-end-of-filename)
            (let ((from (point)))
              (insert-and-inherit (mapconcat (lambda (part) (concat "/" part)) chain))
              (put-text-property from (point) 'dired-filename t))
            (push (expand-file-name (string-join chain "/") file)
                  my/sidebar-compact-ends))
          (forward-line 1)))
      (set-marker end nil))))

;; JetBrains shows a Java or Kotlin file that declares a type of its own
;; name as that type, without the extension.  The declaration follows the
;; package and imports, so reading the file's start finds it.

(defvar my/sidebar-types (make-hash-table :test #'equal)
  "Icons of JVM source files, as (MODIFICATION-TIME . ICON) by file.")

(defconst my/sidebar-type-bytes 16384
  "Bytes of a JVM source file read to find its type.")

(defun my/sidebar-read-type (file)
  "Return the icon of the type FILE declares under its own name, or nil."
  (let ((name (file-name-base file))
        (case-fold-search nil))
    (with-temp-buffer
      (ignore-errors
        (insert-file-contents-literally file nil 0 my/sidebar-type-bytes))
      (when (re-search-forward
             (concat "^[ \t]*\\(?:@[[:alnum:]_.]+\\(?:([^)\n]*)\\)?[ \t]+\\)*"
                     "\\(\\(?:[a-z-]+[ \t]+\\)*\\)"
                     "\\(class\\|interface\\|enum\\|record\\|object\\|@interface\\)"
                     "[ \t]+" (regexp-quote name) "\\(?:[^[:alnum:]_$]\\|$\\)")
             nil t)
        (let* ((keyword (match-string 2))
               (modifiers (split-string (match-string 1))))
          (cond ((or (equal keyword "@interface") (member "annotation" modifiers))
                 "nodes/annotation")
                ((or (equal keyword "enum") (member "enum" modifiers)) "nodes/enum")
                ((equal keyword "interface") "nodes/interface")
                ((equal keyword "record") "nodes/record")
                ((string-suffix-p "Exception" name)
                 (if (member "abstract" modifiers)
                     "nodes/abstractException" "nodes/exception"))
                ((member "abstract" modifiers) "nodes/classAbstract")
                (t "nodes/class")))))))

(defun my/sidebar-type-icon (file)
  "Return the icon of the type FILE declares if it is JVM source, else nil.
Each file is read once until it changes."
  (when (and (member (file-name-extension file) '("java" "kt"))
             (my/sidebar-package-p file))
    (let ((time (file-attribute-modification-time (file-attributes file)))
          (cached (gethash file my/sidebar-types)))
      (if (and cached (equal (car cached) time))
          (cdr cached)
        (cdr (puthash file (cons time (my/sidebar-read-type file))
                      my/sidebar-types))))))

;;;; Rows

;; Each entry's leading space shows its disclosure chevron and icon, and a
;; name too wide for the window shows shortened, with the full name as its
;; tooltip.  Rows are drawn when Dired lists them, and names are fitted again
;; when the window's width changes; redisplay and scrolling redraw nothing.

(require 'expui-icons)

(defface my/sidebar-neutral-icon '((t (:inherit shadow)))
  "Folder and ordinary file icons." :group 'dired)
(defface my/sidebar-source-icon '((t (:inherit link)))
  "Source file icons." :group 'dired)

(defconst my/sidebar-state-width 16
  "Pixel width of the disclosure column, matching the chevrons.")

(defconst my/sidebar-icon-gap 6
  "Pixels between an icon and its name.")

(defconst my/sidebar-name-margin 12
  "Pixels kept clear between a shortened name and the window's edge.")

(defvar my/sidebar-source-icons
  '("xml" "c" "h" "cpp" "Csharp" "java" "kotlin" "kotlinScript" "groovy"
    "language/scala" "language/php" "python" "perl" "javaScript" "typeScript"
    "swiftLang" "nodes/sourceRoot" "nodes/testRoot" "nodes/class"
    "nodes/classAbstract" "nodes/interface" "nodes/enum" "nodes/record"
    "nodes/annotation" "nodes/exception" "nodes/abstractException")
  "Icons drawn in the accent color when `expui-icons-style' is `mono'.")

(defvar-local my/sidebar-rows-width nil
  "Body width in pixels that the names were last fitted to, or nil.")

(defvar-local my/sidebar-name-widths nil
  "Pixel widths of names in the sidebar's font, by name.")

(defun my/sidebar-pixel-width (string)
  "Return the width of STRING in pixels, in the sidebar's font."
  (if (>= emacs-major-version 30)
      (string-pixel-width string (current-buffer))
    (string-pixel-width string)))

(defun my/sidebar-name-width (name)
  "Return the width of NAME in pixels, measured once per font."
  (unless my/sidebar-name-widths
    (setq my/sidebar-name-widths (make-hash-table :test #'equal)))
  (or (gethash name my/sidebar-name-widths)
      (puthash name (my/sidebar-pixel-width name) my/sidebar-name-widths)))

(defun my/sidebar-state (directory-p)
  "Return the disclosure chevron of the line at point.
DIRECTORY-P says whether the line lists a folder."
  (let ((state (and directory-p
                    (if (my/sidebar-tree-expanded-p) 'expanded 'collapsed))))
    (if (display-images-p)
        (propertize " " 'face 'my/sidebar-neutral-icon
                    'display (pcase state
                               ('expanded (expui-icons-image "general/chevronDown"))
                               ('collapsed (expui-icons-image "general/chevronRight"))
                               (_ `(space :width (,my/sidebar-state-width)))))
      (pcase state ('expanded "▾") ('collapsed "▸") (_ " ")))))

(defun my/sidebar-icon (icon)
  "Return ICON, an icon name; source files use the accent in `mono' style."
  (expui-icons-icon icon :face (if (member icon my/sidebar-source-icons)
                                   'my/sidebar-source-icon
                                 'my/sidebar-neutral-icon)))

(defun my/sidebar-fit-name (label)
  "Hide the end of the name under overlay LABEL if it is too wide.
The name stays buffer text, so the row keeps the buffer's faces and
background; an ellipsis replaces the hidden end.  The name drawn is the
label's `my/sidebar-name', which may leave out an extension."
  (dolist (key '(my/sidebar-tail my/sidebar-ext))
    (when-let* ((overlay (overlay-get label key)))
      (delete-overlay overlay)
      (overlay-put label key nil)))
  (let* ((name (overlay-get label 'my/sidebar-name))
         (start (overlay-start label))
         (room (when my/sidebar-rows-width
                 (max 0 (- my/sidebar-rows-width
                           (* (overlay-get label 'my/sidebar-label) my/sidebar-indent)
                           my/sidebar-state-width expui-icons-height
                           my/sidebar-icon-gap
                           ;; The mark column and the space before the icon.
                           (my/sidebar-name-width "  ")
                           my/sidebar-name-margin))))
         (shown (if (and room (> (my/sidebar-name-width name) room))
                    (length (truncate-string-pixelwise
                             name (max 0 (- room (my/sidebar-name-width "…")))
                             (current-buffer)))
                  (length name)))
         (key (if (< shown (length name)) 'my/sidebar-tail 'my/sidebar-ext)))
    (when (< (+ start shown) (overlay-end label))
      (let ((hidden (make-overlay (+ start shown) (overlay-end label))))
        (overlay-put hidden 'invisible key)
        (overlay-put hidden 'my/sidebar-row t)
        (overlay-put hidden 'evaporate t)
        (overlay-put label key hidden)))))

(defun my/sidebar-label-text (label)
  "Return the name under overlay LABEL as drawn, with the buffer's faces."
  (let* ((name (overlay-get label 'my/sidebar-name))
         (start (overlay-start label))
         (text (buffer-substring start (+ start (length name)))))
    ;; Packages draw dots for slashes.
    (dotimes (i (length name))
      (aset text i (aref name i)))
    text))

(defun my/sidebar-highlight (string face)
  "Return STRING with FACE, a selection face or nil, beneath its own faces.
Overlay strings do not take the background of the selection overlay."
  (when face
    (add-face-text-property 0 (length string) face t string))
  string)

(defun my/sidebar-row ()
  "Draw the entry on the line at point, if the line lists one."
  (when-let* ((start (dired-move-to-filename))
              (end (dired-move-to-end-of-filename t))
              (file (dired-get-filename nil t)))
    (let* ((directory-p (file-directory-p file))
           (name (buffer-substring-no-properties start end))
           (icon (if directory-p (my/sidebar-folder-icon file)
                   (my/sidebar-type-icon file)))
           (dotted (and directory-p (equal icon "nodes/package")
                        (string-search "/" name)))
           ;; Dired leaves the space before the name visible; the chevron
           ;; takes its place.
           (space (make-overlay (1- start) start))
           (label (make-overlay start end))
           (selected (my/sidebar-selected-face start)))
      ;; A compacted package draws its slashes as dots.
      (when dotted
        (save-excursion
          (goto-char start)
          (while (search-forward "/" end t)
            (let ((dot (make-overlay (1- (point)) (point))))
              (overlay-put dot 'display ".")
              (overlay-put dot 'my/sidebar-row t)
              (overlay-put dot 'evaporate t)))))
      ;; No hover face or tooltip: Dired's would repaint the name alone,
      ;; and a shortened name shows in full instead (see Full names).
      (with-silent-modifications
        (remove-text-properties (pos-bol) (pos-eol) '(mouse-face nil help-echo nil)))
      (dolist (overlay (list space label))
        (overlay-put overlay 'my/sidebar-row t)
        (overlay-put overlay 'evaporate t))
      (overlay-put space 'invisible t)
      ;; Images show from overlay strings, not from inside a display string.
      (overlay-put label 'before-string
                   (my/sidebar-highlight
                    (propertize
                     (concat (my/sidebar-state directory-p) " "
                             (my/sidebar-icon
                              (or icon (expui-icons-name-for-file name directory-p)))
                             (propertize " " 'display
                                         `(space :width (,my/sidebar-icon-gap))))
                     'pointer 'hand)
                    selected))
      (overlay-put label 'my/sidebar-label (my/sidebar-tree-depth))
      (overlay-put label 'my/sidebar-name
                   (cond (dotted (string-replace "/" "." name))
                         ;; A type's row leaves out its file's extension.
                         ((and icon (not directory-p)) (file-name-sans-extension name))
                         (t name)))
      (overlay-put label 'my/sidebar-hl selected)
      (when selected (push label my/sidebar-hl-rows))
      (overlay-put label 'pointer 'hand)
      (my/sidebar-fit-name label))))

(defun my/sidebar-rows-draw (start end)
  "Draw the entries on the lines from START to END."
  (remove-overlays start end 'my/sidebar-row t)
  (save-excursion
    (goto-char start)
    (while (< (point) end)
      (my/sidebar-row)
      (forward-line 1))))

(defun my/sidebar-rows-fit (window)
  "Fit the names to WINDOW when it shows its sidebar at a new width."
  (with-current-buffer (window-buffer window)
    (let ((width (window-body-width window t)))
      (unless (eql width my/sidebar-rows-width)
        (setq my/sidebar-rows-width width)
        (dolist (overlay (overlays-in (point-min) (point-max)))
          (when (overlay-get overlay 'my/sidebar-label)
            (my/sidebar-fit-name overlay)))))))

(defun my/sidebar-rows-refresh (&rest _)
  "Draw every sidebar again, as after a theme or font change."
  (interactive)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when my/sidebar-mode
        (setq my/sidebar-name-widths nil)
        (my/sidebar-rows-draw (point-min) (point-max))))))
;; Color icons have light and dark variants.
(add-hook 'enable-theme-functions #'my/sidebar-rows-refresh)

;;;; Selection

;; Overlays highlight the selected rows, in a fainter face while another
;; window is selected: the row at point, or every row an active region
;; touches, since Dired's marking and deletion commands act on the region.
;; The cursor itself stays hidden.

(defface my/sidebar-hl-line '((t (:inherit highlight :extend t)))
  "Selected sidebar row while the sidebar is in use." :group 'dired)
(defface my/sidebar-hl-line-inactive '((t (:inherit secondary-selection :extend t)))
  "Selected sidebar row while another window is in use." :group 'dired)

(defun my/sidebar-selected-face (position)
  "Return the selection face if the row at POSITION is selected, else nil."
  (let ((line (save-excursion (goto-char position) (pos-bol))))
    (seq-some (lambda (overlay)
                (and (overlay-buffer overlay) (= (overlay-start overlay) line)
                     (overlay-get overlay 'face)))
              my/sidebar-hl)))

(defun my/sidebar-snap ()
  "Move point from a line without an entry to the nearest entry.
Below the listing that is the last entry."
  (unless (dired-get-filename nil t)
    (let ((find (lambda (step)
                  (save-excursion
                    (while (and (zerop (forward-line step))
                                (not (dired-get-filename nil t))))
                    (and (dired-get-filename nil t) (point))))))
      (when-let* ((line (if (eobp)
                            (funcall find -1)
                          (or (funcall find 1) (funcall find -1)))))
        (goto-char line)
        (dired-move-to-filename)))))

(defun my/sidebar-selected-lines (window)
  "Return the starts of the rows selected in WINDOW, its sidebar's buffer current.
They are the rows an active region touches in the selected window, else
the row at WINDOW's point."
  (if (and (eq window (selected-window)) (region-active-p))
      (let ((end (region-end))
            lines)
        (save-excursion
          (goto-char (region-beginning))
          ;; A region ending at a row's start does not select that row.
          (while (and (< (point) end) (not (eobp)))
            (push (pos-bol) lines)
            (forward-line 1)))
        (nreverse lines))
    (list (save-excursion
            (when window (goto-char (window-point window)))
            (pos-bol)))))

(defun my/sidebar-select (&optional window)
  "Highlight the selected rows of WINDOW's sidebar.
WINDOW defaults to a window showing the current buffer."
  (let ((window (or window (get-buffer-window nil t))))
    (with-current-buffer (if window (window-buffer window) (current-buffer))
      (when my/sidebar-mode
        (let* ((face (if (and window (eq window (selected-window)))
                         'my/sidebar-hl-line 'my/sidebar-hl-line-inactive))
               (lines (my/sidebar-selected-lines window))
               (live (seq-filter #'overlay-buffer my/sidebar-hl))
               (old (mapcar #'overlay-start live))
               ;; Rows drawn selected, wherever text has since moved them.
               (drawn (delete-dups
                       (mapcar (lambda (label)
                                 (save-excursion (goto-char (overlay-start label)) (pos-bol)))
                               (seq-filter #'overlay-buffer my/sidebar-hl-rows)))))
          (unless (and (equal old lines)
                       (seq-every-p (lambda (overlay) (eq (overlay-get overlay 'face) face))
                                    live)
                       (seq-every-p (lambda (line) (memq line lines)) drawn))
            (mapc #'delete-overlay my/sidebar-hl)
            (setq my/sidebar-hl
                  (mapcar (lambda (line)
                            ;; Front-advance: rows a folder inserts above stay outside.
                            (let ((overlay (make-overlay
                                            line (save-excursion (goto-char line) (pos-bol 2))
                                            nil t)))
                              ;; Above the folders' indentation, which it also highlights.
                              (overlay-put overlay 'priority 100)
                              (overlay-put overlay 'evaporate t)
                              (overlay-put overlay 'face face)
                              (overlay-put overlay 'line-prefix
                                           (propertize " " 'face face 'display
                                                       `(space :width (,(* (my/sidebar-tree-depth line)
                                                                           my/sidebar-indent)))))
                              overlay))
                          lines))
            ;; Icons and shortened names carry the background themselves.
            (setq my/sidebar-hl-rows nil)
            (save-excursion
              (dolist (line (delete-dups (append old drawn lines)))
                (when (<= line (point-max))
                  (goto-char line)
                  (my/sidebar-rows-draw (pos-bol) (pos-eol)))))))))))

(defun my/sidebar-after-command ()
  "Keep point on an entry and highlight it, after a command in the sidebar."
  (my/sidebar-snap)
  (my/sidebar-select (selected-window)))

;;;; Full names

;; As in JetBrains, a shortened name shows in full while the mouse rests on
;; its row: a child frame covers the row with the same text, reaching past
;; the sidebar's edge.  Clicks and wheel turns on it act on the row.

(require 'posframe)

(defconst my/sidebar-name-buffer " *sidebar-name*"
  "Buffer of the child frame showing a full name.")

(defvar my/sidebar-name-shown nil
  "The row whose full name is shown, as (WINDOW LINE KEY), or nil.
LINE is the row's start; KEY changes when the row is drawn again.")

(defun my/sidebar-name-hide ()
  "Hide the full name, if one is shown."
  (when my/sidebar-name-shown
    (setq my/sidebar-name-shown nil)
    (posframe-hide my/sidebar-name-buffer)))

(defun my/sidebar-name-label (window position)
  "Return the shortened name's overlay on WINDOW's row at POSITION, or nil."
  (with-current-buffer (window-buffer window)
    (save-excursion
      (goto-char position)
      (seq-find (lambda (overlay)
                  (and (overlay-get overlay 'my/sidebar-label)
                       (overlay-get overlay 'my/sidebar-tail)))
                (overlays-in (pos-bol) (pos-eol))))))

(defun my/sidebar-name-click (_event)
  "Act on the row under the full name, as a click on the row would."
  (interactive "e")
  (pcase-let ((`(,window ,line) my/sidebar-name-shown))
    (my/sidebar-name-hide)
    (when (window-live-p window)
      (select-window window)
      (goto-char line)
      (when-let* ((file (and (dired-move-to-filename) (dired-get-filename nil t))))
        (if (file-directory-p file)
            (my/sidebar-tree-toggle)
          (my/sidebar-visit))))))

(defun my/sidebar-name-scroll (event)
  "Scroll the sidebar under the full name with wheel EVENT."
  (interactive "e")
  (let ((window (car my/sidebar-name-shown)))
    (my/sidebar-name-hide)
    (when (window-live-p window)
      (let ((start (copy-sequence (event-start event))))
        (setcar start window)
        (my/sidebar-scroll (append (list (car event) start) (cddr event)))))))

(defvar my/sidebar-name-map
  (let ((map (make-sparse-keymap)))
    (define-key map [down-mouse-1] #'ignore)
    (define-key map [mouse-1] #'my/sidebar-name-click)
    (define-key map [mouse-2] #'my/sidebar-name-click)
    (define-key map [wheel-up] #'my/sidebar-name-scroll)
    (define-key map [wheel-down] #'my/sidebar-name-scroll)
    map)
  "Mouse actions on a full name, forwarded to its row.")

(defun my/sidebar-name-show (window label)
  "Show the full name of overlay LABEL over its row in WINDOW."
  (let* ((buffer (window-buffer window))
         (line (with-current-buffer buffer
                 (save-excursion (goto-char (overlay-start label)) (pos-bol))))
         (key (list (overlay-get label 'before-string)
                    (overlay-start (overlay-get label 'my/sidebar-tail)))))
    (unless (equal my/sidebar-name-shown (list window line key))
      (let* ((selected (overlay-get label 'my/sidebar-hl))
             (spot (posn-x-y (posn-at-point line window)))
             (edges (window-inside-pixel-edges window))
             ;; Start at the icon, past the mark column and chevron, as in
             ;; JetBrains.  Without a border the row simply runs on.
             (inset (with-current-buffer buffer
                      (+ (my/sidebar-name-width "  ") my/sidebar-state-width)))
             (text (with-current-buffer buffer
                     (concat (substring (overlay-get label 'before-string) 2)
                             (my/sidebar-highlight (my/sidebar-label-text label)
                                                   selected)
                             (propertize " " 'display
                                         `(space :width (,my/sidebar-icon-gap)))))))
        (with-current-buffer (get-buffer-create my/sidebar-name-buffer)
          ;; The sidebar's fonts, card color and row height.
          (setq-local face-remapping-alist
                      (copy-tree (buffer-local-value 'face-remapping-alist buffer)))
          (when selected
            (face-remap-add-relative 'default :background (face-background selected nil t)))
          (setq-local line-spacing (buffer-local-value 'line-spacing buffer)))
        ;; The child frame lies under the pointer; leave the pointer there.
        (let ((posframe-mouse-banish-function #'ignore))
          (posframe-show my/sidebar-name-buffer
                         :string (propertize text 'keymap my/sidebar-name-map
                                             'pointer 'hand)
                         :position (cons (+ (nth 0 edges) (car spot) inset)
                                         (+ (nth 1 edges) (cdr spot)))
                         :left-fringe 0 :right-fringe 0
                         :internal-border-width 0
                         :border-width 0
                         :lines-truncate t
                         :accept-focus nil))
        (setq my/sidebar-name-shown (list window line key))))))

(defun my/sidebar-name-track (position)
  "Show the full name of the shortened row at mouse POSITION, else hide it.
POSITION is from `mouse-pixel-position'."
  (let* ((frame (car position))
         (child (and my/sidebar-name-shown
                     (get-buffer-window my/sidebar-name-buffer t)))
         (posn (and (frame-live-p frame) (cadr position)
                    (not (frame-parent frame))
                    (posn-at-x-y (cadr position) (cddr position) frame)))
         (window (and posn (posn-window posn)))
         (point (and posn (posn-point posn))))
    (cond
     ;; The pointer rests on the full name itself.
     ((and child (eq frame (window-frame child))))
     ((and (windowp window) (integerp point) (not (posn-area posn))
           (eq frame (selected-frame))
           (buffer-local-value 'my/sidebar-mode (window-buffer window)))
      (if-let* ((label (my/sidebar-name-label window point)))
          (my/sidebar-name-show window label)
        (my/sidebar-name-hide)))
     (t (my/sidebar-name-hide)))))

;;;; Header and status bar

;; The header names the project, with a New UI tool window's toolbar while
;; the sidebar is in use.  The status bar is empty: it only continues the
;; editor's along the frame's bottom edge.  init-status.el and
;; init-islands.el advise both functions.

(declare-function my/ui-mode-line-space "frame-setting" (width))
(declare-function my/ui-header-space "frame-setting" (width))

(defun my/sidebar-status-line ()
  "Return the sidebar's status bar."
  (when (display-graphic-p)
    (my/ui-mode-line-space 0)))

;; Emacs reports no mouse enter or leave events for windows, so poll the
;; pointer and redraw a sidebar's header only when it enters or leaves one.
(defvar my/sidebar-hovered nil "The sidebar window under the mouse.")
(defvar my/sidebar-hover-timer nil)

(defun my/sidebar-track-hover ()
  "Note which sidebar the mouse is over and redraw the bars that change."
  (let* ((position (mouse-pixel-position))
         (window (and (frame-live-p (car position)) (cadr position)
                      (window-at-x-y (cadr position) (cddr position)
                                     (car position))))
         (hovered (and window
                       (buffer-local-value 'my/sidebar-mode (window-buffer window))
                       window)))
    (unless (eq hovered my/sidebar-hovered)
      (dolist (changed (list my/sidebar-hovered hovered))
        (when (window-live-p changed)
          (with-current-buffer (window-buffer changed)
            (force-mode-line-update))))
      (setq my/sidebar-hovered hovered))
    (my/sidebar-name-track position)))

(when (timerp my/sidebar-hover-timer)
  (cancel-timer my/sidebar-hover-timer))
(setq my/sidebar-hover-timer
      (when (display-graphic-p)
        (run-with-timer 0.15 0.15 #'my/sidebar-track-hover)))

(defun my/sidebar-active-p ()
  "Return non-nil if the sidebar whose header is drawn is focused or hovered.
Headers are drawn with their window temporarily selected."
  (or (mode-line-window-selected-p)
      (eq (selected-window) my/sidebar-hovered)))

(defface my/sidebar-project-title '((t (:inherit default)))
  "Sidebar project title." :group 'dired)
(defface my/sidebar-toolbar-hover '((t (:inherit highlight)))
  "Sidebar header button under the mouse." :group 'dired)

(defconst my/sidebar-toolbar-padding 4
  "Pixels on each side of a toolbar icon.")

(defconst my/sidebar-toolbar-margin 6
  "Pixels between the toolbar and the sidebar's right edge.")

(defvar my/sidebar-buttons
  '(("general/add" my/sidebar-new-menu "New")
    ("general/locate" my/sidebar-locate "Select Opened File")
    ("general/expandAll" my/sidebar-tree-expand-all "Expand Selected")
    ("general/collapseAll" my/sidebar-tree-clear "Collapse All")
    ("general/moreVertical" my/sidebar-options-menu "Options")
    ("general/hide" my/sidebar-hide "Hide"))
  "Sidebar toolbar buttons as (ICON ACTION HELP).
ACTION is a command, or a function called with the click event.")

(defun my/sidebar-button (action help &rest strings)
  "Return STRINGS as a header button running ACTION, with tooltip HELP.
ACTION runs in the clicked sidebar; see `my/sidebar-buttons'."
  (let ((map (make-sparse-keymap)))
    ;; Act on press, like the status bar's menu; this also keeps the press
    ;; from starting a header-line window resize.
    (define-key map [header-line down-mouse-1]
      (lambda (event)
        (interactive "e")
        (select-window (posn-window (event-start event)))
        (if (commandp action)
            (call-interactively action)
          (funcall action event))))
    (define-key map [header-line mouse-1] #'ignore)
    (propertize (apply #'concat strings)
                'local-map map 'help-echo help 'pointer 'hand
                'mouse-face 'my/sidebar-toolbar-hover)))

(defun my/sidebar-toolbar ()
  "Return the sidebar's toolbar buttons."
  (let ((pad (propertize " " 'display
                         `(space :width (,my/sidebar-toolbar-padding)))))
    (mapconcat (pcase-lambda (`(,icon ,action ,help))
                 (my/sidebar-button
                  action help pad
                  (expui-icons-icon icon :face 'my/sidebar-neutral-icon) pad))
               my/sidebar-buttons "")))

(defun my/sidebar-header ()
  "Return the sidebar's view title, and its toolbar while in use.
As in a New UI tool window, the toolbar shows when focused or hovered."
  (let* ((toolbar (when (my/sidebar-active-p)
                    (concat (my/sidebar-toolbar)
                            (propertize " " 'display
                                        `(space :width (,my/sidebar-toolbar-margin))))))
         (toolbar-width (if toolbar (string-pixel-width toolbar) 0))
         (chevron (concat (propertize " " 'display '(space :width (2)))
                          (expui-icons-icon "general/chevronDown"
                                            :face 'my/sidebar-neutral-icon)))
         ;; As in JetBrains, the title bar names the project; this is the
         ;; Project view, whose menu switches between projects.
         (name (propertize " Project" 'face 'my/sidebar-project-title))
         ;; Shorten the title rather than let the window clip the toolbar.
         (room (- (window-body-width nil t) toolbar-width
                  (string-pixel-width chevron) 8 (my/ui-line-end-inset))))
    (concat (propertize " " 'face 'header-line 'display (my/ui-header-space 0))
            (my/sidebar-button
             #'my/sidebar-project-menu "Switch Project"
             (truncate-string-pixelwise name room (current-buffer) "…")
             chevron)
            (when toolbar
              (my/ui-at-right toolbar (my/ui-line-end))))))

;;;; Menus

(declare-function my/workspace-root-name "init-workspace" (root))
(declare-function my/workspace-projects "init-workspace" ())
(declare-function my/workspace-open "init-workspace")

(defun my/sidebar-project-menu (event)
  "Pop up recent projects at EVENT, marking the frame's current one."
  (let ((current (frame-parameter nil 'my/workspace-root))
        (projects (and (fboundp 'my/workspace-projects)
                       (seq-take (my/workspace-projects) 10))))
    (popup-menu
     `("Projects"
       ,@(mapcar (lambda (root)
                   (vector (my/workspace-root-name root)
                           `(my/sidebar-in-editor #'my/workspace-open ,root)
                           :style 'radio :selected (equal root current)))
                 projects)
       ,@(and projects '("---"))
       ["Open Directory…" (my/sidebar-in-editor #'my/sidebar-open-directory)])
     event)))

(defun my/sidebar-new-menu (event)
  "Pop up commands at EVENT creating entries in the folder at point."
  (popup-menu '("New"
                ["File…" dired-create-empty-file]
                ["Directory…" dired-create-directory])
              event))

(defun my/sidebar-relist (remove &optional add)
  "Relist the sidebar without switches matching REMOVE, then with ADD."
  (setq dired-actual-switches
        (string-join (append (seq-remove (lambda (switch)
                                           (string-match-p remove switch))
                                         (split-string dired-actual-switches))
                             (and add (list add)))
                     " "))
  (revert-buffer))

(defconst my/sidebar-sorts
  '(("Name" nil) ("Modification Time" "--sort=time") ("Size" "--sort=size")
    ("Type" "--sort=extension"))
  "Sidebar sort orders as (LABEL SWITCH); GNU ls sorts by name by default.")

(defun my/sidebar-options-menu (event)
  "Pop up the sidebar's sort and listing options at EVENT."
  (let* ((switches (split-string dired-actual-switches))
         (sort (seq-find (lambda (switch) (string-prefix-p "--sort=" switch))
                         switches))
         (toggle (lambda (label switch)
                   (let ((on (member switch switches)))
                     (vector label
                             `(my/sidebar-relist
                               ,(concat "\\`" (regexp-quote switch) "\\'")
                               ,(unless on switch))
                             :style 'toggle :selected (and on t)
                             :active my/sidebar-gnu-ls))))
         (count (length (directory-files default-directory nil
                                         directory-files-no-dot-files-regexp t))))
    (popup-menu
     `("Options"
       ,@(mapcar (pcase-lambda (`(,label ,switch))
                   (vector (concat "Sort by " label)
                           `(my/sidebar-relist "\\`--\\(sort\\|time\\)=" ,switch)
                           :style 'radio :selected (equal switch sort)
                           :active my/sidebar-gnu-ls))
                 my/sidebar-sorts)
       "---"
       ,(funcall toggle "Descending" "--reverse")
       ,(funcall toggle "Folders First" "--group-directories-first")
       "---"
       ,(vector (format "%d item%s" count (if (= count 1) "" "s")) nil :active nil))
     event)))

;;;; Mouse

;; Islands paints a few fringe pixels beside the one-pixel divider.
;; Treat that visible gap as part of the resize handle as well.
(defun my/sidebar-drag-divider (event)
  "Resize the sidebar using positions from mouse EVENTs, including its fringe."
  (interactive "e")
  (let* ((window (posn-window (event-start event)))
         (x-position
          (lambda (position)
            (let ((win (posn-window position)))
              (+ (car (posn-x-y position))
                 (if (windowp win) (car (window-inside-pixel-edges win)) 0)))))
         (last-x (funcall x-position (event-start event)))
         (track-mouse t)
         done)
    (while (not done)
      (let ((next (read-event)))
        (cond
         ((and (mouse-event-p next)
               (memq (event-basic-type next) '(mouse-movement mouse-1)))
          (let* ((x (funcall x-position (event-end next)))
                 (delta (- x last-x)))
            (unless (zerop delta)
              (adjust-window-trailing-edge window delta t t)
              (setq last-x x)
              ;; Redisplay refits the names and recomposes the header now,
              ;; while `read-event' keeps this command running.
              (force-mode-line-update t)
              (redisplay t)))
          (when (eq (event-basic-type next) 'mouse-1) (setq done t)))
         (t (setq unread-command-events (cons next unread-command-events)
                  done t)))))))

(define-key my/sidebar-mode-map [right-fringe down-mouse-1] #'my/sidebar-drag-divider)
(define-key my/sidebar-mode-map [right-divider down-mouse-1] #'my/sidebar-drag-divider)
(define-key my/sidebar-mode-map [right-fringe mouse-1] #'ignore)
(define-key my/sidebar-mode-map [right-fringe drag-mouse-1] #'ignore)

(defvar-local my/sidebar-scroll-remainder 0)

(declare-function pixel-scroll-precision "pixel-scroll" (event))

(defun my/sidebar-scroll (event)
  "Scroll sidebar rows with EVENT, accumulating small touchpad deltas.
Avoid repeatedly relaying out SVGs at fractional row offsets."
  (interactive "e")
  (let ((window (mwheel-event-window event)))
    (when (framep window) (setq window (frame-selected-window window)))
    (if (not (and (window-live-p window)
                  (buffer-local-value 'my/sidebar-mode (window-buffer window))))
        (pixel-scroll-precision event)
      (with-selected-window window
        (set-window-vscroll window 0 t)
        (if-let* ((raw-delta (cdr-safe (nth 4 event))))
            ;; The wheel event already reflects the system's scroll direction;
            ;; its raw pixel delta does not necessarily use the same sign.
            ;; Only `wheel-*' events carry a pixel delta; `wheel-up' shows
            ;; earlier rows, as in `mwheel-scroll'.
            (let* ((delta (if (eq (event-basic-type event) 'wheel-up)
                              (- (abs raw-delta)) (abs raw-delta)))
                   (height (max 1 (line-pixel-height)))
                   (old my/sidebar-scroll-remainder))
              (setq my/sidebar-scroll-remainder
                    (+ delta (if (< (* delta old) 0) 0 old)))
              (let ((lines (truncate (/ my/sidebar-scroll-remainder
                                        (float height)))))
                (unless (zerop lines)
                  (setq my/sidebar-scroll-remainder
                        (- my/sidebar-scroll-remainder (* lines height)))
                  (condition-case nil
                      (if (> lines 0) (scroll-up lines) (scroll-down (- lines)))
                    ((beginning-of-buffer end-of-buffer) nil)))))
          (let ((mouse-wheel-scroll-amount '(2 ((shift) . 1)))
                (mouse-wheel-progressive-speed nil))
            (mwheel-scroll event)))
        ;; Scrolling moves point along when its row leaves the window.
        (my/sidebar-snap)
        (my/sidebar-select window)))))

(define-key my/sidebar-mode-map [remap pixel-scroll-precision] #'my/sidebar-scroll)
(put 'my/sidebar-scroll 'scroll-command t)

;;;; Window

(defvar my/sidebar-width-ratio 0.22
  "Share of the frame's width a sidebar opens with, within the limits.")

(defvar my/sidebar-width-limits '(220 . 300)
  "Narrowest and widest width, in pixels, that a sidebar opens with.
The narrowest still fits most names two levels deep; the widest is about
a New UI tool window's.")

(defun my/sidebar-width ()
  "Return the selected frame's sidebar width in columns."
  (let ((pixels (* my/sidebar-width-ratio (frame-pixel-width))))
    (round (max (car my/sidebar-width-limits)
                (min (cdr my/sidebar-width-limits) pixels))
           (frame-char-width))))

(defun my/sidebar-window (&optional frame)
  "Return FRAME's visible sidebar window, or nil."
  (seq-find (lambda (window)
              (and (window-parameter window 'window-side)
                   (buffer-local-value 'my/sidebar-mode (window-buffer window))))
            (window-list frame 'no-minibuffer)))

(defun my/sidebar-display (buffer)
  "Show BUFFER in the selected frame's sidebar window and return the window.
The window stays dedicated, so it never shows an editor buffer."
  (if-let* ((window (my/sidebar-window)))
      (progn
        (set-window-dedicated-p window nil)
        (set-window-buffer window buffer)
        (set-window-dedicated-p window t)
        window)
    (display-buffer-in-side-window
     buffer `((side . left) (slot . -1) (dedicated . t)
              (window-width . ,(my/sidebar-width))
              (window-parameters (no-other-window . t)
                                 (no-delete-other-windows . t))))))

(defun my/sidebar-hide (&optional frame)
  "Hide FRAME's sidebar, keeping its buffer for the next time it shows."
  (interactive)
  (when-let* ((window (my/sidebar-window frame)))
    (delete-window window)))

(defun my/sidebar-in-editor (function &rest args)
  "Call FUNCTION with ARGS, or interactively, from the last editor window.
The sidebar's window is dedicated, so it cannot show other buffers."
  (when-let* ((window (get-mru-window nil nil t)))
    (select-window window))
  (if args (apply function args) (call-interactively function)))

;;;; Entry points

(defun my/sidebar-root ()
  "Return the current project root, or the current directory."
  (if-let* ((project (project-current nil)))
      (project-root project)
    default-directory))

(defun my/sidebar-show (&optional directory)
  "Ensure the sidebar shows DIRECTORY, preserving the selected window.
When it starts showing DIRECTORY, expand it to the current buffer's file."
  (let* ((directory (file-name-as-directory
                     (expand-file-name (or directory (my/sidebar-root)))))
         (buffer (my/sidebar-buffer directory))
         ;; An external dependency source cannot be located in this tree.
         (file (and buffer-file-name
                    (string-prefix-p directory (expand-file-name buffer-file-name))
                    buffer-file-name))
         (shown (when-let* ((window (my/sidebar-window)))
                  (eq (window-buffer window) buffer)))
         (window (save-selected-window (my/sidebar-display buffer))))
    (when (and file (not shown))
      (with-selected-window window
        (my/sidebar-tree-reveal file)))
    (my/sidebar-select window)
    (set-frame-parameter nil 'my/sidebar-directory directory)))

(defun my/sidebar-toggle ()
  "Focus the sidebar from the editor; hide it when already focused."
  (interactive)
  (if-let* ((window (my/sidebar-window)))
      (if (eq window (selected-window))
          (my/sidebar-hide)
        (select-window window))
    (my/sidebar-show (frame-parameter nil 'my/sidebar-directory))
    (when-let* ((window (my/sidebar-window)))
      (select-window window))))

(global-set-key (kbd "s-1") #'my/sidebar-toggle)
(global-set-key (kbd "C-c e") #'my/sidebar-toggle)

(defun my/sidebar-visit ()
  "Open the file at point in the editor, or list the folder at point here."
  (interactive)
  (let ((file (dired-get-file-for-visit)))
    (if (file-directory-p file)
        (my/sidebar-show file)
      (my/sidebar-in-editor #'find-file file))))

(defun my/sidebar-up ()
  "List the parent of the sidebar's folder."
  (interactive)
  (my/sidebar-show (file-name-directory (directory-file-name default-directory))))

(defun my/sidebar-mouse-press (event)
  "Focus the sidebar clicked with EVENT without moving point yet."
  (interactive "e")
  (select-window (posn-window (event-start event))))

(defun my/sidebar-mouse-visit (event)
  "Expand or collapse the folder clicked with EVENT, or open the file."
  (interactive "e")
  (let* ((position (event-end event))
         (point (posn-point position)))
    (select-window (posn-window position))
    ;; Blank space below the listing maps to point-max; leave point be.
    (when-let* ((file (and (integer-or-marker-p point)
                           (< point (point-max))
                           (save-excursion (goto-char point)
                                           (dired-get-filename nil t)))))
      (goto-char point)
      (if (file-directory-p file)
          (my/sidebar-tree-toggle)
        (my/sidebar-visit)))))

(define-key my/sidebar-mode-map (kbd "RET") #'my/sidebar-visit)
(define-key my/sidebar-mode-map (kbd "TAB") #'my/sidebar-tree-toggle)
(define-key my/sidebar-mode-map (kbd "^") #'my/sidebar-up)
(define-key my/sidebar-mode-map (kbd "q") #'my/sidebar-hide)
;; Dired's follow-link translates a left click on a filename to mouse-2.
(define-key my/sidebar-mode-map [down-mouse-1] #'my/sidebar-mouse-press)
(define-key my/sidebar-mode-map [mouse-1] #'my/sidebar-mouse-visit)
(define-key my/sidebar-mode-map [mouse-2] #'my/sidebar-mouse-visit)

(declare-function my/welcome-empty-buffer "init-welcome")

(defun my/sidebar-empty-buffer (directory)
  "Return an empty editor buffer for DIRECTORY.
Before the start page loads, use a scratch buffer, preserving its text."
  (if (fboundp 'my/welcome-empty-buffer)
      (my/welcome-empty-buffer directory)
    (my/sidebar-scratch-buffer directory)))

(defun my/sidebar-scratch-buffer (directory)
  "Return an empty scratch buffer for DIRECTORY, preserving existing text."
  (let ((buffer (get-buffer-create "*scratch*")))
    (unless (zerop (buffer-size buffer))
      (setq buffer (generate-new-buffer "*scratch*")))
    (with-current-buffer buffer
      (unless (derived-mode-p 'lisp-interaction-mode)
        (lisp-interaction-mode))
      (setq-local default-directory (file-name-as-directory directory)))
    buffer))

(declare-function my/workspace-root-of "init-workspace" (directory))

(defun my/sidebar-open-directory (directory)
  "Open DIRECTORY's project, or DIRECTORY itself, as a workspace.
Like the start page, this remembers the project and gives it its own tabs."
  (interactive (list (read-directory-name "Open directory: " nil nil t)))
  (my/workspace-open (my/workspace-root-of directory)))

(defun my/sidebar-project-dired ()
  "Show the current project in the sidebar with an empty editor buffer."
  (interactive)
  (let ((directory (project-root (project-current t))))
    (switch-to-buffer (my/sidebar-empty-buffer directory))
    (my/sidebar-show directory)))

(defun my/sidebar-after-project-find-file (&rest _)
  "Show the current project after opening a project file."
  (my/sidebar-show))

(advice-add 'project-dired :override #'my/sidebar-project-dired)
;; Project switching and startup are owned by init-workspace.el.
(advice-add 'project-find-file :after #'my/sidebar-after-project-find-file)

(defun my/sidebar-take-startup-directory ()
  "Replace command-line directory windows with empty editors; return the first.
Run after Emacs has processed file arguments, including relative paths and
paths following --.  Explicit file buffers remain in their editor windows.
The caller decides what to show for the returned directory."
  (let (directory)
    (dolist (window (window-list))
      (with-current-buffer (window-buffer window)
        (when (and (derived-mode-p 'dired-mode)
                   (not (window-parameter window 'window-side)))
          (setq directory (or directory default-directory))
          (let ((directory-buffer (current-buffer)))
            (set-window-buffer window
                               (my/sidebar-empty-buffer default-directory))
            ;; Keep the Dired buffer alive, but remove the startup placeholder
            ;; from this editor's navigation history and tab strip.
            (set-window-prev-buffers
             window (seq-remove (lambda (entry) (eq (car entry) directory-buffer))
                                (window-prev-buffers window)))
            (set-window-next-buffers
             window (delq directory-buffer (window-next-buffers window)))))))
    directory))

(provide 'init-sidebar)
;;; init-sidebar.el ends here
