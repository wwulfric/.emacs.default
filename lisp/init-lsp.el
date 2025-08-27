(require 'yasnippet)
(yas-global-mode 1)

(setq lsp-bridge-python-command (concat (global/load-file-path) "../.venv/bin/python"))

(require 'lsp-bridge)

(global-lsp-bridge-mode)
;;(setq lsp-bridge-enable-hover-diagnostic t)

;; python
(setq lsp-bridge-python-lsp-server "ruff")
(setq lsp-bridge-python-multi-lsp-server "basedpyright_ruff")

;; java
(require 'lsp-bridge-jdtls) ;; 根据项目自动生成自定义配置，添加必要的启动参数
(setq lsp-bridge-enable-auto-import t) ;; 开启自动导入依赖，目前没有code action。补全时可以通过这个导入相应的依赖，建议开启。


(provide 'init-lsp)
