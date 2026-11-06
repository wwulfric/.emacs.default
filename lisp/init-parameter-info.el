;;; init-parameter-info.el --- IntelliJ's Parameter Info and inlay hints -*- lexical-binding: t; -*-

;;; Commentary:
;; Parameter Info: S-s-SPC (Cmd-Shift-Space, VS Code's key for it, as
;; Cmd-P is the search here) shows the parameters of the call around the
;; caret above it, the one being typed in bold, every overload on a line
;; of its own and those that do not match dimmed.  It also opens by itself
;; after typing "(" or ",", and stays while the caret is inside the call,
;; following it from argument to argument, as in IntelliJ.
;;
;; Inlay hints: the language server's parameter names and types, drawn in
;; the code in small gray type.  M-x my/inlay-hints-toggle turns them off.

;;; Code:

(require 'lsp-bridge)
(require 'acm-frame)
(require 'seq)

(defvar my/ui-popup-padding)

(setq lsp-bridge-enable-inlay-hint t)

;;;; Parameter Info

(defconst my/parameter-info--buffer " *parameter-info*")

(defvar my/parameter-info--frame nil)

(defvar my/parameter-info--call nil
  "The call shown: a marker at its opening bracket, or at point without one.")

(defvar my/parameter-info--asked nil
  "(BUFFER POINT) where Parameter Info was asked for, until it shows.")

(defvar-local my/parameter-info--tick nil
  "The buffer's modification count after the last command.")

(defvar my/parameter-info--typed nil
  "Non-nil when the last command typed the start of an argument.")

(defun my/parameter-info--open ()
  "Return the position of the innermost bracket around point, or nil."
  (car (last (nth 9 (syntax-ppss)))))

(defun my/parameter-info--visible-p ()
  "Return non-nil when Parameter Info is showing."
  (and (frame-live-p my/parameter-info--frame)
       (frame-visible-p my/parameter-info--frame)))

(defun my/parameter-info-hide ()
  "Hide Parameter Info."
  (interactive)
  (when (my/parameter-info--visible-p)
    (acm-frame-hide-frame my/parameter-info--frame))
  (when (markerp my/parameter-info--call)
    (set-marker my/parameter-info--call nil))
  (setq my/parameter-info--call nil))

(defun my/parameter-info--extent (label from limit)
  "Return where the parameter at FROM in LABEL ends, at most LIMIT.
Some servers name only the parameter, its type and default following it,
so it runs to the next comma or closing bracket outside brackets."
  (let ((depth 0) (index from) end)
    (while (and (not end) (< index limit))
      (pcase (aref label index)
        ((or ?\( ?\[ ?\{) (setq depth (1+ depth)))
        ((or ?\) ?\] ?\}) (if (zerop depth) (setq end index) (setq depth (1- depth))))
        (?, (when (zerop depth) (setq end index))))
      (setq index (1+ index)))
    (let ((end (or end limit)))
      (while (and (> end from) (memq (aref label (1- end)) '(?\s ?\t)))
        (setq end (1- end)))
      end)))

(defun my/parameter-info--line (signature matches)
  "Return SIGNATURE's parameters as one line, the active one in bold.
MATCHES says the call is to SIGNATURE; the other overloads are dimmed."
  (pcase-let* ((`(,label ,ranges ,current) signature)
               (size (length label))
               (ranges (seq-filter (pcase-lambda (`(,start ,end))
                                     (<= 0 start end size))
                                   ranges))
               ;; Each parameter whole: (START END).
               (parameters
                (seq-map-indexed
                 (pcase-lambda (`(,start ,end) index)
                   (let ((next (car (nth (1+ index) ranges))))
                     (list start (my/parameter-info--extent label end (or next size)))))
                 ranges)))
    (if (null parameters)
        (propertize "<no parameters>" 'face 'shadow)
      (let* ((start (car (car parameters)))
             (text (substring label start (cadr (car (last parameters))))))
        (if (not matches)
            (add-face-text-property 0 (length text) 'shadow t text)
          (when (< -1 current (length parameters))
            (pcase-let ((`(,from ,to) (nth current parameters)))
              (add-face-text-property (- from start) (- to start) 'bold t text))))
        text))))

(defun my/parameter-info--bracket-p (position)
  "Return non-nil when an opening bracket is at POSITION."
  (and (char-after position) (eq (char-syntax (char-after position)) ?\()))

(defun my/parameter-info--place ()
  "Put Parameter Info above the call's arguments, or below when no room.
Return nil when neither the call nor point is in sight."
  (when-let* ((frame my/parameter-info--frame)
              (call (and my/parameter-info--call
                         (marker-position my/parameter-info--call)))
              (anchor (if (my/parameter-info--bracket-p call) (1+ call) call))
              (shown (cond ((pos-visible-in-window-p anchor) anchor)
                           ((pos-visible-in-window-p (point)) (point)))))
    ;; From the window's text area: `window-absolute-pixel-position'
    ;; counts the header line twice.
    (let* ((position (posn-x-y (posn-at-point shown)))
           (edges (window-inside-pixel-edges))
           (line-top (+ (nth 1 edges) (cdr position)))
           (height (frame-pixel-height frame))
           (gap 2)
           (y (if (>= (- line-top height gap) (nth 1 edges))
                  (- line-top height gap)
                (+ line-top (line-pixel-height) gap)))
           ;; Line the popup's text up with the arguments.
           (x (- (+ (nth 0 edges) (car position))
                 (car (window-inside-pixel-edges (frame-root-window frame)))))
           (x (max 0 (min x (- (frame-pixel-width) (frame-pixel-width frame))))))
      (unless (equal (frame-position frame) (cons x y))
        (set-frame-position frame x y))
      t)))

(defun my/parameter-info--show (signatures active-signature)
  "Show SIGNATURES, the call being to the ACTIVE-SIGNATURE'th, if wanted.
Called with a language server's signature help; shows it when asked
for, when an argument was just started, or to follow the shown call."
  (with-current-buffer (window-buffer (selected-window))
    (let ((open (my/parameter-info--open))
          (asked (equal my/parameter-info--asked (list (current-buffer) (point)))))
      (when (and (display-graphic-p)
                 (or asked
                     (and open (or my/parameter-info--typed
                                   (my/parameter-info--visible-p)))))
        (setq my/parameter-info--asked nil)
        (with-current-buffer (get-buffer-create my/parameter-info--buffer)
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert (mapconcat #'identity
                               (seq-map-indexed
                                (lambda (signature index)
                                  (my/parameter-info--line signature (= index active-signature)))
                                signatures)
                               "\n"))))
        (unless (and (markerp my/parameter-info--call)
                     (eq (marker-buffer my/parameter-info--call) (current-buffer))
                     (eql (marker-position my/parameter-info--call) (or open (point))))
          (when (markerp my/parameter-info--call)
            (set-marker my/parameter-info--call nil))
          (setq my/parameter-info--call (copy-marker (or open (point)))))
        (acm-frame-new my/parameter-info--frame my/parameter-info--buffer
                       "parameter info frame"
                       (max 20 (min 120 (- (window-body-width) 4))) 10)
        (my/parameter-info--place)))))

(setq lsp-bridge-signature-help-function #'my/parameter-info--show)

(defun my/parameter-info--still-p ()
  "Return non-nil when point is still in the call shown."
  (let ((call my/parameter-info--call))
    (and (markerp call)
         (eq (marker-buffer call) (current-buffer))
         (not (memq this-command '(keyboard-quit keyboard-escape-quit)))
         (if (my/parameter-info--bracket-p call)
             (memql (marker-position call) (nth 9 (syntax-ppss)))
           ;; A call without brackets lasts while point is on its line.
           (= (line-number-at-pos call) (line-number-at-pos))))))

(defun my/parameter-info--post-command ()
  "Note a typed argument start; hide or move Parameter Info with point."
  (unless (eq my/parameter-info--tick (buffer-chars-modified-tick))
    (setq my/parameter-info--tick (buffer-chars-modified-tick))
    (setq my/parameter-info--typed
          (and (not (minibufferp))
               (memq (char-before (save-excursion (skip-chars-backward " \t\n") (point)))
                     '(?\( ?,)))))
  (when (my/parameter-info--visible-p)
    (unless (and (my/parameter-info--still-p) (my/parameter-info--place))
      (my/parameter-info-hide))))

(add-hook 'post-command-hook #'my/parameter-info--post-command)

(defun my/parameter-info ()
  "Show the parameters of the call around point, as Cmd-P does in IntelliJ."
  (interactive)
  (unless (lsp-bridge-has-lsp-server-p)
    (user-error "No language server for this buffer"))
  (let ((asked (list (current-buffer) (point))))
    (setq my/parameter-info--asked asked)
    (lsp-bridge-call-file-api "signature_help" (lsp-bridge--position))
    (run-at-time 1 nil (lambda ()
                         (when (equal my/parameter-info--asked asked)
                           (setq my/parameter-info--asked nil)
                           (message "No parameters to show here"))))))

(keymap-global-set "S-s-SPC" #'my/parameter-info)

;;;; Inlay hints

(defun my/inlay-hints-toggle ()
  "Turn the language server's inlay hints on or off."
  (interactive)
  (setq lsp-bridge-enable-inlay-hint (not lsp-bridge-enable-inlay-hint))
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (bound-and-true-p lsp-bridge-mode)
        (lsp-bridge-inlay-hint-hide-overlays)
        (setq-local lsp-bridge-inlay-hint-cache nil
                    ;; Ask again on the next command there.
                    lsp-bridge-inlay-hint-last-update-pos nil)
        (when (and lsp-bridge-enable-inlay-hint (get-buffer-window buffer t))
          (lsp-bridge-inlay-hint-try-send-request)))))
  (message "Inlay hints %s" (if lsp-bridge-enable-inlay-hint "on" "off")))

(provide 'init-parameter-info)
;;; init-parameter-info.el ends here
