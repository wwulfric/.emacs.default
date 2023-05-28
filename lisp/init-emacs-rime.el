(require 'rime)
(setq rime-emacs-module-header-root "/Applications/Emacs.app/Contents/Resources/include/")
(setq rime-librime-root  "~/.emacs.d/librime/dist/")
(setq default-input-method "rime"
      rime-show-candidate 'posframe)
(setq rime-user-data-dir "~/.emacs.d/rime")
(provide 'init-emacs-rime)
