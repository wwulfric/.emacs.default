;;; init-acm-icons.el --- Expui icons for ACM -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'seq)
(require 'acm-icon)
(require 'expui-icons)

(defvar acm-enable-icon)

(defconst my/acm-icon-groups
  '(("nodes/word" "unknown" "text" "string" "note")
    ("nodes/method" "method")
    ("nodes/function" "function" "fun" "macro" "special form")
    ("nodes/constructor" "constructor" "ctor")
    ("general/search" "search" "workspace-symbol")
    ("nodes/field" "field" "member" "enum-member" "enummember")
    ("nodes/variable" "variable" "var" "array")
    ("nodes/class" "class" "object" "instance")
    ("nodes/interface" "interface" "i/f")
    ("nodes/module" "module" "mod" "feature")
    ("nodes/package" "package" "namespace")
    ("nodes/property" "property" "prop")
    ("nodes/constant" "constant" "const" "value" "number" "boolean" "null" "unit")
    ("nodes/enum" "enum")
    ("nodes/record" "struct")
    ("nodes/type" "type-parameter" "typeparam" "typeparameter" "typedef")
    ("nodes/parameter" "param")
    ("nodes/template" "snippet" "yas-snippet" "template" "sn" "emmet abbreviation")
    ("gutter/colors" "color" "face")
    ("text" "file")
    ("nodes/folder" "folder" "dir")
    ("nodes/annotation" "at"))
  "ACM kind aliases grouped by bundled Expui resource.
Kinds without a specific mapping use the neutral word icon.")

(defun my/acm-expui-image (original collection name color)
  "Render Expui COLLECTION entries; delegate other entries to ORIGINAL."
  (if (equal collection "expui")
      (expui-icons-image name :margin
                         (cons (max 0 (floor (- (* acm-icon-width (frame-char-width))
                                                expui-icons-height) 2)) 0))
    (funcall original collection name color)))

(defun my/acm-expui-build (original collection name color)
  "Keep ACM's character column while letting Expui manage image caching."
  (if (not (equal collection "expui"))
      (funcall original collection name color)
    (if (and acm-enable-icon (expui-icons-svg-p))
        (propertize (make-string acm-icon-width ?\s)
                    'display (acm-icon collection name color))
      "")))

;; Copy the mapping rather than altering the vendored package's data in place.
(setq acm-icon-alist
      (mapcar (lambda (entry)
                (list (car entry) "expui"
                      (or (car (seq-find (lambda (group)
                                           (member (car entry) (cdr group)))
                                         my/acm-icon-groups))
                          "nodes/word")
                      nil))
              acm-icon-alist))
(advice-add 'acm-icon :around #'my/acm-expui-image)
(advice-add 'acm-icon-build :around #'my/acm-expui-build)
(clrhash acm-icon-cache)

(provide 'init-acm-icons)
