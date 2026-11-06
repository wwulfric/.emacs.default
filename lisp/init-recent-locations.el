;;; init-recent-locations.el --- IntelliJ's Recent Locations -*- lexical-binding: t; -*-

;;; Commentary:
;; S-s-e lists the places worked at lately, newest first, each with its
;; line of code: where navigation left from (the history s-[ goes back
;; through, init-navigation.el) and where text was changed.  Typing
;; filters them by file and code; S-s-e again shows changed places only,
;; as Cmd-Shift-E does in IntelliJ.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'xref)
(require 'expui-icons)

(defvar palette-islands-placement)
(declare-function palette-islands-set-action "palette-islands" (key description))

(defcustom my/recent-locations-max 60
  "Most places Recent Locations remembers."
  :type 'natnum
  :group 'convenience)

(defconst my/recent-locations-near 3
  "Lines within which two places in one file count as one.")

(defvar my/recent-locations nil
  "Places worked at, newest first: (MARKER . KIND), KIND `visited' or `changed'.")

(defun my/recent-locations--same-p (marker other)
  "Return non-nil when MARKER and OTHER are within a few lines of each other."
  (and (eq (marker-buffer marker) (marker-buffer other))
       (with-current-buffer (marker-buffer marker)
         (<= (abs (- (line-number-at-pos marker t) (line-number-at-pos other t)))
             my/recent-locations-near))))

(defun my/recent-locations-note (position kind)
  "Remember POSITION, a marker or point, as a place of KIND.
A place near one already remembered replaces it; `changed' wins."
  (when (and (buffer-file-name (if (markerp position) (marker-buffer position) (current-buffer)))
             (not (minibufferp)))
    (let ((marker (if (markerp position) (copy-marker position) (point-marker))))
      (when-let* ((old (seq-find (lambda (entry)
                                   (and (marker-buffer (car entry))
                                        (my/recent-locations--same-p marker (car entry))))
                                 my/recent-locations)))
        (when (eq (cdr old) 'changed) (setq kind 'changed))
        (set-marker (car old) nil)
        (setq my/recent-locations (delq old my/recent-locations)))
      (push (cons marker kind) my/recent-locations)
      (when (> (length my/recent-locations) my/recent-locations-max)
        (dolist (entry (nthcdr my/recent-locations-max my/recent-locations))
          (set-marker (car entry) nil))
        (setq my/recent-locations (seq-take my/recent-locations my/recent-locations-max))))))

(defun my/recent-locations--visited (marker &rest _)
  "Remember MARKER, which navigation is leaving."
  (when (and (markerp marker) (marker-buffer marker))
    (with-current-buffer (marker-buffer marker)
      (my/recent-locations-note marker 'visited))))

(advice-add 'xref-push-marker-stack :after #'my/recent-locations--visited)

(defvar-local my/recent-locations--changed nil
  "Non-nil when the command running changed this buffer's text.")

(defun my/recent-locations--changed (&rest _)
  "Note that the command running changed this file's text."
  (when (and buffer-file-name this-command (not undo-in-progress))
    (setq my/recent-locations--changed t)))

(defun my/recent-locations--command-done ()
  "Remember where point is after a command that changed the text.
A run of typing is one place, as the caret ends up after it."
  (when my/recent-locations--changed
    (setq my/recent-locations--changed nil)
    (my/recent-locations-note (point) 'changed)))

(add-hook 'after-change-functions #'my/recent-locations--changed)
(add-hook 'post-command-hook #'my/recent-locations--command-done)

(defun my/recent-locations--candidates (changed-only)
  "Return the places as candidates, newest first; CHANGED-ONLY keeps changes."
  (let ((here (point-marker))
        (index 0)
        candidates)
    (dolist (entry my/recent-locations)
      (let ((marker (car entry)))
        (when (and (marker-buffer marker)
                   (buffer-file-name (marker-buffer marker))
                   (or (not changed-only) (eq (cdr entry) 'changed))
                   (not (my/recent-locations--same-p here marker)))
          (with-current-buffer (marker-buffer marker)
            (save-excursion
              (goto-char marker)
              (font-lock-ensure (pos-bol) (pos-eol))
              (let* ((line (line-number-at-pos nil t))
                     (code (string-trim (buffer-substring (pos-bol) (pos-eol))))
                     (file (file-name-nondirectory buffer-file-name))
                     (candidate
                      (concat file
                              (propertize (format ":%d" line) 'face 'completions-annotations)
                              "  "
                              (if (string-empty-p code)
                                  (propertize "(blank line)" 'face 'shadow)
                                code))))
                ;; Two places may show the same text.
                (when (assoc candidate candidates)
                  (setq candidate (concat candidate (propertize (format "  (%d)" (cl-incf index))
                                                                'face 'shadow))))
                (add-text-properties
                 0 1 (list 'palette-islands-icon (expui-icons-name-for-file file)
                           'palette-islands-detail
                           (format "%s:%d%s" (abbreviate-file-name buffer-file-name) line
                                   (if (eq (cdr entry) 'changed) " · changed" "")))
                 candidate)
                (push (cons candidate marker) candidates)))))))
    (set-marker here nil)
    (nreverse candidates)))

(defvar-keymap my/recent-locations-map
  "S-s-e" (lambda () (interactive) (throw 'my/recent-locations 'toggle))
  "s-E" (lambda () (interactive) (throw 'my/recent-locations 'toggle)))

(defun my/recent-locations (&optional changed-only)
  "Go to a place visited or changed lately, chosen from a list.
CHANGED-ONLY lists changed places only."
  (interactive)
  (let ((result
         (catch 'my/recent-locations
           (let* ((candidates (my/recent-locations--candidates changed-only))
                  (table (lambda (string predicate action)
                           (if (eq action 'metadata)
                               '(metadata (category . recent-location)
                                          (display-sort-function . identity)
                                          (cycle-sort-function . identity))
                             (complete-with-action action candidates string predicate)))))
             (minibuffer-with-setup-hook
                 (:append (lambda ()
                            (use-local-map (make-composed-keymap my/recent-locations-map
                                                                 (current-local-map)))
                            (when (fboundp 'palette-islands-set-action)
                              (palette-islands-set-action
                               "S-s-e" (if changed-only "Show all" "Show changed only")))))
               (cdr (assoc (completing-read (if changed-only "Recently Changed Locations: "
                                              "Recent Locations: ")
                                            table nil t)
                           candidates)))))))
    (cond ((eq result 'toggle) (my/recent-locations (not changed-only)))
          ((markerp result)
           (unless (marker-buffer result) (user-error "The file was closed"))
           (switch-to-buffer (marker-buffer result))
           (goto-char result)
           (recenter)))))

(keymap-global-set "S-s-e" #'my/recent-locations)
(keymap-global-set "s-E" #'my/recent-locations)

(provide 'init-recent-locations)
;;; init-recent-locations.el ends here
