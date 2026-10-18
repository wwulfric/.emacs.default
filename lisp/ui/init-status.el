;;; init-status.el --- One status bar along the frame's bottom -*- lexical-binding: t; -*-

;;; Commentary:
;; As in JetBrains IDEs, one bar along the frame's bottom edge tells about
;; the window being edited, instead of a mode line under each window:
;;
;;   ☰  Haxl › Core › Monad.hs  ●       Saved       E3 W2  287:12  LF  UTF-8  Haskell
;;
;; At the left the mode menu (frame-setting.el), the file's place in its
;; project and its state; in the middle the last message; at the right
;; diagnostics, position, line ends, encoding and mode; as in JetBrains, the
;; title bar names the project and branch.  Like awesome-tray, the bar is
;; the text of the idle echo area, whose minibuffer
;; opens in a floating panel (init-palette.el); it sits on the canvas below
;; the cards (init-islands.el).  Messages are drawn in the bar rather than
;; replacing it; a long one is cut short, and a click shows them all.
;; A window's mode line keeps only the bottom edge of its card, as tall as
;; the card's rounded corners.  Terminal frames keep the full mode line.

;;; Code:

(require 'subr-x)
(require 'ui-layout)
;; For Dirvish's session accessors, which are macros.
(eval-when-compile (require 'dirvish nil t))

(declare-function my/ui-build-mode-menu "frame-setting" ())
(declare-function my/ui-status-line "frame-setting" ())
(declare-function my/dirvish-side-bars "init-dirvish" (dv))
(declare-function project-root "project" (project))
(defvar my/ui-diagnostic-summary)
(defvar my/islands-mode)
(defvar my/islands-radius)

(defface my/status '((t (:inherit my/ui-font :height 0.9)))
  "Text of the status bar."
  :group 'faces)

(defface my/status-muted '((t (:inherit (shadow my/status))))
  "Secondary text of the status bar: folders, flags and encoding."
  :group 'faces)

(defface my/status-hover '((t (:inherit highlight)))
  "Item of the status bar under the mouse."
  :group 'faces)

(defconst my/status-gap 16
  "Pixels between the items of the status bar.")

(defconst my/status-spacing '(0.45 . 0.45)
  "Space above and below the status bar's text, relative to its height.")

(defvar my/status--message nil
  "Message shown in the middle of the bar, or nil.")

(defvar my/status--last nil
  "Text last written to the bar, to skip identical updates.")

;;;; Mode lines

(defun my/status-edge ()
  "Return a mode line that is only the bottom edge of the window's card.
It is `my/ui-mode-line-pixels' tall, the height of the card's rounded
corners, which Islands draws at its ends, and reaches the right one.
Terminal frames get nil."
  (when (display-graphic-p)
    (propertize " " 'face '(:overline nil :underline nil :box nil)
                'display `(space :align-to ,(my/ui-line-end)
                                 :height (,my/ui-mode-line-pixels)
                                 :ascent 75))))

(defun my/status--mode-line (status-line)
  "Call STATUS-LINE in terminal frames; graphical ones show the bar instead."
  (if (display-graphic-p) (my/status-edge) (funcall status-line)))

(defun my/status--dirvish-bars (dv &rest _)
  "Make the status bar of Dirvish side session DV a card edge too."
  (when (eq (dv-type dv) 'side)
    (setf (dv-mode-line dv) '(:eval (my/status-edge)))))

;;;; Items

(defun my/status--window ()
  "Return the window the bar tells about: the editor window in use.
Side windows such as the sidebar, and the minibuffer, defer to the editor
window used most recently."
  (let ((window (if (minibufferp (window-buffer (selected-window)))
                    (minibuffer-selected-window)
                  (selected-window))))
    (if (and (window-live-p window) (not (window-parameter window 'window-side)))
        window
      (let (best)
        (dolist (candidate (window-list nil 'no-minibuffer))
          (unless (or (window-parameter candidate 'window-side)
                      (and best (< (window-use-time candidate)
                                   (window-use-time best))))
            (setq best candidate)))
        (or best (frame-first-window))))))

(defconst my/status--stray-mouse
  '([drag-mouse-1] [double-down-mouse-1] [double-mouse-1] [double-drag-mouse-1]
    [triple-down-mouse-1] [triple-mouse-1] [triple-drag-mouse-1])
  "Mouse events the bar ignores outside its items.
A click clears the message and so rewrites the bar under the mouse, which
makes Emacs see the release as a drag.  Unbound, it would reach
`mouse-set-region', which refuses the inactive minibuffer window.")

(defvar my/status--mouse-map
  (let ((map (make-sparse-keymap)))
    (dolist (key (cons [mouse-1] my/status--stray-mouse))
      (define-key map key #'ignore))
    map)
  "Parent keymap of the bar's items, which act on `down-mouse-1'.
Other mouse events, the release included, do nothing.")

(defvar my/status--saved-mouse nil
  "Bindings of `minibuffer-inactive-mode-map' replaced by the bar.")

(defun my/status--set-mouse (enable)
  "Make the idle echo area ignore stray mouse events when ENABLE, else restore.
Only the bar's items respond to the mouse; Emacs would otherwise show the
messages on a click anywhere in it."
  (if enable
      (unless my/status--saved-mouse
        (dolist (key (cons [mouse-1] my/status--stray-mouse))
          (push (cons key (lookup-key minibuffer-inactive-mode-map key))
                my/status--saved-mouse)
          (define-key minibuffer-inactive-mode-map key #'ignore)))
    (dolist (binding my/status--saved-mouse)
      (define-key minibuffer-inactive-mode-map (car binding) (cdr binding)))
    (setq my/status--saved-mouse nil)))

(defun my/status--item (text &optional action help)
  "Return TEXT, running ACTION with the click event when clicked, with HELP."
  (if (not action)
      text
    (let ((map (make-sparse-keymap)))
      (set-keymap-parent map my/status--mouse-map)
      (define-key map [down-mouse-1] (lambda (event) (interactive "e")
                                       (funcall action event)))
      (propertize text 'keymap map 'mouse-face 'my/status-hover
                  'pointer 'hand 'help-echo help))))

(defvar-local my/status--root nil
  "Project root of this buffer as (DIRECTORY . ROOT-OR-NIL), cached.")

(defun my/status--project-root ()
  "Return the root of the current buffer's project, or nil."
  (unless (equal (car my/status--root) default-directory)
    (setq my/status--root
          (cons default-directory
                (when-let* ((project (ignore-errors (project-current))))
                  (expand-file-name (project-root project))))))
  (cdr my/status--root))

(defun my/status--path ()
  "Return the current buffer's place in its project: folders › file name.
The title bar names the project and its branch (init-frame-title.el)."
  (let* ((file (or buffer-file-name
                   (and (derived-mode-p 'dired-mode) default-directory)))
         (root (and file (my/status--project-root)))
         (separator (propertize " › " 'face 'my/status-muted)))
    (if (not file)
        (propertize (buffer-name) 'face 'my/status)
      (let* ((relative (if (and root (string-prefix-p root file))
                           (substring file (length root))
                         (abbreviate-file-name file)))
             (parts (split-string relative "/" t))
             (folders (butlast parts))
             (name (car (last parts))))
        ;; Long paths keep their first and last two folders.
        (when (> (length folders) 4)
          (setq folders (append (list (car folders) "…") (last folders 2))))
        (concat (mapconcat (lambda (folder) (propertize folder 'face 'my/status-muted))
                           folders separator)
                (when folders separator)
                (propertize (or name (file-name-nondirectory
                                      (directory-file-name file)))
                            'face 'my/status))))))

(defun my/status--flags ()
  "Return the current buffer's state: modified, read-only, recording..."
  (let ((flags (delq nil
                     (list (when (and buffer-file-name (buffer-modified-p)) "●")
                           (when buffer-read-only "Read-only")
                           (when (buffer-narrowed-p) "Narrowed")
                           (when defining-kbd-macro "Recording")
                           (when current-input-method current-input-method-title)
                           (when (bound-and-true-p my/writing-layout-mode) "Reading")
                           (when (bound-and-true-p my/writing-numbering-mode)
                             "Numbering")))))
    (when flags
      (propertize (string-join flags " · ") 'face 'my/status-muted))))

(defun my/status--encoding ()
  "Return the current buffer's line ends and encoding, such as (\"LF\" \"UTF-8\")."
  (let* ((coding buffer-file-coding-system)
         ;; Plain ASCII leaves the encoding undecided until the file is
         ;; saved, which then uses the default one.
         (charset (if (eq (coding-system-base coding) 'undecided)
                      (default-value 'buffer-file-coding-system)
                    coding)))
    (list (pcase (coding-system-eol-type coding) (1 "CRLF") (2 "CR") (_ "LF"))
          (upcase (symbol-name (or (coding-system-get charset :mime-charset)
                                   (coding-system-base charset)))))))

;;;; Actions

(defun my/status-mode-menu (event)
  "Pop up the mode menu of the window the bar tells about, at EVENT."
  (with-selected-window (my/status--window)
    (popup-menu (my/ui-build-mode-menu) event)))

(defun my/status-diagnostics (_event)
  "List the diagnostics of the window the bar tells about."
  (select-window (my/status--window))
  (when (fboundp 'lsp-bridge-diagnostic-list)
    (call-interactively #'lsp-bridge-diagnostic-list)))

(defun my/status-messages (_event)
  "Show every message, including those the bar cut short.
They open as a tab of the editor window in use, rather than in a window
of their own that closing the tab would leave behind."
  (interactive (list last-input-event))
  (select-window (my/status--window))
  (pop-to-buffer-same-window (messages-buffer))
  (goto-char (point-max)))

;;;; Bar

(defun my/status--left ()
  "Return the left part of the bar for the current buffer."
  (string-join
   (delq nil (list (my/status--item (propertize "☰" 'face 'my/status)
                                    #'my/status-mode-menu "Modes and their menus")
                   (my/status--path)
                   (my/status--flags)))
   (my/ui-space my/status-gap)))

(defun my/status--right (window)
  "Return the right part of the bar for the current buffer, shown in WINDOW."
  (let* ((point (window-point window))
         (position (format "%d:%d" (line-number-at-pos point)
                           (1+ (save-excursion (goto-char point) (current-column)))))
         (encoding (my/status--encoding))
         (diagnostics (and (bound-and-true-p lsp-bridge-mode)
                           (bound-and-true-p my/ui-diagnostic-summary))))
    (string-join
     (delq nil (list (and diagnostics
                          (my/status--item diagnostics #'my/status-diagnostics
                                           "List diagnostics"))
                     (propertize position 'face 'my/status)
                     (propertize (car encoding) 'face 'my/status-muted)
                     (propertize (cadr encoding) 'face 'my/status-muted)
                     (propertize (format-mode-line mode-name nil window)
                                 'face 'my/status)))
     (my/ui-space my/status-gap))))

(defun my/status--width (text)
  "Return the width of TEXT in pixels as the bar shows it."
  (string-pixel-width text (current-buffer)))

(defun my/status--fit (text width)
  "Return TEXT cut to WIDTH pixels with an ellipsis."
  (if (<= (my/status--width text) width)
      text
    (let ((end (length text)))
      (while (and (> end 0)
                  (> (my/status--width (concat (substring text 0 end) "…")) width))
        (setq end (max 0 (- end (max 1 (/ (- end 1) 8))))))
      (concat (substring text 0 end) "…"))))

(defun my/status--message-text (room left-width right-width total)
  "Return the message placed between LEFT-WIDTH and RIGHT-WIDTH pixels.
ROOM is the width free for it and TOTAL the bar's; nil when it has no room."
  (when (and my/status--message (> room 40))
    (let* ((lines (split-string my/status--message "\n"))
           (line (if (cdr lines) (concat (car lines) " …") (car lines)))
           (text (my/status--fit (propertize line 'face 'my/status) room))
           (width (my/status--width text))
           ;; Centered in the frame when there is room, else just after
           ;; the left part.
           (x (max (+ left-width my/status-gap)
                   (min (/ (- total width) 2)
                        (- total right-width my/status-gap width)))))
      (concat (my/ui-space-to x)
              (my/status--item text #'my/status-messages "Show all messages")))))

(defun my/status--compose (window)
  "Return the bar's text about WINDOW, in the echo area's current buffer."
  (let* ((buffer (window-buffer window))
         (left (with-current-buffer buffer (my/status--left)))
         (right (with-current-buffer buffer (my/status--right window)))
         (total (window-body-width (minibuffer-window) t))
         (left-width (my/status--width left))
         (right-width (my/status--width right)))
    (concat left
            (my/status--message-text (- total left-width right-width
                                        (* 2 my/status-gap))
                                     left-width right-width total)
            (my/ui-at-right right nil (current-buffer)))))

(defun my/status-update (&rest _)
  "Redraw the bar about the editor window in use."
  (when (and (display-graphic-p) (not (active-minibuffer-window)))
    (let ((echo (window-buffer (minibuffer-window))))
      ;; The idle echo area shows the inactive minibuffer's text; while a
      ;; message or prompt occupies it, the bar waits.
      (when (equal (buffer-name echo) " *Minibuf-0*")
        (with-current-buffer echo
          (let ((text (ignore-errors (my/status--compose (my/status--window)))))
            (when (and text (not (equal-including-properties text my/status--last)))
              (setq my/status--last text)
              (let ((inhibit-read-only t)
                    (inhibit-modification-hooks t))
                (erase-buffer)
                (insert text))
              (my/status--fit-echo-area))))))))

(defun my/status--fit-echo-area ()
  "Make the echo area as tall as the bar.
Resizing the frame, as when entering full screen, gives the echo area
back its height of one line, which cuts off the bar's spacing."
  (let* ((window (minibuffer-window))
         (height (cdr (window-text-pixel-size window))))
    (when (and (> height 0) (/= height (window-pixel-height window)))
      (window--resize-mini-window window (- height (window-pixel-height window))))))

(defun my/status--resized (_frame)
  "Redraw the bar for the frame's new size."
  (setq my/status--last nil)
  (my/status-update))

(defun my/status--after-minibuffer ()
  "Redraw the bar once the minibuffer has closed."
  (setq my/status--last nil)
  (run-at-time 0 nil #'my/status-update))

;;;; Messages

(defun my/status--set-message (message)
  "Show MESSAGE in the middle of the bar instead of the echo area.
Messages while the minibuffer is open, and in terminal frames, go on as
usual."
  (when (and (display-graphic-p) (not (active-minibuffer-window))
             (stringp message))
    (setq my/status--message (unless (string-empty-p message) message))
    (my/status-update)
    t))

(defun my/status--clear-message ()
  "Clear the bar's message, as the next input event clears the echo area.
The bar is redrawn once that event is handled: a click on the message
must still find it under the mouse."
  (when my/status--message
    (setq my/status--message nil)
    (run-at-time 0 nil #'my/status-update))
  (clear-minibuffer-message))

(defvar my/status--command-error nil
  "The `command-error-function' the bar's replaced, called outside of it.")

(defun my/status--command-error (data context signal)
  "Report the error DATA of a command, after CONTEXT, in the bar.
Errors are written into the echo area directly, without
`set-message-functions'.  SIGNAL is the function that signaled it."
  (if (and (display-graphic-p) (not (active-minibuffer-window)))
      (progn
        (discard-input)
        (ding)
        (message "%s%s" (or context "") (error-message-string data)))
    (funcall (or my/status--command-error #'command-error-default-function)
             data context signal)))

;;;; Mode

(defun my/status--prepare-echo-area ()
  "Give the echo area's buffers the bar's height."
  (dolist (name '(" *Minibuf-0*" " *Echo Area 0*" " *Echo Area 1*"))
    (with-current-buffer (get-buffer-create name)
      (setq-local line-spacing my/status-spacing
                  truncate-lines t))))

(defvar my/status--timer nil
  "Timer refreshing what changes without a command, such as diagnostics.")

(define-minor-mode my/status-mode
  "Show one status bar along the bottom of graphical frames."
  :global t
  :group 'mode-line
  (when (timerp my/status--timer) (cancel-timer my/status--timer))
  (if my/status-mode
      (progn
        (my/status--prepare-echo-area)
        (my/status--set-mouse t)
        ;; As tall as the cards' corners, or a one-pixel rule without them.
        (setq my/ui-mode-line-pixels
              (if (bound-and-true-p my/islands-mode) my/islands-radius 1))
        (advice-add 'my/ui-status-line :around #'my/status--mode-line
                    ;; Inside Islands' corners.
                    '((depth . 90)))
        (with-eval-after-load 'init-dirvish
          (when my/status-mode
            (advice-add 'my/dirvish-side-bars :after #'my/status--dirvish-bars
                        '((depth . 90)))))
        (setq set-message-functions
              (append (remq 'my/status--set-message set-message-functions)
                      '(my/status--set-message))
              clear-message-function #'my/status--clear-message)
        (unless (eq command-error-function #'my/status--command-error)
          (setq my/status--command-error command-error-function
                command-error-function #'my/status--command-error))
        (add-hook 'post-command-hook #'my/status-update 90)
        (add-hook 'window-selection-change-functions #'my/status-update)
        (add-hook 'window-buffer-change-functions #'my/status-update)
        (add-hook 'window-size-change-functions #'my/status--resized)
        (add-hook 'minibuffer-exit-hook #'my/status--after-minibuffer)
        (setq my/status--timer (run-with-timer 1 1 #'my/status-update))
        (my/status-update))
    (setq my/ui-mode-line-pixels nil)
    (my/status--set-mouse nil)
    (advice-remove 'my/ui-status-line #'my/status--mode-line)
    (advice-remove 'my/dirvish-side-bars #'my/status--dirvish-bars)
    (setq set-message-functions (remq 'my/status--set-message set-message-functions)
          clear-message-function #'clear-minibuffer-message
          command-error-function (if (eq command-error-function
                                         #'my/status--command-error)
                                     (or my/status--command-error
                                         #'command-error-default-function)
                                   command-error-function)
          my/status--message nil
          my/status--last nil)
    (remove-hook 'post-command-hook #'my/status-update)
    (remove-hook 'window-selection-change-functions #'my/status-update)
    (remove-hook 'window-buffer-change-functions #'my/status-update)
    (remove-hook 'window-size-change-functions #'my/status--resized)
    (remove-hook 'minibuffer-exit-hook #'my/status--after-minibuffer)
    (with-current-buffer (get-buffer-create " *Minibuf-0*")
      (let ((inhibit-read-only t)) (erase-buffer)))
    (dolist (name '(" *Minibuf-0*" " *Echo Area 0*" " *Echo Area 1*"))
      (with-current-buffer (get-buffer-create name)
        (kill-local-variable 'line-spacing))))
  (force-mode-line-update t))

(provide 'init-status)
;;; init-status.el ends here
