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
