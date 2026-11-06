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

- `git-islands-ui.el` 的 obsolete aliases 是对外迁移兼容层，内部已经调用
  tool-islands；本轮保留，后续应在明确的破坏性版本中统一移除并写迁移说明。
- 中文分词的 Lisp 客户端仍按进程输出块解析结果；如进一步改造，宜采用按行缓冲
  和明确的请求完成状态，并覆盖拆包、合包及进程退出场景。
- Rime 维护包仍在初始化时读取词库。下一步可将路径与词库状态封装成显式创建的
  对象，使纯逻辑测试不需要整套词库；本轮通过 RIME_DIR 先消除固定个人目录依赖。

tool-islands 的运行时代码变更在本轮开始时已存在，本轮没有将其作为新实现覆盖。
