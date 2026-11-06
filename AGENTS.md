# Notes for agents

## Icons

The interface follows JetBrains' New UI, so its icons come from IntelliJ's
own `expui` set, through the expui-icons package in `lisp/expui-icons`.

1. Use an expui icon whenever one fits: `expui-icons-icon` and
   `expui-icons-image` with its name, such as `"vcs/push"` or
   `"general/close"`.  The bundled names are the files under
   `lisp/expui-icons/icons`.
2. If the icon is not bundled, look for it upstream before anything else:
   in intellij-community's `platform/icons/src/expui` at the commit pinned
   in `lisp/expui-icons/scripts/COMMIT`, and in the index of
   <https://intellij-icons.jetbrains.design> (`data.json`), which covers
   plugins' icon sets too, such as `DvcsImplIcons`.  An icon found there
   is added to expui-icons (`scripts/manifest.txt`, then
   `scripts/update-icons.sh`), not copied into this configuration.
3. Draw an icon only when IntelliJ has none, as when it paints one in
   code.  Then follow IntelliJ's painter: the Git log's ref labels copy
   the geometry of `TagPainter.kt`.  Say in a comment where the shape
   comes from.

## Layout changes

Any change to a window's size, fringes or margins while the editor
scrolls by pixels (`pixel-scroll-precision-mode`) resets the scroll
offset, and the view jumps back.  Several parts of this configuration
write the layout from hooks: the status bar sets the echo area's height,
Git Islands sets its panes' widths, `frame-setting.el` and
`init-islands.el` set fringes, and `init-writing.el` sets margins.  If one
of these writes does not settle, it repeats on every redisplay, and
scrolling stutters.  Twice already this has been a target one pixel off
what Emacs would allow.

1. Write the layout only when the geometry may have changed: in
   `window-size-change-functions`, `window-state-change-functions` or
   when a mode turns on.  Never write it from a content refresh, such as
   the status bar's text, the cursor's position, a timer or
   `post-command-hook`.
2. Compare before writing, and skip a write that changes nothing: even a
   zero-delta `window-resize`, or fringes set to their current values,
   applies the layout again.
3. Aim at a target Emacs keeps.  Measure with Emacs's own rules (as
   `window-default-line-height`, not the size of styled text), and resize
   pixelwise with `window-resize-pixelwise` bound to t, or the delta is
   rounded to character cells.
4. When the target cannot be reached, as when a neighbour is at its
   minimum size, remember the attempt and do not retry it on every later
   size change.  A flag against recursion stops only nested calls, not
   the next event's retry.
5. Do not hide a stutter with timers, `scroll-conservatively` or by
   restoring the scroll position: find the writer that keeps changing.
6. The global `window-size-change-functions` and
   `window-state-change-functions` also run for child frames, the
   popups and Sticky Lines (`init-sticky-lines.el`), whose size changes
   as the editor scrolls.  A writer for the frame's own layout skips
   them: `(frame-parent frame)` is non-nil.
7. Something drawn over the editor, as Sticky Lines and Parameter Info
   are, goes in a child frame, which leaves the window's layout alone; an
   overlay or header line that changes the text's height does not.

After changing any of these writers, or adding one, replay scrolling in
the running GUI Emacs with `tests/scroll-replay.el` (its commentary shows
how) and check that `:jumps` is 0 and no layout writer appears in
`:writes`.  Calling the scroll commands from Lisp does not show the
problem; the replay sends real wheel events through the command loop.
