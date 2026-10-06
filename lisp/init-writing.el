;;; init-writing.el --- Quiet Org and Markdown writing -*- lexical-binding: t; -*-

;;; Commentary:
;; Keep prose typography, code block spacing, optional reading layout and
;; section numbers together.  Ink owns face colors; frame-setting owns fonts
;; and base window padding.  All writing decorations are display-only and
;; leave document source unchanged.  Reading layout and numbering are manual,
;; independent toggles; basic typography and code spacing apply automatically.

;;; Code:

(require 'cl-lib)
(require 'face-remap)
(require 'seq)

(defface my-writing-heading-1 '((t (:inherit bold)))
  "First-level prose heading." :group 'faces)
(defface my-writing-heading-2 '((t (:inherit bold)))
  "Second-level prose heading." :group 'faces)
(defface my-writing-heading-3 '((t (:inherit bold)))
  "Lower-level prose heading." :group 'faces)
(defface my-writing-code-block '((t (:inherit fixed-pitch)))
  "Fixed-pitch prose code block." :group 'faces)
(defface my-writing-inline-code '((t (:inherit fixed-pitch)))
  "Fixed-pitch inline code." :group 'faces)
(defface my-writing-path '((t (:inherit (fixed-pitch link))))
  "A literal path or URL in prose." :group 'faces)

;;; Markdown structure


(declare-function treesit-parser-list "treesit")
(declare-function treesit-parser-language "treesit" (parser))
(declare-function treesit-query-capture "treesit" (node query &optional beg end node-only grouped))
(declare-function treesit-node-type "treesit" (node))
(declare-function treesit-node-start "treesit" (node))
(declare-function treesit-node-end "treesit" (node))
(declare-function treesit-node-child "treesit" (node n &optional named))
(declare-function treesit-node-child-count "treesit" (node &optional named))
(declare-function markdown-heading-at-point "markdown-mode" (&optional pos))

(defvar-local my/writing-markdown--blocks nil)
(defvar-local my/writing-markdown--invalid-from nil)

(defconst my/writing-markdown--html-block-tag
  (concat " \\{0,3\\}</?"
          (regexp-opt '("address" "article" "aside" "base" "blockquote"
                        "body" "caption" "center" "col" "colgroup" "dd"
                        "details" "dialog" "dir" "div" "dl" "dt" "fieldset"
                        "figcaption" "figure" "footer" "form" "frame"
                        "frameset" "h1" "h2" "h3" "h4" "h5" "h6" "head"
                        "header" "hr" "html" "iframe" "legend" "li" "link"
                        "main" "menu" "menuitem" "nav" "noframes" "ol"
                        "optgroup" "option" "p" "param" "search" "section"
                        "source" "summary" "table" "tbody" "td" "tfoot"
                        "th" "thead" "title" "tr" "track" "ul"))
          "\\(?:[ \t/>]\\|$\\)"))

(defun my/writing-markdown--native-block-p (position)
  "Read markdown-mode's existing block syntax properties at POSITION."
  (cl-some (lambda (property) (get-text-property position property))
           '(markdown-pre markdown-fenced-code markdown-gfm-code
             markdown-yaml-metadata-begin markdown-yaml-metadata-section
             markdown-yaml-metadata-end)))

(defun my/writing-markdown--invalidate-blocks (begin _end _old-length)
  "Record an edit at BEGIN without doing parsing inside the change hook."
  (setq my/writing-markdown--invalid-from
        (min begin (or my/writing-markdown--invalid-from begin))))

(defun my/writing-markdown--rewind-blocks (begin)
  "Retain cached block context before an edit at BEGIN."
  (when my/writing-markdown--blocks
    (save-excursion
      (save-match-data
        (goto-char begin)
        (forward-line -1)
        (let* ((state my/writing-markdown--blocks)
               (restart (max (point-min) (point)))
               (range (cl-find-if
                       (lambda (entry)
                         (and (< (car entry) restart) (< restart (cadr entry))))
                       (plist-get state :ranges)))
               (open (or (car range)
                         (when (and (plist-get state :open)
                                    (< (plist-get state :open) restart))
                           (plist-get state :open))))
               (close (if range (nth 2 range) (plist-get state :close))))
          (when (< restart (plist-get state :next))
            (setf (plist-get state :next) restart
                  (plist-get state :ranges)
                  (cl-remove-if (lambda (entry) (> (cadr entry) restart))
                                (plist-get state :ranges))
                  (plist-get state :open) open
                  (plist-get state :close) close))
          (setf (plist-get state :tick) (buffer-chars-modified-tick)))))))

(defun my/writing-markdown-p ()
  "Return non-nil in classic, GFM or tree-sitter Markdown buffers."
  (derived-mode-p 'markdown-mode 'gfm-mode 'markdown-ts-mode))

(defun my/writing-markdown--atx (begin)
  "Return the ATX heading at BEGIN, or nil for invalid prefix syntax."
  (save-excursion
    (goto-char begin)
    (when (looking-at " \\{0,3\\}\\(#[#]\\{0,5\\}\\)\\(?:[ \t]+\\|$\\)")
      (let ((marker (match-string-no-properties 1))
            (content (match-end 0)))
        (list :begin begin :content content :end (line-end-position)
              :level (length marker) :kind 'atx
              :prefix-end content :marker marker)))))

(defun my/writing-markdown--treesit (parser start end)
  "Read structural headings from PARSER within START and END."
  (let (headings)
    (dolist (node (treesit-query-capture
                  parser '((atx_heading) @heading (setext_heading) @heading)
                  start end t))
      (let ((begin (treesit-node-start node)))
        (save-excursion
          (goto-char begin)
          (let ((line (line-beginning-position)))
            (when (string-match-p "\\` \\{0,3\\}\\'"
                                  (buffer-substring-no-properties line begin))
              (setq begin line))))
        (when (and (<= start begin) (< begin end))
          (if (equal (treesit-node-type node) "atx_heading")
              (when-let* ((heading (my/writing-markdown--atx begin)))
                (push heading headings))
            (let* ((underline (treesit-node-child
                               node (1- (treesit-node-child-count node t)) t))
                   (level (if (equal (treesit-node-type underline)
                                     "setext_h1_underline") 1 2)))
              (save-excursion
                (goto-char begin)
                (skip-chars-forward " " (line-end-position))
                (let ((content (point)))
                  (goto-char (treesit-node-end node))
                  (when (and (> (point) begin) (eq (char-before) ?\n))
                    (backward-char))
                  (push (list :begin begin :content content :end (point)
                              :level level :kind 'setext
                              :prefix-end nil :marker nil)
                        headings))))))))
    (nreverse headings)))

(defun my/writing-markdown--html-start ()
  "Return an HTML block's closing regexp, or `blank', at this line."
  (let ((case-fold-search t))
    (cond
     ((looking-at " \\{0,3\\}<\\(script\\|pre\\|style\\|textarea\\)\\(?:[ \t>]\\|$\\)")
      (concat "</" (match-string-no-properties 1) "[ \t]*>"))
     ((looking-at " \\{0,3\\}<!--") "-->")
     ((looking-at " \\{0,3\\}<!\\[CDATA\\[") "\\]\\]>")
     ((looking-at " \\{0,3\\}<\\?") "\\?>")
     ((looking-at " \\{0,3\\}<![A-Z]") ">")
     ;; Classic markdown-mode does not mark raw HTML blocks structurally.
     ;; Block tags and whole-line tags continue up to the next blank line.
     ((or (looking-at my/writing-markdown--html-block-tag)
          (looking-at " \\{0,3\\}</?[[:alpha:]][[:alnum:]-]*\\(?:[ \t][^<>]*\\)?/?>[ \t]*$"))
      'blank))))

(defun my/writing-markdown--classic-blocks (end)
  "Cache block boundaries omitted by classic markdown-mode through END.
Reuse earlier context when scrolling.  The mode supplies indented code and
YAML exclusions; supplement HTML, TOML and arbitrary-length/unclosed fences."
  (let ((tick (buffer-chars-modified-tick)))
    (unless (and my/writing-markdown--blocks
                 (or (= tick (plist-get my/writing-markdown--blocks :tick))
                     my/writing-markdown--invalid-from)
                 (= (point-min) (plist-get my/writing-markdown--blocks :min)))
      (setq my/writing-markdown--blocks
            (list :tick tick :min (point-min) :next (point-min)
                  :open nil :close nil :ranges nil)
            my/writing-markdown--invalid-from nil)
      (add-hook 'after-change-functions #'my/writing-markdown--invalidate-blocks nil t))
    (when my/writing-markdown--invalid-from
      (my/writing-markdown--rewind-blocks my/writing-markdown--invalid-from)
      (setq my/writing-markdown--invalid-from nil))
    (let ((state my/writing-markdown--blocks)
          (case-fold-search t))
      (save-excursion
        (goto-char (plist-get state :next))
        (while (< (point) end)
          (let ((begin (point)) (limit (line-end-position)) opening-line)
            (unless (plist-get state :open)
              (let ((close
                     (cond
                      ((and (not (cl-some
                                  (lambda (property)
                                    (get-text-property begin property))
                                  '(markdown-yaml-metadata-begin
                                    markdown-yaml-metadata-section
                                    markdown-yaml-metadata-end)))
                            (looking-at " \\{0,3\\}\\([`]\\{3,\\}\\|~\\{3,\\}\\)\\(.*\\)$"))
                       (let ((fence (match-string-no-properties 1))
                             (info (match-string-no-properties 2)))
                         (unless (and (eq (aref fence 0) ?`)
                                      (string-match-p "`" info))
                           (setq opening-line t)
                           (format "^ \\{0,3\\}%s\\{%d,\\}[ \t]*$"
                                   (regexp-quote (substring fence 0 1))
                                   (length fence)))))
                      ;; Our fence state accounts for delimiter length.  The
                      ;; classic mode's fence properties can run past a long
                      ;; fence's real end, so do not let them hide later HTML.
                      ((cl-some (lambda (property)
                                  (get-text-property begin property))
                                '(markdown-pre markdown-yaml-metadata-begin
                                  markdown-yaml-metadata-section
                                  markdown-yaml-metadata-end)) nil)
                      ((and (= begin (point-min)) (looking-at "\\+\\+\\+[ \t]*$"))
                       (when (save-excursion
                               (forward-line)
                               (re-search-forward "^\\+\\+\\+[ \t]*$" nil t))
                         (setq opening-line t)
                         "^\\+\\+\\+[ \t]*$"))
                      (t (my/writing-markdown--html-start)))))
                (when close
                  (setf (plist-get state :open) begin
                        (plist-get state :close) close))))
            (when (and (plist-get state :open) (not opening-line)
                       (if (eq (plist-get state :close) 'blank)
                           (looking-at "[ \t]*$")
                         (re-search-forward (plist-get state :close) limit t)))
              (push (list (plist-get state :open) (min (point-max) (1+ limit))
                          (plist-get state :close))
                    (plist-get state :ranges))
              (setf (plist-get state :open) nil))
            (goto-char limit)
            (forward-line)))
        (setf (plist-get state :next) (point)))
      state)))

(defun my/writing-markdown--blocked-p (position blocks)
  "Whether POSITION is code, a comment or one of the cached BLOCKS."
  (or (my/writing-markdown--native-block-p position)
      (get-text-property position 'markdown-comment)
      (and (plist-get blocks :open) (>= position (plist-get blocks :open)))
      (cl-some (lambda (range) (and (<= (car range) position) (< position (cadr range))))
               (plist-get blocks :ranges))))

(defun my/writing-markdown--classic (start end)
  "Read classic markdown-mode headings within START and END."
  (let* ((scan-end (save-excursion
                     (goto-char end)
                     (forward-line 2)
                     (point)))
         (_ (syntax-propertize scan-end))
         (blocks (my/writing-markdown--classic-blocks scan-end))
         headings)
    (save-excursion
      (goto-char start)
      (beginning-of-line)
      (while (< (point) scan-end)
        (let* ((begin (point))
               (known (markdown-heading-at-point begin))
               (setext (and known (match-beginning 1)))
               (heading
                (cond
                 (setext
                  (list :begin (match-beginning 0) :content (match-beginning 1) :end (match-end 0)
                        :level (if (match-beginning 2) 1 2) :kind 'setext
                        :prefix-end nil :marker nil))
                 (t (my/writing-markdown--atx begin)))))
          ;; The classic regex omits headings indented by up to three spaces.
          (unless heading
            (when (and (looking-at " \\{0,3\\}[^ \t\n#>*+-]")
                       (save-excursion
                         (forward-line)
                         (looking-at " \\{0,3\\}\\(=+\\|-+\\)[ \t]*$")))
              (let ((level (if (eq (char-after (match-beginning 1)) ?=) 1 2))
                    (finish (match-end 0)))
                (save-excursion
                  (skip-chars-forward " " (line-end-position))
                  (setq heading (list :begin begin :content (point) :end finish
                                      :level level :kind 'setext
                                      :prefix-end nil :marker nil))))))
          (when (and heading (<= start (plist-get heading :begin))
                     (< (plist-get heading :begin) end)
                     (not (my/writing-markdown--blocked-p begin blocks)))
            (push heading headings))
          (if (eq (plist-get heading :kind) 'setext)
              (goto-char (plist-get heading :end))
            (goto-char begin))
          (forward-line))))
    (nreverse headings)))

(defun my/writing-markdown-headings (&optional start end)
  "Return ordered structural headings beginning in [START, END).
Both bounds default to the accessible buffer.  Each record has integer
:begin (physical line start), :content (text start), :end (excluding the
final newline), :level (1..6), and :kind (`atx' or `setext').  ATX records
also have :prefix-end and a :marker hash string; Setext records use nil.
For Setext, :end includes the underline line.  Point and match data stay
unchanged.  Existing syntax properties may be refreshed by the major mode."
  (when (my/writing-markdown-p)
    (save-excursion
      (save-restriction
        (save-match-data
          (let* ((start (max (point-min) (or start (point-min))))
                 (end (min (point-max) (or end (point-max))))
                 (parser (and (fboundp 'treesit-parser-list)
                              (cl-find 'markdown (treesit-parser-list)
                                       :key #'treesit-parser-language))))
            (when (< start end)
              (if parser
                  (my/writing-markdown--treesit parser start end)
                (when (derived-mode-p 'markdown-mode 'gfm-mode)
                  (my/writing-markdown--classic start end))))))))))

;;; Code block structure


(declare-function org-element-at-point "org-element" (&optional epom cached-only))
(declare-function org-element-type "org-element" (element &optional robust))
(declare-function org-element-property "org-element" (property element))

(defun my/writing-code--line-end (position)
  "Return the exclusive physical line boundary at or after POSITION."
  (save-excursion
    (goto-char position)
    (if (or (bolp) (eobp)) (point)
      (forward-line)
      (point))))

(defun my/writing-code--record (begin end kind &optional closed)
  "Make a code block record covering BEGIN through END of KIND."
  (list :begin (save-excursion (goto-char begin) (line-beginning-position))
        :end (my/writing-code--line-end end) :kind kind :closed closed))

(defun my/writing-code--intersects-p (record start end)
  "Whether RECORD intersects the half-open interval START through END."
  (and (< (plist-get record :begin) end)
       (> (plist-get record :end) start)))

(defun my/writing-code--org-record (element)
  "Return an Org source/example ELEMENT's physical bounds, or nil."
  (when (memq (org-element-type element) '(src-block example-block))
    (let ((begin (or (org-element-property :post-affiliated element)
                     (org-element-property :begin element)))
          (end (org-element-property :end element)))
      ;; Org's :end includes following blank lines, which are outside the block.
      (save-excursion
        (goto-char end)
        (let ((post-blank (or (org-element-property :post-blank element) 0)))
          ;; `forward-line' with zero would move an unterminated EOF line to
          ;; its beginning and accidentally remove the closing delimiter.
          (when (> post-blank 0) (forward-line (- post-blank))))
        (my/writing-code--record
         begin (point)
         (if (eq (org-element-type element) 'src-block) 'src 'example) t)))))

(defun my/writing-code--org (start end)
  "Read Org code blocks intersecting START through END."
  (require 'org-element)
  (let ((case-fold-search t) records)
    ;; The viewport may start in the middle of a large source block.
    (when-let* ((record (my/writing-code--org-record (org-element-at-point start))))
      (when (my/writing-code--intersects-p record start end)
        (push record records)))
    (goto-char start)
    (beginning-of-line)
    (while (re-search-forward "^[ \t]*#\\+begin_\\(?:src\\|example\\)\\(?:[ \t]\\|$\\)" end t)
      (let* ((candidate (match-beginning 0))
             (record (my/writing-code--org-record (org-element-at-point candidate))))
        ;; The parser rejects apparent openers inside examples or other blocks.
        (when (and record (my/writing-code--intersects-p record start end))
          (push record records)
          (goto-char (min end (plist-get record :end))))))
    (delete-dups (nreverse records))))

(defun my/writing-code--treesit-eof-closed-p (node opener)
  "Recognize NODE's closing fence at EOF when its parser omits the node.
OPENER is the parsed opening delimiter.  Some installed Markdown grammars
treat a final closing fence without a newline as code content."
  (when (and opener (= (treesit-node-end node) (point-max))
             (not (eq (char-before (point-max)) ?\n)))
    (save-excursion
      (goto-char (point-max))
      (beginning-of-line)
      (when (> (point) (treesit-node-end opener))
        ;; Respect parsed container prefixes instead of treating arbitrary >
        ;; characters in top-level code as block quote continuation markers.
        (let ((line-begin (point)))
          (dolist (prefix (treesit-query-capture
                           node '((block_continuation) @prefix)
                           line-begin (point-max) t))
            (when (= (treesit-node-start prefix) line-begin)
              (goto-char (treesit-node-end prefix)))))
        (looking-at-p
         (format " \\{0,3\\}%s\\{%d,\\}[ \t]*$"
                 (regexp-quote (char-to-string (char-after (treesit-node-start opener))))
                 (- (treesit-node-end opener) (treesit-node-start opener))))))))

(defun my/writing-code--treesit (parser start end)
  "Read code block nodes from PARSER intersecting START through END."
  (let (records)
    (dolist (node (treesit-query-capture
                  parser '((fenced_code_block) @block (indented_code_block) @block)
                  start end t))
      (let* ((fenced (equal (treesit-node-type node) "fenced_code_block"))
             (delimiters
              (when fenced
                (cl-loop for index below (treesit-node-child-count node t)
                         for child = (treesit-node-child node index t)
                         when (equal (treesit-node-type child)
                                     "fenced_code_block_delimiter")
                         collect child)))
             (record (my/writing-code--record
                      (treesit-node-start node) (treesit-node-end node)
                      (if fenced 'fenced 'indented)
                      (or (not fenced) (= (length delimiters) 2)
                          (my/writing-code--treesit-eof-closed-p node (car delimiters))))))
        (when (my/writing-code--intersects-p record start end)
          (push record records))))
    (nreverse records)))

(defun my/writing-code--fence-at (position)
  "Return non-nil when the cached block at POSITION is a code fence."
  (save-excursion
    (goto-char position)
    (and (not (cl-some (lambda (property) (get-text-property position property))
                       '(markdown-yaml-metadata-begin markdown-yaml-metadata-section
                         markdown-yaml-metadata-end)))
         (looking-at-p " \\{0,3\\}\\(?:`\\{3,\\}\\|~\\{3,\\}\\)"))))

(defun my/writing-code--classic (start end)
  "Read classic Markdown code blocks intersecting START through END."
  (syntax-propertize end)
  (let* ((state (my/writing-markdown--classic-blocks end))
         (open (plist-get state :open))
         records)
    ;; Finish only an open code block that crosses the viewport's end.  The
    ;; cached opener supplies its exact length-sensitive closing expression.
    (when (and open (< (plist-get state :next) (point-max))
               (my/writing-code--fence-at open))
      (let* ((close (plist-get state :close))
             (finish (save-excursion
                       (goto-char (plist-get state :next))
                       (if (re-search-forward close nil t)
                           (my/writing-code--line-end (match-end 0))
                         (point-max)))))
        (syntax-propertize finish)
        (setq state (my/writing-markdown--classic-blocks finish)
              open (plist-get state :open))))
    (dolist (range (plist-get state :ranges))
      (when (and (< (car range) end) (> (cadr range) start)
                 (my/writing-code--fence-at (car range)))
        (push (my/writing-code--record (car range) (cadr range) 'fenced t) records)))
    (when (and open (< open end) (my/writing-code--fence-at open))
      (push (my/writing-code--record open (point-max) 'fenced nil) records))
    ;; The major mode has already accounted for list nesting and indentation.
    ;; Walk its property runs instead of implementing those Markdown rules.
    (let ((position start))
      (while (< position end)
        (let ((bounds (get-text-property position 'markdown-pre)))
          (when (and bounds
                     (not (or (get-text-property (car bounds) 'markdown-comment)
                              (cl-some
                               (lambda (property)
                                 (get-text-property (car bounds) property))
                               '(markdown-yaml-metadata-begin
                                 markdown-yaml-metadata-section
                                 markdown-yaml-metadata-end))
                              (and open (>= (car bounds) open))
                              (cl-some
                               (lambda (range)
                                 (and (<= (car range) (car bounds))
                                      (< (car bounds) (cadr range))))
                               (plist-get state :ranges)))))
            (push (my/writing-code--record (car bounds) (cadr bounds) 'indented t)
                  records)))
        (setq position (next-single-property-change position 'markdown-pre nil end))))
    (sort (delete-dups records)
          (lambda (left right) (< (plist-get left :begin) (plist-get right :begin))))))

(defun my/writing-code-blocks (&optional start end)
  "Return code blocks intersecting the half-open interval START through END.
Bounds default to the accessible buffer.  Each plist has :begin (physical
line beginning), :end (exclusive, including the final newline when present),
:kind (`src', `example', `fenced' or `indented') and :closed.  A block's full
bounds may extend outside START/END or a narrowing restriction.  Org follows
its parser, which does not treat an unmatched BEGIN as a source block.
Preserve point, restriction, match data and source text.  Existing major-mode
syntax properties and structural caches may be refreshed."
  (when (or (derived-mode-p 'org-mode) (my/writing-markdown-p))
    (save-excursion
      (save-match-data
        (let ((start (max (point-min) (or start (point-min))))
              (end (min (point-max) (or end (point-max)))))
          (when (< start end)
            (save-restriction
              (widen)
              (if (derived-mode-p 'org-mode)
                  (my/writing-code--org start end)
                (let ((parser (and (fboundp 'treesit-parser-list)
                                   (cl-find 'markdown (treesit-parser-list)
                                            :key #'treesit-parser-language))))
                  (if parser (my/writing-code--treesit parser start end)
                    (my/writing-code--classic start end)))))))))))

;;; Code block spacing

(declare-function org-fold-next-visibility-change "org-fold" (&optional pos limit))

(defgroup my-writing-code nil "Space inside prose code blocks." :group 'faces)
(defcustom my/writing-code-left-padding 12
  "Pixels of display-only space before each code block line."
  :type 'natnum :group 'my-writing-code)
(defcustom my/writing-code-vertical-padding 4
  "Pixels of display-only space at the top and bottom of a code block."
  :type 'natnum :group 'my-writing-code)

(defvar-local my/writing-code--overlays nil)
(defvar-local my/writing-code--state nil)
(defvar-local my/writing-code--refreshing nil)
(defvar my/writing-code-mode)

(defun my/writing-code--clear ()
  "Remove only the decorations owned by this mode."
  (mapc #'delete-overlay my/writing-code--overlays)
  (setq my/writing-code--overlays nil
        my/writing-code--state nil))

(defun my/writing-code--invalidate (&rest _)
  "Request an update on the next display or command."
  (setq my/writing-code--state nil))

(defun my/writing-code--ranges ()
  "Return the merged physical line ranges visible in this buffer's windows."
  (let (ranges merged)
    (dolist (window (get-buffer-window-list (current-buffer) nil t))
      (unless (window-minibuffer-p window)
        (save-excursion
          (goto-char (max (point-min) (window-start window)))
          (let ((begin (line-beginning-position)))
            (goto-char (min (point-max) (or (window-end window t) (point-max))))
            ;; Keep a small amount of overscan while padding changes wrapping.
            (forward-line 2)
            (push (cons begin (point)) ranges)))))
    (dolist (range (sort ranges (lambda (a b) (< (car a) (car b)))))
      (if (and merged (<= (car range) (cdar merged)))
          (setcdr (car merged) (max (cdar merged) (cdr range)))
        (push range merged)))
    (setq merged (nreverse merged))
    ;; A folded subtree may contain megabytes between two visible lines.
    ;; Do not fontify or parse its hidden blocks.  These boundaries also
    ;; invalidate the cache after direct fold API calls, which need not
    ;; run `org-cycle-hook' or change a buffer modification tick.
    (let (visible)
      (dolist (range merged)
        (let ((position (car range)))
          (while (< position (cdr range))
            (let ((next (if (derived-mode-p 'org-mode)
                            (org-fold-next-visibility-change position (cdr range))
                          (next-single-char-property-change
                           position 'invisible nil (cdr range)))))
              (unless (invisible-p position)
                ;; Different inactive invisibility tags can still describe
                ;; one visible line, notably classic Markdown delimiters.
                (if (and visible (= (cdar visible) position))
                    (setcdr (car visible) next)
                  (push (cons position next) visible)))
              (setq position next)))))
      (nreverse visible))))

(defun my/writing-code--key (ranges)
  "Return the display state affecting code padding in RANGES."
  (list (buffer-modified-tick) ranges (point-min) (point-max)
        (bound-and-true-p org-indent-mode) buffer-invisibility-spec
        line-prefix wrap-prefix line-spacing
        my/writing-code-left-padding my/writing-code-vertical-padding))

(defun my/writing-code--prefix (original padding)
  "Append PADDING to an ORIGINAL display prefix of any supported type."
  (concat (cond ((null original) "")
                ((stringp original) original)
                (t (propertize " " 'display original)))
          padding))

(defun my/writing-code--spacer (face)
  "Return a small blank display line using FACE."
  ;; Ignore the newline's font metrics so the stretch glyph alone sets the
  ;; height.  A newline with an integer `line-height' still has a full row's
  ;; minimum height, even when its face requests a tiny font.
  (concat (propertize " " 'face face 'display
                      `(space :width (0) :height (,my/writing-code-vertical-padding)))
          (propertize "\n" 'face face 'line-height t
                      'line-prefix "" 'wrap-prefix "" 'line-spacing 0)))

(defun my/writing-code--decorate (block start end)
  "Pad the visible portion of BLOCK between START and END."
  (let* ((begin (plist-get block :begin))
         (finish (plist-get block :end))
         (face (if (derived-mode-p 'org-mode) 'org-block 'my-writing-code-block))
         (padding (propertize " " 'face face 'display
                              `(space :width ,(if (display-graphic-p)
                                                  (list my/writing-code-left-padding)
                                                (ceiling my/writing-code-left-padding 8.0))
                                      :height (1))))
         (vertical (and (display-graphic-p) (> my/writing-code-vertical-padding 0))))
    (save-excursion
      (goto-char (max begin start (point-min)))
      (beginning-of-line)
      (while (< (point) (min finish end (point-max)))
        (let* ((line (point))
               (next (min (point-max) (1+ (line-end-position)))))
          (unless (invisible-p line)
            (let* ((original-line (or (get-char-property line 'line-prefix) line-prefix))
                   (original-wrap (or (get-char-property line 'wrap-prefix) wrap-prefix))
                   (overlay (make-overlay line next nil t nil)))
              (overlay-put overlay 'my-writing-code t)
              (overlay-put overlay 'evaporate t)
              (overlay-put overlay 'line-prefix
                           (my/writing-code--prefix original-line padding))
              (overlay-put overlay 'wrap-prefix
                           (my/writing-code--prefix original-wrap padding))
              (when (and vertical (= line begin))
                (overlay-put overlay 'before-string (my/writing-code--spacer face)))
              (when (and vertical (= next finish)
                         (plist-get block :closed)
                         (not (invisible-p (max line (1- next)))))
                (overlay-put overlay 'after-string
                             (concat (unless (eq (char-before next) ?\n) "\n")
                                     (my/writing-code--spacer face)
                                     ;; End the extending code face before a
                                     ;; following empty prose line is drawn.
                                     (propertize " " 'face '(:inherit default :extend t)
                                                 'display '(space :width (0) :height (1))))))
              (push overlay my/writing-code--overlays)))
          (goto-char next))))))

(defun my/writing-code-refresh (&rest _)
  "Refresh visible block decoration after an edit, scroll or layout change."
  (when (and my/writing-code-mode (not my/writing-code--refreshing))
    (let* ((my/writing-code--refreshing t)
           (ranges (my/writing-code--ranges)))
      (unless (equal my/writing-code--state (my/writing-code--key ranges))
        (save-excursion
          (save-match-data
            (my/writing-code--clear)
            (dolist (range ranges)
              ;; Fontification supplies Org indentation and native code faces.
              (font-lock-ensure (car range) (cdr range))
              (dolist (block (my/writing-code-blocks (car range) (cdr range)))
                (my/writing-code--decorate block (car range) (cdr range))))
            (setq my/writing-code--state (my/writing-code--key ranges))))))))

(defun my/writing-code--windows-changed (frame)
  "Refresh prose buffers displayed on FRAME."
  (let (seen)
    (dolist (window (window-list frame 'no-minibuffer))
      (let ((buffer (window-buffer window)))
        (unless (memq buffer seen)
          (push buffer seen)
          (with-current-buffer buffer
            (when my/writing-code-mode (my/writing-code-refresh))))))))

(defun my/writing-code--leave ()
  "Release decorations before changing major mode or killing the buffer."
  (my/writing-code-mode -1))

;;;###autoload
(define-minor-mode my/writing-code-mode
  "Add display-only space inside Org and Markdown code blocks."
  :lighter nil :group 'my-writing-code
  (if my/writing-code-mode
      (progn
        (add-hook 'post-command-hook #'my/writing-code-refresh 90 t)
        (add-hook 'after-change-functions #'my/writing-code--invalidate nil t)
        (add-hook 'window-scroll-functions #'my/writing-code-refresh 90 t)
        (add-hook 'org-cycle-hook #'my/writing-code--invalidate nil t)
        (add-hook 'change-major-mode-hook #'my/writing-code--leave nil t)
        (add-hook 'kill-buffer-hook #'my/writing-code--leave nil t)
        (my/writing-code-refresh))
    (remove-hook 'post-command-hook #'my/writing-code-refresh t)
    (remove-hook 'after-change-functions #'my/writing-code--invalidate t)
    (remove-hook 'window-scroll-functions #'my/writing-code-refresh t)
    (remove-hook 'org-cycle-hook #'my/writing-code--invalidate t)
    (remove-hook 'change-major-mode-hook #'my/writing-code--leave t)
    (remove-hook 'kill-buffer-hook #'my/writing-code--leave t)
    (my/writing-code--clear)))

(add-hook 'window-state-change-functions #'my/writing-code--windows-changed 90)

;;; Typography and reading layout


(declare-function org-indent-mode "org-indent" (&optional arg))
(declare-function org-num-mode "org-num" (&optional arg))
(defvar org-num-mode)

(defgroup my-writing nil "Quiet prose editing." :group 'text)
(defcustom my/writing-measure 80
  "Preferred prose width in the frame's default-font columns."
  :type 'integer :group 'my-writing)
(defface my-writing-heading-marker '((t (:inherit (fixed-pitch shadow))))
  "Prose source markers and optional section numbers." :group 'my-writing)

(defvar-local my/writing--saved-state nil)
(defvar-local my/writing--typography-state nil)
(defvar-local my/writing--saved-numbering nil)
(defvar-local my/writing--marker-overlays nil)
(defvar my/writing--updating nil)

(defun my/writing--save-variables (variables)
  "Record the values and local bindings of VARIABLES."
  (mapcar (lambda (symbol)
            (list symbol (local-variable-p symbol)
                  (and (boundp symbol) (symbol-value symbol))))
          variables))

(defun my/writing--restore-variables (state)
  "Restore buffer-local variable STATE."
  (dolist (entry state)
    (if (nth 1 entry)
        (set (make-local-variable (car entry)) (nth 2 entry))
      (kill-local-variable (car entry)))))

(defun my/writing--prune-markers (&optional all)
  "Delete markers for dead windows, or ALL markers in this buffer."
  (setq my/writing--marker-overlays
        (delq nil
              (mapcar
               (lambda (overlay)
                 (if (and (not all) (overlay-buffer overlay)
                          (window-live-p (overlay-get overlay 'window)))
                     overlay
                   (delete-overlay overlay)
                   nil))
               my/writing--marker-overlays))))

(defun my/writing--clear-window (window)
  "Remove our overlays and still-owned margins from WINDOW."
  (when-let* ((state (window-parameter window 'my-writing-layout)))
    (mapc #'delete-overlay (plist-get state :overlays))
    ;; `set-window-buffer' may already have applied the new buffer's margins.
    ;; Do not replace those with the margins saved for the previous buffer.
    (when (equal (window-margins window) (plist-get state :applied))
      (let ((saved (plist-get state :saved)))
        (set-window-margins window (car saved) (cdr saved))))
    (when (buffer-live-p (plist-get state :buffer))
      (with-current-buffer (plist-get state :buffer)
        (my/writing--prune-markers)))
    (set-window-parameter window 'my-writing-layout nil)))

(defun my/writing--visible-heading-prefixes (start end)
  "Collect visible Org heading prefixes between START and END.
Jump over folded regions in one step; do not visit their hidden headings."
  (let (prefixes)
    (save-excursion
      (goto-char start)
      (beginning-of-line)
      (while (and (< (point) end)
                  (re-search-forward "^\\(\\*+ \\)" end t))
        (let ((begin (match-beginning 1)) (finish (match-end 1)))
          (if (invisible-p begin)
              (goto-char (org-fold-next-visibility-change begin end))
            (push (cons begin finish) prefixes)))))
    (nreverse prefixes)))

(defun my/writing--heading-overlays (window state)
  "Update visible Org or Markdown heading markers in WINDOW using STATE."
  (let ((markdown (my/writing-markdown-p)))
    (when (or markdown (derived-mode-p 'org-mode))
      (let* ((start (window-start window))
             (end (or (window-end window t) (point-max)))
             (margin (or (car (window-margins window)) 0))
             (prefixes
              (if markdown
                  (delq nil
                        (mapcar
                         (lambda (heading)
                           ;; Setext headings have no leading marker to move.
                           (when-let* ((finish (plist-get heading :prefix-end))
                                       (begin (plist-get heading :begin))
                                       ((not (invisible-p begin))))
                             (list begin finish (plist-get heading :marker))))
                         (my/writing-markdown-headings start end)))
                (mapcar (lambda (prefix) (list (car prefix) (cdr prefix) nil))
                        (my/writing--visible-heading-prefixes start end))))
             ;; Folding need not change the text tick or viewport endpoints.
             ;; Visible prefixes detect that change without reacting to every
             ;; unrelated font-lock text-property update.
             (stamp (list start end margin (buffer-chars-modified-tick) prefixes)))
        (unless (equal stamp (plist-get state :stamp))
          (mapc #'delete-overlay (plist-get state :overlays))
          (my/writing--prune-markers)
          (setf (plist-get state :overlays) nil
                (plist-get state :stamp) stamp)
          (save-excursion
            (dolist (prefix prefixes)
              (let ((begin (car prefix)) (finish (cadr prefix)))
                (when (and (> margin 0)
                           (or markdown
                               (save-excursion
                                 (goto-char begin)
                                 (eq (org-element-type (org-element-at-point))
                                     'headline))))
                  (let* ((source-marker
                          (or (nth 2 prefix)
                              (buffer-substring-no-properties begin (1- finish))))
                         (room (max 1 (1- margin)))
                         (marker (if (> (length source-marker) room)
                                     (concat (substring source-marker 0 (max 0 (1- room))) "·")
                                   source-marker))
                         (text (propertize
                                (concat (make-string (max 0 (- margin (length marker) 1)) ?\s)
                                        marker (if (> margin 1) " " ""))
                                'face 'my-writing-heading-marker))
                         (overlay (make-overlay begin finish nil nil t)))
                    (overlay-put overlay 'window window)
                    (overlay-put overlay 'evaporate t)
                    (overlay-put overlay 'my-writing-display
                                 `((margin left-margin) ,text))
                    (push overlay my/writing--marker-overlays)
                    (push overlay (plist-get state :overlays))))))))
        ;; Moving onto the source prefix reveals it, making marker edits and the
        ;; cursor ordinary again.  The other window can keep its reading view.
        (let ((position (window-point window)))
          (dolist (overlay (plist-get state :overlays))
            (when (overlay-buffer overlay)
              (overlay-put overlay 'display
                           (unless (and (<= (overlay-start overlay) position)
                                        (< position (overlay-end overlay)))
                             (overlay-get overlay 'my-writing-display))))))))))

(defun my/writing--update-window (window)
  "Apply or release prose layout in WINDOW."
  (when (window-live-p window)
    (let ((state (window-parameter window 'my-writing-layout))
          (buffer (window-buffer window)))
      (when (and state (not (eq buffer (plist-get state :buffer))))
        (my/writing--clear-window window)
        (setq state nil))
      (with-current-buffer buffer
        (my/writing--prune-markers)
        (if (not (bound-and-true-p my/writing-layout-mode))
            (my/writing--clear-window window)
          (unless state
            (setq state (list :buffer buffer :saved (window-margins window)
                              :applied nil :overlays nil :stamp nil))
            (set-window-parameter window 'my-writing-layout state))
          (let* ((margins (window-margins window))
                 (width (+ (window-body-width window)
                           (or (car margins) 0) (or (cdr margins) 0)))
                 (minimum (if (< width 48) 1 2))
                 (margin (max minimum (/ (max 0 (- width my/writing-measure)) 2))))
            (unless (equal margins (cons margin margin))
              (set-window-margins window margin margin))
            (setf (plist-get state :applied) (window-margins window)))
          (my/writing--heading-overlays window state))))))

(defun my/writing--window-state-change (frame)
  "Refresh prose windows on FRAME after a display change."
  (unless my/writing--updating
    (let ((my/writing--updating t))
      (dolist (window (window-list frame 'no-minibuf))
        (my/writing--update-window window)))))

(defun my/writing--around-split-window (function &rest arguments)
  "Let FUNCTION split windows without counting our decorative margins.
ARGUMENTS are passed through unchanged.  Restore layout even if splitting
fails, and let each new window save the original, unstyled margin values."
  (let* ((window (or (car arguments) (selected-window)))
         (frame (window-frame window))
         (styled (seq-filter
                  (lambda (view) (window-parameter view 'my-writing-layout))
                  (window-list frame 'no-minibuf))))
    (if (null styled)
        (apply function arguments)
      (unwind-protect
          (let ((my/writing--updating t))
            (mapc #'my/writing--clear-window styled)
            (apply function arguments))
        (when (frame-live-p frame)
          (my/writing--window-state-change frame))))))

(defun my/writing--refresh-buffer-windows (&rest _)
  "Refresh visible views of the current prose buffer."
  (unless my/writing--updating
    (let ((my/writing--updating t))
      (dolist (window (get-buffer-window-list (current-buffer) nil t))
        (my/writing--update-window window)))))

(defun my/writing--release-buffer-windows ()
  "Release every window still owned by the current buffer."
  (dolist (frame (frame-list))
    (dolist (window (window-list frame 'no-minibuf))
      (when (eq (plist-get (window-parameter window 'my-writing-layout) :buffer)
                (current-buffer))
        (my/writing--clear-window window))))
  (my/writing--prune-markers t))

(defun my/writing--leave-layout ()
  "Restore editing state before changing major mode."
  (my/writing-layout-mode -1))

(defun my/writing--leave-typography ()
  "Restore prose typography before changing major mode."
  (my/writing-typography-mode -1))

;;;###autoload
(define-minor-mode my/writing-typography-mode
  "Use prose fonts, line spacing, code padding and visual wrapping here.
This mode does not change window margins or move Org heading markers."
  :lighter nil :group 'my-writing
  (if my/writing-typography-mode
      (unless my/writing--typography-state
        (setq my/writing--typography-state
              (list :variables
                    (my/writing--save-variables
                     '(line-spacing word-wrap word-wrap-by-category truncate-lines
                                    truncate-partial-width-windows))
                    :visual-line (bound-and-true-p visual-line-mode)
                    :face-cookie nil))
        (setq-local line-spacing 0.12)
        (unless (bound-and-true-p visual-line-mode) (visual-line-mode 1))
        ;; Keep Latin words intact next to Chinese text while allowing CJK
        ;; line breaks; this changes only display, never the source text.
        (when (boundp 'word-wrap-by-category)
          (setq-local word-wrap-by-category t))
        ;; Own one remapping without replacing another buffer-face-mode face.
        (setf (plist-get my/writing--typography-state :face-cookie)
              (face-remap-add-relative 'default 'variable-pitch))
        (add-hook 'change-major-mode-hook #'my/writing--leave-typography nil t))
    (when my/writing--typography-state
      (remove-hook 'change-major-mode-hook #'my/writing--leave-typography t)
      (unless (eq (bound-and-true-p visual-line-mode)
                  (plist-get my/writing--typography-state :visual-line))
        (visual-line-mode
         (if (plist-get my/writing--typography-state :visual-line) 1 -1)))
      (face-remap-remove-relative
       (plist-get my/writing--typography-state :face-cookie))
      (my/writing--restore-variables
       (plist-get my/writing--typography-state :variables))
      (setq my/writing--typography-state nil)))
  (my/writing-code-mode (if my/writing-typography-mode 1 -1)))

;;;###autoload
(define-minor-mode my/writing-layout-mode
  "Toggle a centered reading layout without changing the prose source.
Margins adapt separately in each window.  Org stars and Markdown ATX hashes
move to the margin until the cursor edits them.
Setext underlines stay in place.
Fonts, spacing and wrapping are independent:
see `my/writing-typography-mode'."
  :lighter " 阅读" :group 'my-writing
  (if my/writing-layout-mode
      (unless my/writing--saved-state
        (setq my/writing--saved-state
              (list :variables
                    (my/writing--save-variables
                     '(org-hide-leading-stars
                       org-adapt-indentation indent-tabs-mode))
                    :org-indent (bound-and-true-p org-indent-mode)))
        (when (bound-and-true-p org-indent-mode)
          (org-indent-mode -1)
          (my/writing--restore-variables
           (plist-get my/writing--saved-state :variables)))
        (when (derived-mode-p 'org-mode)
          ;; Keep newly entered bodies on the same axis too: an inherited t
          ;; otherwise indents RET and shifts body text on promote/demote.
          (setq-local org-hide-leading-stars nil
                      org-adapt-indentation nil)
          (font-lock-flush))
        (add-hook 'post-command-hook #'my/writing--refresh-buffer-windows nil t)
        (add-hook 'after-change-functions #'my/writing--refresh-buffer-windows t t)
        (add-hook 'window-scroll-functions #'my/writing--refresh-buffer-windows nil t)
        (add-hook 'change-major-mode-hook #'my/writing--leave-layout nil t)
        (add-hook 'kill-buffer-hook #'my/writing--release-buffer-windows nil t)
        (my/writing--refresh-buffer-windows))
    (when my/writing--saved-state
      (remove-hook 'post-command-hook #'my/writing--refresh-buffer-windows t)
      (remove-hook 'after-change-functions #'my/writing--refresh-buffer-windows t)
      (remove-hook 'window-scroll-functions #'my/writing--refresh-buffer-windows t)
      (remove-hook 'change-major-mode-hook #'my/writing--leave-layout t)
      (remove-hook 'kill-buffer-hook #'my/writing--release-buffer-windows t)
      (my/writing--release-buffer-windows)
      (when (plist-get my/writing--saved-state :org-indent) (org-indent-mode 1))
      (my/writing--restore-variables (plist-get my/writing--saved-state :variables))
      (setq my/writing--saved-state nil)
      (when (derived-mode-p 'org-mode) (font-lock-flush)))))

(defun my/writing--section-number (numbering)
  "Format the optional section NUMBERING as secondary information."
  (propertize (concat (mapconcat #'number-to-string numbering ".") "  ")
              'face 'my-writing-heading-marker))

(defun my/writing--leave-numbering ()
  "Release section numbers before leaving the current major mode."
  (my/writing-numbering-mode -1))

(define-minor-mode my/writing-numbering-mode
  "Show optional two-level section numbering in Org or Markdown."
  :lighter nil :group 'my-writing
  (unless (or (derived-mode-p 'org-mode) (my/writing-markdown-p))
    (setq my/writing-numbering-mode nil)
    (user-error "Section numbering is available in Org and Markdown buffers"))
  (if (my/writing-markdown-p)
      (progn
        (if my/writing-numbering-mode
            (my/writing-markdown-numbering-enable)
          (my/writing-markdown-numbering-disable)))
    (require 'org-num)
    (if my/writing-numbering-mode
        (unless my/writing--saved-numbering
          (setq my/writing--saved-numbering
                (list org-num-mode
                      (my/writing--save-variables
                       '(org-num-max-level org-num-skip-unnumbered
                                           org-num-skip-footnotes org-num-format-function))))
          (setq-local org-num-max-level 2
                      org-num-skip-unnumbered t
                      org-num-skip-footnotes t
                      org-num-format-function #'my/writing--section-number)
          (org-num-mode 1))
      (when my/writing--saved-numbering
        (org-num-mode -1)
        (my/writing--restore-variables (cadr my/writing--saved-numbering))
        (when (car my/writing--saved-numbering) (org-num-mode 1))
        (setq my/writing--saved-numbering nil))))
  (if my/writing-numbering-mode
      (add-hook 'change-major-mode-hook #'my/writing--leave-numbering nil t)
    (remove-hook 'change-major-mode-hook #'my/writing--leave-numbering t)))

;;;###autoload
(defun my/writing-number-sections ()
  "Toggle quiet section numbers for the current Org or Markdown document."
  (interactive)
  (my/writing-numbering-mode 'toggle))

(add-hook 'window-state-change-functions #'my/writing--window-state-change)
(advice-add 'split-window :around #'my/writing--around-split-window)
(advice-add 'split-window-sensibly :around #'my/writing--around-split-window)

;;; Markdown section numbers



(defvar-local my/writing-markdown--numbering-enabled nil)
(defvar-local my/writing-markdown--numbering-overlays nil)
(defvar-local my/writing-markdown--numbering-timer nil)

(defun my/writing-markdown--numbering-cancel-timer ()
  "Cancel the pending numbering refresh in this buffer."
  (when (timerp my/writing-markdown--numbering-timer)
    (cancel-timer my/writing-markdown--numbering-timer))
  (setq my/writing-markdown--numbering-timer nil))

(defun my/writing-markdown--numbering-clear ()
  "Remove this buffer's Markdown numbering overlays."
  (mapc #'delete-overlay my/writing-markdown--numbering-overlays)
  (setq my/writing-markdown--numbering-overlays nil))

(defun my/writing-markdown--numbering-refresh ()
  "Refresh enabled Markdown numbering without altering source text."
  (my/writing-markdown--numbering-cancel-timer)
  (when my/writing-markdown--numbering-enabled
    (save-excursion
      (save-restriction
        (widen)
        (let ((headings (my/writing-markdown-headings))
              (section 0)
              (subsection 0))
          (my/writing-markdown--numbering-clear)
          (dolist (heading headings)
            (let* ((level (plist-get heading :level))
                   ;; Match Org: an H2 before the first H1 starts at 0.1.
                   (numbering
                    (cond ((= level 1)
                           (setq section (1+ section) subsection 0)
                           (list section))
                          ((= level 2)
                           (setq subsection (1+ subsection))
                           (list section subsection)))))
              (when numbering
                (let* ((begin (plist-get heading :content))
                       (end (min (point-max) (1+ begin)))
                       (overlay (make-overlay begin end nil t nil)))
                  (overlay-put overlay 'my-writing-markdown-numbering t)
                  (overlay-put overlay 'numbering numbering)
                  ;; A before-string follows the visibility of its starting
                  ;; character, so folded headings cannot leak their numbers.
                  (overlay-put overlay 'before-string
                               (my/writing--section-number numbering))
                  (when (< begin end) (overlay-put overlay 'evaporate t))
                  (push overlay my/writing-markdown--numbering-overlays)))))
          (setq my/writing-markdown--numbering-overlays
                (nreverse my/writing-markdown--numbering-overlays)))))))

(defun my/writing-markdown--numbering-refresh-buffer (buffer)
  "Refresh numbering if BUFFER is still alive and enabled."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (my/writing-markdown--numbering-refresh))))

(defun my/writing-markdown--numbering-after-change (&rest _)
  "Debounce section renumbering while the source is being edited."
  (my/writing-markdown--numbering-cancel-timer)
  (when my/writing-markdown--numbering-enabled
    (setq my/writing-markdown--numbering-timer
          (run-with-idle-timer
           0.2 nil #'my/writing-markdown--numbering-refresh-buffer
           (current-buffer)))))

(defun my/writing-markdown-numbering-enable ()
  "Enable display-only Markdown numbering in the current buffer."
  (unless my/writing-markdown--numbering-enabled
    (setq my/writing-markdown--numbering-enabled t)
    (add-hook 'after-change-functions
              #'my/writing-markdown--numbering-after-change nil t)
    (add-hook 'change-major-mode-hook
              #'my/writing-markdown-numbering-disable nil t)
    (add-hook 'kill-buffer-hook
              #'my/writing-markdown-numbering-disable nil t))
  (my/writing-markdown--numbering-refresh))

(defun my/writing-markdown-numbering-disable ()
  "Disable Markdown numbering and release its hooks, timer and overlays."
  (setq my/writing-markdown--numbering-enabled nil)
  (my/writing-markdown--numbering-cancel-timer)
  (my/writing-markdown--numbering-clear)
  (remove-hook 'after-change-functions
               #'my/writing-markdown--numbering-after-change t)
  (remove-hook 'change-major-mode-hook
               #'my/writing-markdown-numbering-disable t)
  (remove-hook 'kill-buffer-hook
               #'my/writing-markdown-numbering-disable t))

;;; Markdown faces and automatic typography

(declare-function treesit-font-lock-rules "treesit" (&rest query-specs))
(declare-function treesit-font-lock-recompute-features "treesit"
                  (&optional add-list remove-list language))
(defvar treesit-font-lock-settings)

(defvar-local my/writing--markdown-ts-original-settings nil)

(defun my/writing-markdown-ts-faces ()
  "Add prose faces to the bundled `markdown-ts-mode' fontification rules.
That mode uses generic code faces rather than `markdown-header-face-N'."
  (when (and (fboundp 'treesit-parser-list) (treesit-parser-list))
    (unless my/writing--markdown-ts-original-settings
      (setq my/writing--markdown-ts-original-settings treesit-font-lock-settings))
    (setq-local treesit-font-lock-settings
                (append
                 my/writing--markdown-ts-original-settings
                 (treesit-font-lock-rules
                  ;; The bundled inline parser covers the whole buffer.  Apply
                  ;; block faces last so fenced code stays a single surface.
                  :language 'markdown-inline :feature 'paragraph-inline :override t
                  '((code_span) @my-writing-inline-code
                    (link_destination) @my-writing-path
                    (uri_autolink) @my-writing-path)
                  :language 'markdown :feature 'paragraph :override t
                  '((atx_heading (atx_h1_marker)) @my-writing-heading-1
                    (atx_heading (atx_h2_marker)) @my-writing-heading-2
                    (atx_heading (atx_h3_marker)) @my-writing-heading-3
                    (atx_heading (atx_h4_marker)) @my-writing-heading-3
                    (atx_heading (atx_h5_marker)) @my-writing-heading-3
                    (atx_heading (atx_h6_marker)) @my-writing-heading-3
                    (setext_heading (setext_h1_underline)) @my-writing-heading-1
                    (setext_heading (setext_h2_underline)) @my-writing-heading-2
                    (fenced_code_block) @my-writing-code-block
                    (indented_code_block) @my-writing-code-block
                    (pipe_table) @fixed-pitch
                    (minus_metadata) @shadow
                    (plus_metadata) @shadow)
                  :language 'markdown :feature 'paragraph :override 'prepend
                  '((fenced_code_block_delimiter) @shadow
                    (info_string) @shadow
                    (atx_h1_marker) @shadow
                    (atx_h2_marker) @shadow
                    (atx_h3_marker) @shadow
                    (atx_h4_marker) @shadow
                    (atx_h5_marker) @shadow
                    (atx_h6_marker) @shadow
                    (setext_h1_underline) @shadow
                    (setext_h2_underline) @shadow))))
    (treesit-font-lock-recompute-features)
    (font-lock-flush)))

(dolist (hook '(org-mode-hook markdown-mode-hook markdown-ts-mode-hook))
  (add-hook hook #'my/writing-typography-mode))
(add-hook 'markdown-ts-mode-hook #'my/writing-markdown-ts-faces)

(provide 'init-writing)
;;; init-writing.el ends here
