;;; dirvish-display-tests.el --- Sidebar rendering regression -*- lexical-binding: t; -*-

(require 'ert)
(require 'init-dirvish)

(ert-deftest my-dirvish-renders-attributes-without-selecting-sidebar ()
  "Opening from the editor must paint attributes before any focus change."
  (let* ((directory (make-temp-file "dirvish-display-" t))
         (folder (expand-file-name "folder" directory))
         (editor (selected-window)))
    (unwind-protect
        (progn
          (make-directory folder)
          (my/dirvish-show directory)
          (should (eq editor (selected-window)))
          (with-current-buffer (window-buffer (dirvish-side--session-visible-p))
            (should
             (seq-some
              (lambda (ov)
                (let ((text (overlay-get ov 'after-string)))
                  (and (overlay-get ov 'dirvish-a-ov)
                       text (not (string-blank-p text)))))
              (overlays-in (point-min) (point-max))))))
      (when-let* ((window (dirvish-side--session-visible-p)))
        (with-selected-window window (dirvish-quit)))
      (delete-directory directory t))))

(ert-deftest my-dirvish-toggle-from-external-source ()
  "Cached dependency sources must not be expanded inside the saved project."
  (let* ((directory (make-temp-file "dirvish-project-" t))
         (external (make-temp-file (concat directory "-external-") t))
         (source (expand-file-name "Traversable.hs" external))
         (saved-root (frame-parameter nil 'my/dirvish-directory))
         (editor-buffer (current-buffer))
         (buffer (generate-new-buffer " *dirvish-external-test*")))
    (unwind-protect
        (progn
          (with-temp-file source (insert "module Traversable where\n"))
          (make-directory (expand-file-name "src" directory))
          (switch-to-buffer buffer)
          (setq-local buffer-file-name source
                      default-directory (file-name-as-directory external))
          (set-frame-parameter nil 'my/dirvish-directory directory)
          (dotimes (_ 3)
            (my/dirvish-toggle)
            (should (eq (selected-window) (dirvish-side--session-visible-p)))
            (should (equal default-directory (file-name-as-directory directory)))
            (my/dirvish-toggle)
            (should-not (dirvish-side--session-visible-p))
            (should (eq (current-buffer) buffer))
            (should (equal buffer-file-name source))))
      (when-let* ((window (dirvish-side--session-visible-p)))
        (with-selected-window window (dirvish-quit)))
      (switch-to-buffer editor-buffer)
      (kill-buffer buffer)
      (set-frame-parameter nil 'my/dirvish-directory saved-root)
      (delete-directory directory t)
      (delete-directory external t))))

(ert-deftest my-dirvish-still-expands-project-source ()
  "Files inside the sidebar root should still be selected in nested folders."
  (let* ((directory (make-temp-file "dirvish-project-" t))
         (source (expand-file-name "src/nested/Main.hs" directory))
         (saved-root (frame-parameter nil 'my/dirvish-directory))
         (editor-buffer (current-buffer))
         (buffer (generate-new-buffer " *dirvish-project-test*")))
    (unwind-protect
        (progn
          (make-directory (file-name-directory source) t)
          (with-temp-file source (insert "module Main where\n"))
          (switch-to-buffer buffer)
          (setq-local buffer-file-name source)
          (my/dirvish-show directory)
          (should (eq (current-buffer) buffer))
          (should (equal buffer-file-name source))
          (with-current-buffer (window-buffer (dirvish-side--session-visible-p))
            (should (equal (dired-get-filename) source))))
      (when-let* ((window (dirvish-side--session-visible-p)))
        (with-selected-window window (dirvish-quit)))
      (switch-to-buffer editor-buffer)
      (kill-buffer buffer)
      (set-frame-parameter nil 'my/dirvish-directory saved-root)
      (delete-directory directory t))))

(ert-deftest my-dirvish-long-name-tooltip-is-on-displayed-text ()
  "Replacing a long name must preserve its hover target and full name."
  (with-temp-buffer
    (insert "  a-very-long-folder-name")
    (cl-letf (((symbol-function 'dirvish-subtree--depth) (lambda () 0))
              ((symbol-function 'truncate-string-pixelwise)
               (lambda (&rest _) "a-very…")))
      (let* ((result (dirvish-attribute-my-sidebar-name-rd
                      3 (point-max) "a-very-long-folder-name" "/root/a-very-long-folder-name"
                      nil '(dir) 1 (point-max) nil 30))
             (text (overlay-get (cdr result) 'display)))
        (should (equal (get-text-property 0 'help-echo text)
                       "a-very-long-folder-name"))
        (should (eq (get-text-property 0 'pointer text) 'hand))
        (should-not (get-text-property 0 'mouse-face text))
        (should (eq (lookup-key (get-text-property 0 'local-map text) [mouse-1])
                    'my/dirvish-mouse-open))))))

(ert-deftest my-dirvish-drag-resizes-without-selecting-sidebar ()
  "Dragging the gap from editor focus must change the actual sidebar width."
  (let ((directory (make-temp-file "dirvish-resize-" t)))
    (unwind-protect
        (progn
          (my/dirvish-show directory)
          (let* ((window (dirvish-side--session-visible-p))
                 (editor (selected-window))
                 (before (window-pixel-width window))
                 (start (list window 'right-fringe '(20 . 20) 0))
                 (end (list window 'right-fringe '(10 . 20) 0))
                 (release (list 'drag-mouse-1 start end))
                 (events (list (list 'mouse-movement
                                     (list window nil '(15 . 20) 0)) release)))
            (with-current-buffer (window-buffer window)
              (should-not window-size-fixed))
            (cl-letf (((symbol-function 'read-event)
                       (lambda (&rest _)
                         (when (= (length events) 1)
                           ;; Width changes before mouse release, not afterward.
                           (should (= (window-pixel-width window) (- before 5))))
                         (pop events))))
              (my/dirvish-drag-divider (list 'down-mouse-1 start)))
            (should (= (window-pixel-width window) (- before 10)))
            (should (eq (selected-window) editor))))
      (when-let* ((window (dirvish-side--session-visible-p)))
        (with-selected-window window (dirvish-quit)))
      (delete-directory directory t))))

(ert-deftest my-dirvish-render-cache-invalidates-on-resize ()
  "Reuse unchanged rows but recalculate shortened names after resizing."
  (let ((directory (make-temp-file "dirvish-render-cache-" t)))
    (unwind-protect
        (progn
          (my/dirvish-show directory)
          (let* ((window (dirvish-side--session-visible-p))
                 (calls 0)
                 (render (lambda (&rest _) (cl-incf calls))))
            (set-window-parameter window 'my/dirvish-render-state nil)
            (my/dirvish-render-if-changed render window)
            (my/dirvish-render-if-changed render window)
            (should (= calls 1))
            (adjust-window-trailing-edge window -10 t t)
            (my/dirvish-render-if-changed render window)
            (should (= calls 2))))
      (when-let* ((window (dirvish-side--session-visible-p)))
        (with-selected-window window (dirvish-quit)))
      (delete-directory directory t))))

(ert-deftest my-dirvish-name-measurements-reused-until-resize ()
  (with-temp-buffer
    (let ((width 200) (calls 0))
      (cl-letf (((symbol-function 'window-body-width) (lambda (&rest _) width))
                ((symbol-function 'truncate-string-pixelwise)
                 (lambda (text &rest _) (cl-incf calls) text)))
        (my/dirvish-fit-name "long-file-name.el" 2)
        (my/dirvish-fit-name "long-file-name.el" 2)
        (should (= calls 1))
        (setq width 250)
        (my/dirvish-fit-name "long-file-name.el" 2)
        (should (= calls 2))))))

(ert-deftest my-dirvish-touchpad-deltas-accumulate-by-row ()
  (let ((directory (make-temp-file "dirvish-scroll-" t)))
    (unwind-protect
        (progn
          (my/dirvish-show directory)
          (let ((window (dirvish-side--session-visible-p)) calls)
            (with-selected-window window
              (setq my/dirvish-scroll-remainder 0)
              (cl-letf (((symbol-function 'mwheel-event-window) (lambda (_) window))
                        ((symbol-function 'line-pixel-height) (lambda () 10))
                        ((symbol-function 'scroll-up) (lambda (n) (push n calls)))
                        ((symbol-function 'scroll-down) (lambda (n) (push (- n) calls)))
                        ((symbol-function 'dirvish--render-attrs) #'ignore))
                (dotimes (_ 3) (my/dirvish-scroll '(wheel-up nil nil nil (0 . 3))))
                (should-not calls)
                (my/dirvish-scroll '(wheel-up nil nil nil (0 . 3)))
                (should (equal calls '(-1)))
                (my/dirvish-scroll '(wheel-down nil nil nil (0 . -3)))
                (my/dirvish-scroll '(wheel-down nil nil nil (0 . -7)))
                (should (equal calls '(1 -1)))
                ;; Direction follows the wheel event even if its raw delta
                ;; has the opposite sign (as on macOS touchpads).
                (my/dirvish-scroll '(wheel-up nil nil nil (0 . -10)))
                (should (equal calls '(-1 1 -1)))
                (my/dirvish-scroll '(wheel-down nil nil nil (0 . 10)))
                (should (equal calls '(1 -1 1 -1)))
                (should (zerop (window-vscroll window t)))))))
      (when-let* ((window (dirvish-side--session-visible-p)))
        (with-selected-window window (dirvish-quit)))
      (delete-directory directory t))))

;;; dirvish-display-tests.el ends here
