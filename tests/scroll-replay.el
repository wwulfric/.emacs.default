;;; scroll-replay.el --- Replay touchpad scrolling in a live Emacs -*- lexical-binding: t; -*-

;;; Commentary:

;; Checks that nothing changes the layout while the editor scrolls by
;; pixels.  Any change to a window's size, fringes or margins mid-scroll
;; resets the pixel offset, and the view jumps back.
;;
;; Calling the scroll commands from Lisp, even with `redisplay', does not
;; show the problem.  This sends `wheel-up' events with pixel deltas
;; through the real command loop, one per timer step, so each is redrawn
;; before the next arrives.  Between the end of one scroll command and
;; the next event the view must stay where the command left it.
;;
;; Load it into the running GUI Emacs and start a replay:
;;
;;   emacsclient --eval '(progn (load "~/.emacs.d/tests/scroll-replay.el" nil t)
;;                              (scroll-replay-run (selected-window) "/tmp/replay.eld"))'
;;
;; The result is written to the file once the replay ends, a few seconds
;; later: :jumps should be 0, and :writes should name no layout writer.
;; The window's view is restored afterwards.

;;; Code:

(require 'cl-lib)

(defconst scroll-replay-writers
  '(window--resize-mini-window window-resize adjust-window-trailing-edge
    set-window-fringes set-window-margins set-window-scroll-bars
    git-islands-pane-fit my/status--fit-echo-area)
  "Functions that change, or try to change, the layout.")

(defvar scroll-replay--state nil
  "Plist of the replay under way.")

(defun scroll-replay--snapshot (window)
  "Return WINDOW's view and size, and the echo area's height."
  (list (window-start window) (window-vscroll window t)
        (window-pixel-width window) (window-pixel-height window)
        (window-pixel-height (minibuffer-window (window-frame window)))))

(defun scroll-replay--count (function &rest _)
  "Count a call to the layout writer FUNCTION, with its caller."
  (let ((caller (cl-loop for i from 3 to 15
                         for frame = (backtrace-frame i)
                         for f = (cadr frame)
                         when (and (car frame) (symbolp f) (fboundp f)
                                   (not (special-form-p f)) (not (macrop f))
                                   (not (memq f scroll-replay-writers))
                                   (not (memq f '(apply funcall apply-partially
                                                  scroll-replay--count))))
                         return f)))
    (cl-incf (alist-get (cons function caller)
                        (plist-get scroll-replay--state :writes) 0 nil #'equal))))

(defun scroll-replay--after-command ()
  "Record the view a scroll command left."
  (when (memq this-command '(pixel-scroll-precision mwheel-scroll))
    (plist-put scroll-replay--state :after
               (scroll-replay--snapshot (plist-get scroll-replay--state :window)))))

(defun scroll-replay--step ()
  "Compare the view with the last command's, then send the next event."
  (let* ((state scroll-replay--state)
         (window (plist-get state :window))
         (now (scroll-replay--snapshot window))
         (after (plist-get state :after)))
    (when (and after (not (equal (cl-subseq now 0 2) (cl-subseq after 0 2))))
      (plist-put state :jumps (cons (list :event (plist-get state :sent)
                                          :after after :next now)
                                    (plist-get state :jumps))))
    (if (>= (plist-get state :sent) (plist-get state :events))
        (scroll-replay--finish)
      (plist-put state :sent (1+ (plist-get state :sent)))
      (setq unread-command-events
            (append unread-command-events
                    `((wheel-up ,(posn-at-x-y 100 100 window) 1 nil
                                (0.0 . ,(float (plist-get state :delta)))))))
      (run-at-time (plist-get state :interval) nil #'scroll-replay--step))))

(defun scroll-replay--cleanup ()
  "Remove the replay's hooks and advice."
  (remove-hook 'post-command-hook #'scroll-replay--after-command)
  (dolist (function scroll-replay-writers)
    (advice-remove function 'scroll-replay)))

(defun scroll-replay--finish ()
  "Restore the window's view and write the result."
  (scroll-replay--cleanup)
  (let* ((state scroll-replay--state)
         (window (plist-get state :window))
         (saved (plist-get state :saved)))
    (when (window-live-p window)
      (set-window-start window (car saved) t)
      (set-window-vscroll window 0 t)
      (set-window-point window (cdr saved)))
    (with-temp-file (plist-get state :out)
      (let ((print-length nil) (print-level nil))
        (prin1 (list :events (plist-get state :sent)
                     :jumps (length (plist-get state :jumps))
                     :writes (plist-get state :writes)
                     :first-jumps (seq-take (reverse (plist-get state :jumps)) 10))
               (current-buffer))))
    (setq scroll-replay--state nil)))

(cl-defun scroll-replay-run (window out &key (events 45) (delta 14)
                                    (interval 0.06) (from 300))
  "Scroll WINDOW up by EVENTS wheel events of DELTA pixels; result to OUT.
Start FROM lines below the window's start.  Send one event every
INTERVAL seconds."
  (when scroll-replay--state
    (error "A replay is already under way"))
  (setq scroll-replay--state
        (list :window window :out (expand-file-name out)
              :events events :delta delta :interval interval
              :sent 0 :after nil :jumps nil :writes nil
              :saved (cons (window-start window) (window-point window))))
  (with-selected-window window
    (save-excursion
      (goto-char (window-start window))
      (forward-line from)
      (set-window-start window (point) t))
    (set-window-vscroll window 0 t))
  (select-window window)
  (dolist (function scroll-replay-writers)
    (when (fboundp function)
      (advice-add function :before (apply-partially #'scroll-replay--count function)
                  '((name . scroll-replay)))))
  (add-hook 'post-command-hook #'scroll-replay--after-command)
  (run-at-time 0.3 nil #'scroll-replay--step)
  t)

(provide 'scroll-replay)
;;; scroll-replay.el ends here
