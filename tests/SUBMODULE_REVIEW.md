# Owner 子模块检查记录

日期：2026-11-07。范围按 `.gitmodules` 中 `wwulfric` 名下的 8 个仓库确定。
检查了入口与调用关系、内部兼容代码、测试归属及执行方式；对 fork 保留其
上游仍支持的功能，没有因为主配置当前不用就删除公开接口。

## 本轮调整与验证

| 子模块 | 调整 | 验证结果 |
|---|---|---|
| git-islands | 将 9 个纯 UI 测试迁回 tool-islands；重命名回滚测试使用临时废纸篓，避免依赖系统废纸篓 | 严格字节编译通过，51 个 ERT 通过 |
| tool-islands | 接回按钮、页眉、面板布局测试；保留检查前已有的布局修复与 2 个测试 | 严格字节编译通过，17 个 ERT 通过 |
| palette-islands | 模式关闭后恢复原有滚轮绑定；尊重 Consult 是否启用 recenter，恢复时保留其他 hook | 严格字节编译通过，12 个 ERT 通过 |
| expui-icons | 默认回退图标纳入缓存键，动态更改默认图标不再命中旧图像 | 严格字节编译、checkdoc 通过，22 个 ERT 通过 |
| intellij-server | Windows 安装不再尝试 chmod 不存在的 Unix 启动器；补测试入口 | 14 个 ERT 通过，含真实 Java 代理与假服务进程测试 |
| lsp-bridge | 修正多签名参数切片及激活参数；删除全部注释掉的测试实验和无测试的辅助类；增加离线入口、本地依赖选项，并让桥接进程使用测试解释器 | 离线 Python 31 个、ERT 25 个通过；完整集成入口 ERT 9 个、Python 36 个通过（包含重叠用例和字节编译） |
| emacs-chinese-word-segmentation | 删除未使用的宽字符转换与头文件；处理空行；按 UTF-8 字符而非固定 3 字节计算词长 | 编译通过，1 个 Python 协议测试覆盖 7 类输入 |
| rime | 删除空的临时维护入口；支持通过 RIME_DIR 指定维护副本，补文档和测试 | go test ./... 通过，1 个路径测试；未执行词库改写或 Rime 引擎部署 |

4 个 UI 包的 Makefile 均设置 `load-prefer-newer`，避免旧 `.elc` 掩盖源码改动。
主配置的 48 个回归测试也全部通过。

运行中的 GUI Emacs 加载当前 tool-islands 源码，保留 Git 工具窗口，
在临时长文本缓冲区执行 `tests/scroll-replay.el`：45 次真实滚轮事件，
结果为 `(:events 45 :jumps 0 :writes nil :first-jumps nil)`，之后恢复窗口。

## 复跑方式

- 4 个 UI 包：在各自目录运行 `make all`。
- IntelliJ：`INTELLIJ_SERVER_DIRECTORY=/path/to/install make test`。
  未提供已安装 JDK 时，代理进程测试会跳过；本轮使用 `var/intellij-server`，未跳过。
- lsp-bridge：见该仓库的 `test/README.md`。本轮使用主配置的 `.venv/bin/python`
  和相邻依赖，并实际启动 basedpyright 等语言服务完成集成测试。
- 中文分词：`make test`。
- Rime：在 `rime/others/script` 运行 `RIME_DIR=/path/to/rime go test ./...`。
  本轮默认 Go 代理连接失败后使用 `goproxy.cn`，依赖版本和校验仍由 go.mod/go.sum 固定。
- 主配置：`sh tests/run.sh`。

Git 的部分测试与 lsp-bridge 集成测试需要本地 socket；受限沙箱内的初次失败
属于环境限制，允许本地进程通信后通过。中文分词构建仍有来自 vendored
cppjieba 的 C++ 弃用警告，本轮没有改动该第三方库。

## 保留与后续设计建议

- `git-islands-ui.el` 的旧别名层已在后续清理中删除，见下文；个人配置只维护最新接口。
- 中文分词的 Lisp 客户端仍按进程输出块解析结果；如进一步改造，宜采用按行缓冲
  和明确的请求完成状态，并覆盖拆包、合包及进程退出场景。
- Rime 维护包仍在初始化时读取词库。下一步可将路径与词库状态封装成显式创建的
  对象，使纯逻辑测试不需要整套词库；本轮通过 RIME_DIR 先消除固定个人目录依赖。

tool-islands 的运行时代码变更在本轮开始时已存在，本轮没有将其作为新实现覆盖。

## 依赖关系优化与验证

- lsp-bridge 提供 `lsp-bridge-server-config-features` 能力声明；IntelliJ
  适配器在注册前检查所需能力及内部入口的参数数量，不兼容时给出更新提示，
  不留下部分安装的 advice 或模式注册。仍需使用同一 checkout 的 Lisp 与 Python。
- Python 支持范围统一为 3.12–3.13；锁文件补齐 3.12 所需产物，依赖版本未变。
  两个 CI 工作流均覆盖两个版本并使用锁文件，启动脚本使用 `--frozen` 避免改写锁文件。
- Git Islands 的 tree、merge3 直接依赖 tool-islands，启动不再加载旧 UI 别名层；
  兼容层保留供旧配置显式加载，README 补迁移说明。

本地验证：Git Islands 严格字节编译及 52 个 ERT 通过；IntelliJ 核心 14 个、
适配器 5 个 ERT 通过。lsp-bridge 在独立 Python 3.12.11 和 3.13.5 环境中，
各通过 31 个离线 Python 测试及完整集成入口的 36 个 Python、9 个 ERT；
另有离线 ERT 25 个通过。两套环境均验证启动脚本，锁文件一致性检查通过。
主配置 48 个回归测试通过，工作流 YAML 解析通过；未将本地验证视为远端 CI 结果。
本次没有改动布局写入逻辑。

## 删除旧 UI 兼容层

按个人配置只支持最新接口的要求，删除 `git-islands-ui.el` 的 87 条旧名称别名，
以及仅检查兼容层加载状态的测试，移除 README 中按需加载旧兼容层的说明。
删除前检索当前配置与子模块 Lisp 源码，未发现旧别名调用。
清理旧 `.elc` 后，Git Islands 严格字节编译及剩余 51 个 ERT、主配置 48 个
回归测试全部通过。共享 UI 的函数、变量和 face 统一使用 `tool-islands` 名称。

## 主配置与其余自有库的历史兼容清理

检查主配置及 tool-islands、palette-islands、expui-icons、intellij-server、
lsp-bridge、emacs-chinese-word-segmentation、rime 的自有源码和测试：

- 主配置：移除根目录 projects/recentf 向 var/ 的启动迁移，现有状态已在 var/；
  移除 Emacs 31 以前的行间距与侧栏宽度计算分支，README 明确使用 Emacs 31。
- lsp-bridge：删除 3 个无调用的旧命令/变量别名、Yasnippet 的旧 t 值转换、
  Python 3.7 以前的 subprocess 分支、Emacs 27 以前的弹窗坐标分支；
  删除 prefixCaseSensitive 合并选项，大小写统一由 case-mode 设置。
- 其余 6 个自有库未发现同类需要删除的代码或专门测试，未产生空提交。
  图标/终端回退、可选后端检测、IntelliJ 能力检查属于当前运行行为，保留。
  vendored cppjieba/gtest 不作为自有兼容代码改写。没有发现仅覆盖上述已删分支的测试。

验证：主配置 48 个 ERT、独立状态路径启动检查通过；lsp-bridge 离线 Python 31 个、
ERT 25 个通过，Python 3.12/3.13 完整集成各 36 个 Python、9 个 ERT 通过；
另验证当前匹配模式、命令成功/失败返回及 Yasnippet nil/默认/自定义格式。
IntelliJ 核心 14 个、适配器 5 个 ERT 通过。GUI 加载修改后的显示源码后回放
45 次真实滚轮事件：`(:events 45 :jumps 0 :writes nil :first-jumps nil)`，随后恢复窗口。
