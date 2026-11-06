# .emacs.d

一套仿 JetBrains New UI 的 Emacs 配置：基于 Dired 的项目侧边栏、Search Everywhere 风格的
minibuffer 面板、Islands 卡片布局，以及来自 [git-islands](https://github.com/wwulfric/git-islands)
的 Git 工具窗口。

另外搬来了 IntelliJ 的这些编辑功能，快捷键见下方表格：

- **Find 和 Problems 工具窗口**（`s-3`、`s-6`），底部的列表由 [tool-islands](https://github.com/wwulfric/tool-islands) 绘制。
- **Alt+Enter**（`M-RET`）：在光标旁列出语言服务器的 quick fix 和重构。
- **Extend Selection**（`M-<up>` / `M-<down>`）和 **Recent Locations**（`S-s-e`）。
- **Parameter Info**（`s-P`）：在调用上方显示参数，输入 `(` 或 `,` 时自动弹出。
  **Inlay hints** 默认打开，`M-x my/inlay-hints-toggle` 可以关掉。
- **多光标**（`s-d` 等），由 multiple-cursors 提供。鼠标操作和 IntelliJ 一样：
  ⌥⇧ 点击加一个光标或去掉已有的；⌥⇧ 拖动则在拖过的每一行各放一个光标和选区（列选择）。
  这两种鼠标操作不在下面的表格里。
- **Sticky Lines**：滚动时，窗口顶部钉住当前所在的 class、函数和代码块的第一行，点击可跳过去。
  `M-x my/sticky-lines-mode` 可以关掉。

## Python 语言服务

使用 Zuban 提供补全、定义跳转、引用与类型诊断，Ruff 提供 lint、格式化和修复。
在配置目录安装工具（沿用 lsp-bridge 的 `.venv`）：

```sh
uv pip install --python .venv/bin/python 'zuban==0.10.1' ruff
```

自定义配置位于 `lisp/langserver/zuban.json` 和
`lisp/multiserver/zuban_ruff.json`，无需修改 lsp-bridge 源码。
Zuban 从项目目录启动并自动发现项目环境；工具的 `.venv` 与业务项目环境分开。
定义跳转失败时使用 dumb-jump 和 `rg` 搜索同名候选。
Zuban 0.10.1 会把 lsp-bridge 启动时发送的空
`workspace/didChangeConfiguration` 通知记录为 `unhandled notification`；
初始化选项仍正常生效，已验证不影响跳转及诊断。

如需回切，将 `lsp-bridge-python-lsp-server` 设为 `"basedpyright"`，
`lsp-bridge-python-multi-lsp-server` 设为 `"basedpyright_ruff"`，然后执行
`M-x lsp-bridge-restart-process`。已有的 basedpyright 配置保留。

## 维护与测试

个人配置在 `lisp/init-*.el`、`lisp/ui/` 和 `lisp/git/`；独立包通过
Git submodule 管理，各包的测试保留在包内。

运行配置层的回归测试（需要本机 Emacs 和已检出的子模块）：

```sh
sh tests/run.sh
# 也可只运行指定测试：
sh tests/run.sh tests/editing-tests.el tests/init-frame-title-tests.el
```

可用 `EMACS=/path/to/emacs` 指定可执行文件。每个测试文件使用独立 Emacs
进程和临时状态目录，优先加载较新的源码，不读写日常的 `var/`。
`tests/` 中的回归测试应纳入版本控制。

布局改动还需要在运行中的 GUI Emacs 中执行 `tests/scroll-replay.el`
文件头说明的滚动回放，确认 `:jumps` 为 0 且 `:writes` 为空；批处理测试不能替代它。

## 找快捷键

- **`s-?`**：打开快捷键参考面板，按区域分组列出本配置新增的所有快捷键；可以按说明、命令名或按键搜索，回车直接执行。
- **点击或 M-x 时的提示**：用鼠标点了按钮、或用 M-x 执行了一个其实有快捷键的命令时，状态栏会提示它的快捷键（每个命令每次启动最多提示 3 次）。
- **前缀键提示**：按下 `C-x`、`C-c` 等前缀键后稍等，会浮出接下来可按的键（which-key）。

下面的表格由 `M-x my/keys-update-readme` 从按键表生成，和 `s-?` 面板是同一份数据。

## 快捷键

<!-- keys:start -->
### Git

| Key | Action |
|---|---|
| `s-0` | Focus the Commit tool window; hide it when already focused |
| `s-9` | Focus the Git tool window; hide it when already focused |
| `s-k` | Show the Commit tool window and put point in the commit message |
| `C-~` | Show the Git branches popup for ROOT, the current repository by default |
| `C-x g` | Show the status of the current Git repository in a buffer |
| `C-c M-g` | Invoke a Magit command that acts on the visited file |
| `C-x M-g` | Invoke a Magit command from a list of available commands |
| `C-x v g` | Annotate the buffer with Git blame, or stop annotating it |

### Sidebar

| Key | Action |
|---|---|
| `s-1` `C-c e` | Focus the sidebar from the editor; hide it when already focused |

### Search

| Key | Action |
|---|---|
| `s-<f12>` `s-t` | Open the search window on structure |
| `s-F` | Open the search window on text |
| `s-O` | Open the search window on files |
| `s-e` `C-x b` | Enhanced ‘switch-to-buffer’ command with support for virtual buffers |
| `s-l` `M-g g` | Open the search window on line |
| `s-p` | Search files; a first prefix searches another kind |
| `C-x C-b` | Begin using Ibuffer to edit a list of buffers |
| `M-x` | Open the search window on commands |
| `M-g i` | Select item from flattened ‘imenu’ using ‘completing-read’ with preview |

### Code

| Key | Action |
|---|---|
| `s-3` | Focus the Find tool window; hide it when already focused |
| `s-6` | Focus the Problems tool window; hide it when already focused |
| `s-E` `S-s-e` | Go to a place visited or changed lately, chosen from a list |
| `s-P` | Show the parameters of the call around point, as Cmd-P does in IntelliJ |
| `s-[` `C-c n b` | Go back to the previous position in xref history |
| `s-]` `C-c n f` | Go to the point where a previous M-, was invoked |
| `M-<f7>` | List the usages of the symbol at point in the Find tool window |
| `M-s-<down>` | Go to the next usage the Find tool window lists |
| `M-s-<up>` | Go to the previous usage the Find tool window lists |

### Workspaces

| Key | Action |
|---|---|
| `C-x p R` | Discard the current layout and return to the last saved workspace |
| `C-x p k` | Save the project, kill its buffers and return to the start page |
| `C-x p w` | Show the start page in the selected window |

### Tabs

| Key | Action |
|---|---|
| `C-x <left>` `C-x C-<left>` | Switch to the ARGth previous tab’s buffer |
| `C-x <right>` `C-x C-<right>` | Switch to the next ARGth tab’s buffer |
| `C-x M-<left>` | Move a tab to a different position on the tab line |
| `C-x M-<right>` | Move a tab to a different position on the tab line |
| `C-x k` | Kill the current buffer without asking which |

### Editing

| Key | Action |
|---|---|
| `s-/` | Smart comment/uncomment for line or region |
| `s-<backspace>` | Delete the current line without copying to kill ring |
| `s-?` `S-s-/` | List the configuration’s keyboard shortcuts; run the one chosen |
| `s-D` | Drop the occurrence added last, as Ctrl-Shift-G does in IntelliJ |
| `s-d` | Select the word at the caret, then add its next occurrence |
| `C-<return>` | Start a new, indented line above the current one |
| `C-s-g` | Select every occurrence of the selection or of the word at the caret |
| `M-<down>` | Go back to the selection before the last Extend Selection |
| `M-<up>` | Select the piece of code around the selection, or around point |
| `M-S-<down>` | Add a caret on the line below |
| `M-S-<up>` | Add a caret on the line above |
| `S-<return>` | Start a new, indented line below the current one |
| `S-s-<down>` | Move the current line or selected lines down COUNT lines |
| `S-s-<up>` | Move the current line or selected lines up COUNT lines |
| `M-G` | Put a caret at the end of each line of the selection |
| `M-b` | 智能向后单词移动 |
| `C-x C-k C-a` | Add the value of numeric prefix arg (prompt if missing) to ‘kmacro-counter’ |
| `C-x C-k C-c` | Set the value of ‘kmacro-counter’ to ARG, or prompt for value if no argument |
| `C-x C-k C-d` | Delete current macro from keyboard macro ring |
| `C-x C-k C-e` | Edit last keyboard macro |
| `C-x C-k C-f` | Set the format of ‘kmacro-counter’ to FORMAT |
| `C-x C-k C-k` | As ‘kmacro-end-or-call-macro’ but allow repeat without repeating prefix |
| `C-x C-k C-l` | Execute second keyboard macro in macro ring |
| `C-x C-k C-n` | Move to next keyboard macro in keyboard macro ring |
| `C-x C-k C-p` | Move to previous keyboard macro in keyboard macro ring |
| `C-x C-k C-s` `C-x C-k s` | Record subsequent keyboard input, defining a keyboard macro |
| `C-x C-k C-t` | Swap first two elements on keyboard macro ring |
| `C-x C-k C-v` | Display the last keyboard macro |
| `C-x C-k RET` | As edit last keyboard macro, but without kmacro-repeat property |
| `C-x C-k SPC` | Step edit and execute last keyboard macro |
| `C-x C-k TAB` | Insert current value of ‘kmacro-counter’, then increment it by ARG |
| `C-x C-k b` | When not defining or executing a macro, offer to bind last macro to a key |
| `C-x C-k d` | Force redisplay during keyboard macro execution |
| `C-x C-k e` | Edit a keyboard macro |
| `C-x C-k l` | Edit most recent 300 keystrokes as a keyboard macro |
| `C-x C-k n` | Assign a name to the last keyboard macro defined |
| `C-x C-k q` | Query user during kbd macro execution |
| `C-x C-k r` | Apply last keyboard macro to all lines in the region |
| `C-x C-k x` | Store the last keyboard macro in register R |
| `C-x C-k C-q <` | Quit the keyboard macro if the counter is less than ARGS |
| `C-x C-k C-q =` | Quit the keyboard macro if the counter is equal to ARG |
| `C-x C-k C-q >` | Quit the keyboard macro if the counter is greater than ARG |
| `C-x C-k C-r l` | Load the value of a REGISTER into ‘kmacro-counter’ |
| `C-x C-k C-r s` | Save the value of ‘kmacro-counter’ to a REGISTER |

### In the Sidebar

| Key | Action |
|---|---|
| `RET` | Open the file at point in the editor, or list the folder at point here |
| `TAB` | Expand or collapse the folder at point |
| `^` | List the parent of the sidebar’s folder |
| `q` | Hide FRAME’s sidebar, keeping its buffer for the next time it shows |

### In the Start page

| Key | Action |
|---|---|
| `*` | Pin the selected project to the top, or unpin it |
| `/` | Narrow the list while typing; an empty input or C-g clears the filter |
| `1` `2` `3` `4` `5` `6` `7` `8` `9` | Open the project or file with this number |
| `<down>` `n` | Move to the Nth next selectable row; stay put at the last one |
| `<up>` `p` | Move to the Nth previous selectable row |
| `RET` | Open the selected row; with NEW-FRAME open the project in a new frame |
| `d` | Remove the selected project from the list; its saved workspace is kept |
| `o` | Open DIRECTORY’s project, or DIRECTORY itself, as a workspace |
| `q` | Leave the start page for the previous buffer or an empty editor |

### In the Commit tool window

| Key | Action |
|---|---|
| `s-k` `c` | Show the Commit tool window and put point in the commit message |
| `<f4>` `o` | Open the file at point in the editor |
| `<tab>` `TAB` | Fold or unfold the group or folder at point |
| `M` | Open the repository in Magit’s status buffer |
| `R` `M-s-z` | Discard the changes of the row at point, after confirmation |
| `RET` | Show the file at point side by side with HEAD, or fold the row at point |
| `SPC` | Check or uncheck the row at point, staging or unstaging its files |
| `g` | Read the repository’s status again |
| `m` | Move the changed files of the row at point to another changelist |
| `n` | Move cursor vertically down ARG lines |
| `p` | Move cursor vertically up ARG lines |
| `q` | Hide FRAME’s Commit tool window |
| `t` | Switch between files grouped by folder and a flat list |

### In the Commit message

| Key | Action |
|---|---|
| `s-0` | Focus the Commit tool window; hide it when already focused |
| `s-<return>` `C-c C-c` | Commit the checked files with this message; then push if PUSH |
| `C-c C-a` | Amend the last commit, or stop amending it |
| `C-c C-p` `M-s-k` | Commit the checked files with this message, then push |
| `M-n` | Replace the message with a later commit’s message |
| `M-p` | Replace the message with an earlier commit’s message |

### In the Git log

| Key | Action |
|---|---|
| `/` | Show the commits whose message contains a text only |
| `C` | Show every commit of every branch again |
| `P` | Show the commits changing a file or folder only |
| `RET` | Show the selected commits’ changes in the editor |
| `S-<down>` | Add the next row to the selection |
| `S-<up>` | Add the previous row to the selection |
| `TAB` | Move to the details pane |
| `b` | Show the commits of BRANCH only, or of all branches |
| `d` | Show the commits made since a date only |
| `g` | Read the commits again from the start, as after a filter changed |
| `n` | Move cursor vertically down ARG lines |
| `p` | Move cursor vertically up ARG lines |
| `q` | Hide FRAME’s Git tool window |
| `u` | Show the commits of one author only |
| `w` | Copy the selected commits’ hashes |
| `x` | Choose what to do with the selected commits |

### In the Commit details

| Key | Action |
|---|---|
| `RET` | Show the file at point side by side, before and after the commit |
| `TAB` | Fold or unfold the group or folder at point |
| `n` | Move cursor vertically down ARG lines |
| `o` | Open the file at point as it is now |
| `p` | Move cursor vertically up ARG lines |
| `q` | Hide FRAME’s Git tool window |

### In the Branches pane

| Key | Action |
|---|---|
| `RET` | Filter the log to the branch at point |
| `TAB` | Fold or unfold the group or folder at point |
| `g` | List the repository’s branches |
| `n` | Move cursor vertically down ARG lines |
| `p` | Move cursor vertically up ARG lines |
| `q` | Hide FRAME’s Git tool window |

### In the Diff

| Key | Action |
|---|---|
| `<f7>` `C-c C-n` | Move to the next difference |
| `S-<f7>` `C-c C-p` | Move to the previous difference |
| `C-c C-b` | Show the diff of the previous file of the list the diff was opened from |
| `C-c C-f` | Show the diff of the next file of the list the diff was opened from |
| `C-c C-k` | Close the diff and restore the windows as they were |
| `C-c C-r` | Replace the right side’s lines of HUNK with the left’s |
| `C-c C-s` | Stage HUNK, or unstage it when the index already has it |
| `C-c C-u` | Switch the diff between the side-by-side and the unified viewer |

### In the Conflicts

| Key | Action |
|---|---|
| `RET` `m` | Merge the file at point in three panes: yours, the result and theirs |
| `e` | Merge the file at point in Magit’s three-way Ediff |
| `g` | Read the repository’s status again |
| `n` | Move cursor vertically down ARG lines |
| `o` | Open the file at point, its conflicts marked by ‘smerge-mode’ |
| `p` | Move cursor vertically up ARG lines |
| `q` | Quit WINDOW and bury its buffer |
| `t` | Resolve the file at point, or those in the region, with their version |
| `y` | Resolve the file at point, or those in the region, with your version |

### In the Merge

| Key | Action |
|---|---|
| `<f7>` `C-c C-n` | Move to the next conflict |
| `S-<f7>` `C-c C-p` | Move to the previous conflict |
| `C-c C-b` | Resolve the conflict at point with your version, then theirs |
| `C-c C-c` | Save the result, mark the file resolved and close the merge |
| `C-c C-k` | Close the merge, keeping the result’s edits unsaved and the file unresolved |
| `C-c C-l` | Resolve the conflict at point with your version |
| `C-c C-r` | Resolve the conflict at point with their version |

### In the Annotate

| Key | Action |
|---|---|
| `C-c C-l` | Select the commit annotating the line at point in the Git log |

### In the Changed lines

| Key | Action |
|---|---|
| `C-M-s-<down>` | Go to the beginning of the next hunk in the current buffer |
| `C-M-s-<up>` | Go to the beginning of the previous hunk in the current buffer |
| `M-s-z` | Revert the diff hunk with changes at or above the point |

### In the Find tool window

| Key | Action |
|---|---|
| `<f4>` `RET` | Go to the usage at point, or fold or unfold the file or folder there |
| `M-s-<down>` | Go to the next usage the Find tool window lists |
| `M-s-<up>` | Go to the previous usage the Find tool window lists |
| `SPC` | Show the usage at point in the editor, staying in the Find window |

### In the Problems tool window

| Key | Action |
|---|---|
| `<f4>` `RET` | Go to the problem at point, or fold or unfold the file there |
| `SPC` | Show the problem at point in the editor, staying in the Problems window |
| `a` | Switch between the edited file’s problems and every open file’s |
| `g` | List the problems again |

### In the Multi-caret mode

| Key | Action |
|---|---|
| `<escape>` | Go back to one caret, dropping the selections too, as Escape in IntelliJ |
| `C-'` | Hide the lines without a caret |
| `C-:` | Repeat the last command at every caret |
| `C-g` | Drop the selections; again, go back to one caret |
| `C-v` | Scroll to the next caret |
| `M-v` | Scroll to the previous caret |

<!-- keys:end -->
