;; -*- lexical-binding: t; -*-

;; Linux 使用 Super 全选、复制粘贴；macOS 使用原生 Command 绑定。
(when (eq system-type 'gnu/linux)
  (global-set-key (kbd "s-a") #'mark-whole-buffer)
  (global-set-key (kbd "s-c") #'kill-ring-save)
  (global-set-key (kbd "s-v") #'yank))

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

(defun my-delete-whole-line ()
  "Delete the current line without copying to kill ring."
  (interactive)
  (delete-region (line-beginning-position) 
                 (1+ (line-end-position))))
;; 删除整行
(global-set-key (kbd "<s-backspace>") (lambda ()
				  (interactive)
				  ;; (kill-whole-line)
                                  (my-delete-whole-line)
                                  ))

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


;; 上下移动当前行，或选区覆盖的整行。
(defun my-move-lines (count)
  "Move the current line or selected lines by COUNT lines.
Keep point, selection, and the presence of a final newline."
  (let* ((selected (use-region-p))
         (old-point (point))
         (old-mark (and selected (mark)))
         (start (save-excursion
                  (goto-char (if selected (region-beginning) (point)))
                  (line-beginning-position)))
         (end (save-excursion
                (goto-char (if selected (region-end) (point)))
                (unless (and selected (bolp)) (forward-line 1))
                (point)))
         (target (save-excursion
                   (goto-char (if (< count 0) start end))
                   (forward-line count)
                   (point))))
    (when (and (< start end)
               (if (< count 0) (< target start) (> target end)))
      (atomic-change-group
        (let* ((missing-newline (not (eq (char-before (point-max)) ?\n)))
               (old-max (point-max))
               (offset (- old-point start))
               (mark-offset (and selected (- old-mark start))))
          ;; Give both blocks a line separator while exchanging them.
          (when missing-newline
            (save-excursion (goto-char (point-max)) (insert "\n"))
            (when (= end old-max) (setq end (1+ end)))
            (when (= target old-max) (setq target (1+ target))))
          (if (< count 0)
              (progn
                (transpose-regions target start start end)
                (setq start target))
            (transpose-regions start end end target)
            (setq start (+ start (- target end))))
          (when missing-newline
            (save-excursion
              (goto-char (point-max))
              (delete-char -1)))
          (goto-char (min (+ start offset) (point-max)))
          (when selected
            (set-mark (min (+ start mark-offset) (point-max)))
            (setq deactivate-mark nil)))))))

(defun my-move-lines-up (count)
  "Move the current line or selected lines up COUNT lines."
  (interactive "*p")
  (my-move-lines (- count)))

(defun my-move-lines-down (count)
  "Move the current line or selected lines down COUNT lines."
  (interactive "*p")
  (my-move-lines count))

(global-set-key (kbd "s-S-<up>") #'my-move-lines-up)
(global-set-key (kbd "s-S-<down>") #'my-move-lines-down)


;; 只禁用鼠标滚轮缩放，保留 Ctrl+= 等键盘快捷键
(global-unset-key (kbd "C-<wheel-up>"))
(global-unset-key (kbd "C-<wheel-down>"))
(global-unset-key (kbd "C-<mouse-4>"))
(global-unset-key (kbd "C-<mouse-5>"))

(provide 'global-shortkeys)
