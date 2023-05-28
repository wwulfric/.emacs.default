;; jieba 分词
;; 需要提前编译出可执行文件，见：https://github.com/kanglmf/emacs-chinese-word-segmentation/blob/master/README.md#%E7%BC%96%E8%AF%91
;; 核心命令：
;; git submodule update --init --recursive
;; env CXX=clang++ make

(setq cns-prog (concat (global/load-file-path) "emacs-chinese-word-segmentation/cnws"))
(setq cns-dict-directory (concat (global/load-file-path) "emacs-chinese-word-segmentation/cppjieba/dict"))

;;(message cns-prog)

(setq cns-recent-segmentation-limit 20) ; default is 10
(setq cns-debug t) ; disable debug output, default is t
(require 'cns nil t)
(when (featurep 'cns)
  (add-hook 'find-file-hook 'cns-auto-enable))

(global-cns-mode t)
(provide 'init-jieba-word)



