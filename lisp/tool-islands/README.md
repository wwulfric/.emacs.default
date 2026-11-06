# tool-islands

The pieces JetBrains' New UI builds its tool windows from, for Emacs:
rows of one height in the interface font, a rounded pill for the selected
row, headers with toolbars and buttons, side panes that keep their width,
and folder trees that merge single-folder chains ("a/b").

[Git Islands](https://github.com/wwulfric/git-islands) draws its Git tool
windows with them; any other tool window can draw its list the same way.

## Requirements

- Emacs 29.1 or later, with SVG support for pills and checkboxes
- [magit-section](https://github.com/magit/magit) 4.0 or later (rows are sections; Magit itself is not needed)
- [expui-icons](https://github.com/wwulfric/expui-icons) 0.2.2 or later

## A list

```elisp
(require 'magit-section)
(require 'tool-islands)

(define-derived-mode my-list-mode magit-section-mode "List"
  (setq-local magit-section-highlight-current nil
              magit-section-visibility-indicators nil
              header-line-format
              '(:eval (tool-islands-header-line
                       (concat (propertize " " 'display (tool-islands-header-space 0))
                               (propertize " Things" 'face 'tool-islands-title)))))
  (tool-islands-view-setup))

(with-current-buffer (get-buffer-create " *things*")
  (my-list-mode)
  (let ((inhibit-read-only t))
    (magit-insert-section (root)
      (magit-insert-section (folder "src")
        (tool-islands-row 0 (tool-islands-icon "nodes/folder") (tool-islands-gap)
                          (tool-islands-fit "src"))
        (magit-insert-heading)
        (magit-insert-section (file "main.el")
          (tool-islands-row 1 (tool-islands-icon "nodes/function") (tool-islands-gap)
                            (tool-islands-fit "main.el"))))))
  (tool-islands-draw-chevrons)
  (pop-to-buffer (current-buffer)))
```

Give the buffer a name starting with a space, as Git Islands does: global
Font Lock leaves such buffers alone, and would otherwise remove the rows'
faces.

`tool-islands-toggle-section`, `tool-islands-expand-all` and
`tool-islands-collapse-all` fold the rows; `tool-islands-toolbar` makes a
header toolbar of `(ICON ACTION HELP)` entries, and `tool-islands-button`
a header button.  `tool-islands-pane-keep` keeps a side window as wide as
a function says, as a share of the frame.

## Look

Faces and sizes have plain defaults; tie them to your own:

| Variable or face | What it sets |
|---|---|
| `tool-islands-row-height` | Row height, in frame character units |
| `tool-islands-hl-radius`, `tool-islands-hl-margin` | Rounded selection; keep `tool-islands-row-inset` at least their sum |
| `tool-islands-header-height`, `tool-islands-header-padding`, `tool-islands-header-ascent` | Header metrics |
| `tool-islands-header-space-function` | Header height shared with the editor's own headers |
| `tool-islands-header-function` | Gets each header's format and returns the one to show, say inside rounded corners |
| `tool-islands-background-function` | The color tool windows are drawn on, or nil for the default face's |
| `tool-islands-line-end-inset` | Pixels kept free at the right end of headers |
| `tool-islands-button-render-function` | `tool-islands-button-text` or `tool-islands-button-rounded` |
| `tool-islands-font`, `tool-islands-text`, `tool-islands-title`, `tool-islands-dim` | Typography; keep `tool-islands-font` to font attributes |
| `tool-islands-hl-line`, `tool-islands-hl-line-inactive` | The selected row, in the selected window and in others |
| `tool-islands-neutral-icon`, `tool-islands-source-icon` | Icon colors, with `tool-islands-source-icons` naming the accented ones |

## Tests

```sh
make test
```

The Makefile looks for magit, compat, cond-let, dash, llama and
expui-icons beside this checkout; point `DEPS` elsewhere if needed.

## License

Apache-2.0
