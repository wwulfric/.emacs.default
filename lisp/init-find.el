;;; init-find.el --- Keys of the Find and Problems tool windows -*- lexical-binding: t; -*-

;;; Commentary:
;; IntelliJ's Find (s-3) and Problems (s-6) tool windows, along the
;; frame's bottom; bottom-tools.el draws them and loads on first use.
;; Find Usages (M-<f7>) lists usages there, and M-s-<down> / M-s-<up> step
;; through them; Show Usages (M-s-<f7>) keeps the popup beside the symbol.

;;; Code:

(autoload 'my/find-toggle "bottom-tools" nil t)
(autoload 'my/find-usages "bottom-tools" nil t)
(autoload 'my/find-show "bottom-tools")
(autoload 'my/find-next-occurrence "bottom-tools" nil t)
(autoload 'my/find-previous-occurrence "bottom-tools" nil t)
(autoload 'my/problems-toggle "bottom-tools" nil t)

(keymap-global-set "s-3" #'my/find-toggle)
(keymap-global-set "s-6" #'my/problems-toggle)
(keymap-global-set "M-<f7>" #'my/find-usages)
(keymap-global-set "M-s-<down>" #'my/find-next-occurrence)
(keymap-global-set "M-s-<up>" #'my/find-previous-occurrence)

(provide 'init-find)
;;; init-find.el ends here
