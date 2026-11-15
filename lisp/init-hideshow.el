;;; init-hideshow.el --- Clickable folding in the editor gutter -*- lexical-binding: t; -*-

(require 'hideshow)

;; Git hunks occupy the fringe.  Hideshow reserves its own margin column
;; when the mode starts, so the two indicators can share a line.
(setq hs-show-indicators t
      hs-indicator-type 'margin)
(keymap-unset hs-minor-mode-map "<left-fringe> <mouse-1>")
(keymap-set hs-minor-mode-map "<left-margin> <mouse-1>"
            #'hs-indicator-mouse-toggle-hiding)

;; Hideshow's icon API accepts image filenames and supplies a TTY fallback.
(let ((icons (expand-file-name "expui-icons/icons/gutter/"
                               (file-name-directory load-file-name))))
  (custom-set-icons
   `(hs-indicator-hide ((image ,(expand-file-name "fold.svg" icons) :width font)))
   `(hs-indicator-show ((image ,(expand-file-name "unfold.svg" icons) :width font)))))

(defface my/hideshow-placeholder '((t :inherit secondary-selection))
  "Background of a folded brace block.")

(defun my/hideshow-brace-range (original &optional adjust-beg adjust-end)
  "Include the braces in the displayed fold so the whole label is clickable."
  (let ((range (funcall original adjust-beg adjust-end)))
    (if (and adjust-beg adjust-end range
             (eq (char-before (car range)) ?{)
             (eq (char-after (cadr range)) ?}))
        (list (1- (car range)) (1+ (cadr range)))
      range)))

(advice-add 'hs-block-positions :around #'my/hideshow-brace-range)

(defun my/hideshow-align-ellipsis (overlay)
  "Use three code-font periods in OVERLAY's fold label."
  (let ((label (overlay-get overlay 'display)))
    (when (stringp label)
      ;; The display-table ellipsis can include a leading space.
      (setq label (string-trim-left label))
      (when-let* ((i (string-search "…" label)))
        (setq label (concat (substring label 0 i)
                            (apply #'propertize "..." (text-properties-at i label))
                            (substring label (1+ i)))))
      (when (and (eq (overlay-get overlay 'hs) 'code)
                 (eq (char-after (overlay-start overlay)) ?{)
                 (eq (char-before (overlay-end overlay)) ?}))
        (let ((props (list 'keymap (get-text-property 0 'keymap label)
                           'help-echo (get-text-property 0 'help-echo label))))
          (setq label (concat (apply #'propertize "{" props)
                              label (apply #'propertize "}" props)))
          (add-face-text-property 0 (length label) 'my/hideshow-placeholder nil label)
          (put-text-property 0 (length label) 'mouse-face 'highlight label)))
      (overlay-put overlay 'display label))))

(setq hs-set-up-overlay #'my/hideshow-align-ellipsis)

(defun my/enable-code-folding ()
  "Enable Hideshow once in programming modes that support comments."
  (when (and comment-start comment-end (not hs-minor-mode))
    (hs-minor-mode 1)))

(add-hook 'prog-mode-hook #'my/enable-code-folding)

(provide 'init-hideshow)
;;; init-hideshow.el ends here
