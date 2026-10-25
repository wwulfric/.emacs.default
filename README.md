# .emacs.d

一套仿 JetBrains New UI 的 Emacs 配置：基于 Dired 的项目侧边栏、Search Everywhere 风格的
minibuffer 面板、Islands 卡片布局，以及来自 [git-islands](https://github.com/wwulfric/git-islands)
的 Git 工具窗口。

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
| `s-p` | Search files; a first > @ # : or % searches another kind |
| `C-x C-b` | Begin using Ibuffer to edit a list of buffers |
| `M-x` | Open the search window on commands |
| `M-g i` | Select item from flattened ‘imenu’ using ‘completing-read’ with preview |

### Code

| Key | Action |
|---|---|
| `s-[` `C-c n b` | Go back to the previous position in xref history |
| `s-]` `C-c n f` | Go to the point where a previous M-, was invoked |

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
| `s-?` | List the configuration’s keyboard shortcuts; run the one chosen |
| `C-<return>` | Start a new, indented line above the current one |
| `S-<return>` | Start a new, indented line below the current one |
| `S-s-<down>` | Move the current line or selected lines down COUNT lines |
| `S-s-<up>` | Move the current line or selected lines up COUNT lines |
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
| `TAB` | Fold or unfold the folder at point |
| `n` | Move cursor vertically down ARG lines |
| `o` | Open the file at point as it is now |
| `p` | Move cursor vertically up ARG lines |
| `q` | Hide FRAME’s Git tool window |

### In the Branches pane

| Key | Action |
|---|---|
| `RET` | Filter the log to the branch at point |
| `TAB` | Fold or unfold the folder at point |
| `g` | List the repository’s branches |
| `n` | Move cursor vertically down ARG lines |
| `p` | Move cursor vertically up ARG lines |
| `q` | Hide FRAME’s Git tool window |

### In the Diff

| Key | Action |
|---|---|
| `<f7>` `C-c C-n` | Move to the next difference |
| `S-<f7>` `C-c C-p` | Move to the previous difference |
| `C-c C-k` | Close the diff and restore the windows as they were |
| `C-c C-r` | Replace the right side’s lines of the difference at point with the left’s |
| `C-c C-s` | Stage the difference at point |
| `C-c C-u` | Show the same file’s changes in Magit’s unified diff, to stage by line |

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

<!-- keys:end -->
