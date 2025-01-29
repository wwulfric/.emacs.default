
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
  "Add comment at the beginning of line or region."
  (interactive)
  (if (region-active-p)
      (comment-region (region-beginning) (region-end))
    (comment-region (line-beginning-position) (line-end-position))))

(global-set-key (kbd "s-/") 'my-comment-dwim)


(provide 'global-shortkeys)
