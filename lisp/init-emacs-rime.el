(require 'rime)
;; (setq rime-emacs-module-header-root "/Applications/Emacs.app/Contents/Resources/include/")
;; (setq rime-librime-root  "../librime/dist/")
(setq rime-share-data-dir "~/.local/share/fcitx5/rime")

(setq rime-posframe-properties
      (list :background-color "#333333"
            :foreground-color "#dcdccc"
            :font "WenQuanYi Micro Hei Mono-14"
            :internal-border-width 10))

(setq default-input-method "rime"
     rime-show-candidate 'minibuffer )
(setq rime-user-data-dir (concat (global/load-file-path) "../rime" ))

(setq rime-disable-predicates
      '(rime--after-alphabet-char-p
	rime--prog-in-code-p))

(provide 'init-emacs-rime)
