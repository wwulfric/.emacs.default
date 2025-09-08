;; jieba 分词
;; 需要提前编译出可执行文件，见：https://github.com/kanglmf/emacs-chinese-word-segmentation/blob/master/README.md#%E7%BC%96%E8%AF%91
;; 核心命令：
;; git submodule update --init --recursive
;; env CXX=clang++ make

(setq cns-prog (concat (global/load-file-path) "emacs-chinese-word-segmentation/cnws"))
(setq cns-dict-directory (concat (global/load-file-path) "emacs-chinese-word-segmentation/cppjieba/dict"))
(setq cns-process-type 'shell)

;;(message cns-prog)

(setq cns-recent-segmentation-limit 20) ; default is 10
(setq cns-debug t) ; disable debug output, default is t
(require 'cns nil t)
(when (featurep 'cns)
  (add-hook 'find-file-hook 'cns-auto-enable))

(global-cns-mode t)

(defun smart-backward-word ()
  "智能向后单词移动"
  (interactive)
  (let* ((current-point (point))
         (syntax-point
          (save-excursion
            (skip-syntax-backward (string (char-syntax (char-before))))
            (point)))
         (subword-point
          (save-excursion
            (cns-backward-word)
            (point))))
    (if (and (< subword-point current-point)
             (> subword-point syntax-point))
        (goto-char subword-point)
      (goto-char syntax-point))))

(global-set-key (kbd "M-b") 'smart-backward-word)

(provide 'init-jieba-word)



