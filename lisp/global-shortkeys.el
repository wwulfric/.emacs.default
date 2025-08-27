
;; 下方新增一行
(global-set-key (kbd "<S-return>") (lambda ()
				     (interactive)
				     (end-of-line)
				     (newline-and-indent)))
;; 上方新增一行
(global-set-key (kbd "<C-return>") 
                (lambda ()
                  (interactive)
                  (unless (= (line-number-at-pos) 1)
                    (previous-line))
                  (end-of-line)
                  (newline-and-indent)))

;; 删除整行
(global-set-key (kbd "<s-backspace>") (lambda ()
				  (interactive)
				  (kill-whole-line)))

;; kill buffer
(defun custom/kill-this-buffer ()
  (interactive) (kill-buffer (current-buffer)))
(global-set-key (kbd "C-x k") 'custom/kill-this-buffer)

;; comment

(defun my-comment-dwim ()
  "Smart comment/uncomment for line or region.
Always comment/uncomment from the beginning of lines."
  (interactive)
  (let (start end)
    (if (region-active-p)
        (progn
          ;; 扩展选择区域到完整的行
          (setq start (save-excursion
                        (goto-char (region-beginning))
                        (line-beginning-position)))
          (setq end (save-excursion
                      (goto-char (region-end))
                      ;; 如果选择结束不在行首，包含整行
                      (if (bolp)
                          (point)
                        (line-end-position)))))
      ;; 单行处理
      (setq start (line-beginning-position)
            end (line-end-position)))
    
    ;; 使用内置函数进行注释/取消注释
    (comment-or-uncomment-region start end)))


(global-set-key (kbd "s-/") 'my-comment-dwim)


;; 上下滚动
(require 'move-text)
(global-set-key (kbd "s-S-<up>") 'move-text-up)
(global-set-key (kbd "s-S-<down>") 'move-text-down)


(provide 'global-shortkeys)
