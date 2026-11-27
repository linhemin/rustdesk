# RustDesk 产品与 UI 完整 TODO 清单

> 面向桌面端（Windows / macOS / Linux）与移动端（iOS / Android）的产品级完善路线图，涵盖交互重构收口、移动端远控体验精修、账号与设备同步、跨端一致性以及核心能力产品化。

---

## P0 · 移动端远控操作体验精修（当前优先）

### 1. 移动端鼠标移动与画面联动细节优化
- [x] **消除指针模式中线晃屏**：重构 `CursorModel.updatePan`（`flutter/lib/models/model.dart`），将“过画面中线即强行拖动画面”改为**视口内部自由移动 + 边缘缓冲带平滑跟随**；画面已锁定（`canvas.locked`）或完整适配时禁止鼠标移动触发画面偏移；画面滚到边界后剩余位移继续平滑推动光标直达最边缘像素。
- [x] **修复 iOS 虚拟鼠标移动即乱拉画面的问题**：修正 `AwesunSessionView.swift` / `AwesunSessionOverlay.swift` 中 `hubVelocity` 只要离开 31pt 中心圈就反向猛拉画面的逻辑，改为**指针到达屏幕边缘推拉区才按推力比例平滑移动画面**（渐进加速、回拉即停，取代突兀的 600pt/s 阶跃跳速）。
- [x] **补齐 Android 虚拟鼠标边缘平滑拖屏**：让 `AwesunFlutterOverlay` 在拖动中心圆盘或左键拖选触达视口边缘时，通过统一的纯函数数学模型（`flutter/lib/mobile/session_viewport.dart`）平滑推动放大后的远端画面，与 iOS 手感完全一致。
- [x] **补齐单元与交互测试**：覆盖自由移动区不晃屏、边缘区平滑滚屏、锁屏禁止滚屏、滚到尽头光标继续到达最边缘、以及回拉立即停滚等边界用例。

### 2. 默认显示自己的鼠标，远程鼠标默认关闭且提供开关
- [x] **默认开启本地（自己的）鼠标**：
  - iOS `AwesunSessionModel` 首次进入会话默认 `mouseVisible = true`、`mouseCollapsed = false`（同时记忆用户主动关闭后的偏好）。
  - Android `AwesunFlutterOverlay` 默认显示本地虚拟鼠标，并同步支持独立的**显示本地鼠标**开关；当指针模式下虚拟鼠标收起/隐藏时，仍显示轻量本地指针箭头，不迷失光标位置。
- [x] **默认隐藏远程鼠标，改为独立开关**：
  - 修复 `flutter/lib/mobile/pages/remote_page.dart` 中 `CursorPaint` 忽略 `ShowRemoteCursorState` 的问题：在会话初始化时同步读取 `show-remote-cursor`（后端默认关闭），移动端仅在用户打开“显示远程鼠标”开关（或仅观看模式）时才绘制远程鼠标，且开启后与本地鼠标互不冲突。
  - 在移动端（iOS + Android）远控面板中提供直观的双开关：**显示本地鼠标**（默认开）与 **显示远程鼠标**（默认关），并实时同步到远端 `show-remote-cursor` 选项。

### 3. 移动端远控菜单重组（解决“更多”里一团乱麻）
- [x] **一级“远程操作”抽屉重构**：
  - **会话快捷网格**：将高频操作 `最小化`、`声音`、`截图`、`聊天/语音`、`切换屏幕`、`更多工具`、`断开` 清晰排布在一级区域。
  - **操控与鼠标区块**：`指针模式 / 触控模式` 切换 + `手势指南`、`显示本地鼠标`、`显示远程鼠标`、`锁定画面` 开关一目了然。
  - **键盘与显示区块**：`系统键盘`、`虚拟键盘`、`显示与画质`、`连接质量`。
- [x] **二级“更多工具”分组抽屉（双端统一深色毛玻璃）**：
  - 取代 Android 原先简陋的 `showMenu` 气泡列表，与 iOS `AwesunActionPanel` 统一为按场景分组的清晰结构：
    1. **显示与光标**：重置画面缩放、刷新画面、光标居中
    2. **远端控制与安全**：以按键发送剪贴板、系统密码（带快捷编辑入口）、发送 Ctrl+Alt+Del、锁定远端屏幕、阻止对方输入、请求管理员权限、交换控制方、（被控 Android 导航/音量键）
    3. **电源与高危操作**（红色/警告色隔离防误触）：重启远程设备
    4. **连接诊断（默认折叠收起）**：UDP 诊断、复制 P2P 诊断、音频诊断、远程 P2P 测试

---

## P1 · 跨端一致性收口 & 高性价比体验修复

### 4. 补齐 Android & Linux 的新设计系统一致化
- [x] **Android 首页与设备卡片**：在 `peer_card.dart` 与 `mobile/pages/home_page.dart` 为 Android 启用新版 `DeviceCard` 与首页右上角扫码按钮。
- [x] **Android 设置页对齐 iOS**：在 `mobile/pages/settings_page.dart` 为 Android 开启设置搜索栏与顶部账号卡片。
- [x] **Linux 桌面端对齐 Windows/macOS**：放开 `desktop_setting_page.dart` 的 `_expandedDesktopSettings`、`file_manager_page.dart` 的 `FileTransferWorkspace` 以及 `peer_card.dart` 的新版 `DeviceCard` 平台限制。
- [x] **桌面被控连接管理窗口（CM）重设计**：将 `desktop/pages/server_page.dart` 权限面板、状态头与虚拟麦路由徽标升级到 Obsidian/Porcelain 体系。

### 5. 修复关键交互断点
- [x] **桌面设置页全局搜具体设置项**：升级 `desktop_setting_page.dart` 的搜索，从“仅搜左侧分类名”改为支持按中文/英文关键词搜索全部具体配置项并匹配对应分类。
- [x] **移动端后台活动会话条升级**：
  - `_ActiveMobileSessions` 优先显示设备主机名而非纯数字 ID；
  - 支持在会话标签上直接点 `×` 断开挂起会话，无需点进去再断开；
  - [x] 在 `mobile/pages/home_page.dart` 非连接 Tab 顶部提供轻量常驻活动会话横幅（支持一键返回或关闭），避免遗忘后台连接。
- [x] **iOS 文件页支持从设备列表选目标**：在 `ios_files_page.dart` 的连接表单中列出最近/收藏设备一键选择，不必每次手输 ID。

### 6. 账号与设备清单同步 / 备份能力（重点需求）
- [x] **无自建 API 账号场景的本地设备清单导出与恢复（不含密码）**：
  - 已在桌面端“账号”设置与移动端设置中上线**本地设备清单剪贴板 / JSON 文件导出导入**（`flutter/lib/common/local_peer_backup.dart`），默认自动过滤密码/Hash 保障安全；
  - [x] 支持 WebDAV 跨设备推送/拉取同步（`WebDavSyncConfig` + `pushLocalPeersToWebDav`/`pullLocalPeersFromWebDav` + 上次同步时间记录）。
- [x] **统一账号中心体验（桌面 + 移动）**：
  - 通过 `AccountSyncCard`（桌面）与 `AppleSettingsAccountCard`（双移动）明确区分“本机模式（Local）”与“云账号模式（Account）”的状态徽标、最近同步时间与一键导出/导入/WebDAV 同步入口。

---

## P2 · 王牌能力产品化与高频效率升级

### 7. 手机麦克风 / 独立音频模式产品化
- [x] **提升入口可发现性**：在移动端设备卡片与“更多”菜单中提供统一的“音频模式”入口。
- [x] **重做音频控制页（`phone_microphone_page.dart`）**：采用 `WorkspacePanel` 卡片，加入实时 5 柱麦克风电平动效、醒目圆形一键静音/开麦大按钮、实时通话计时器、分组开关与危险色断开按钮，开发者诊断收进右上角菜单。
- [x] **桌面被控端驱动与状态闭环**：在 `desktop_setting_page.dart` 音频设置与 `server_page.dart` 被控弹窗中展示虚拟麦克风驱动（VB-Cable / CABLE Output）就绪状态与当前路由徽标。

### 8. 多中继管理与连接诊断可视化
- [x] **多中继节点一键测速**：在 `relay_servers.dart` 顶栏新增 `Test` 一键并发测速按钮，为每个中继节点展示实时延迟徽标（ms / 超时错误）。
- [x] **桌面 → 手机一键二维码同步全套配置**：在桌面网络设置页通过 `showServerConfigQrDialog` 生成包含 ID 服务器 + 多中继列表 + 公钥的 `config=...` 二维码，手机端扫码直接展开并应用。
- [x] **连接失败“人话诊断”**：提供 `showNetworkDiagnosticsDialog` 网络体检弹窗（并发探测 ID 服务器、中继列表与直连模式配置），并挂入桌面/移动网络设置及 `msgBox` 的 `Connection Error` 错误弹窗。

### 9. 桌面主工作台与远控会话增强
- [x] **真正的“活动会话”总览视图**：桌面工作台“远程会话”页展示当前活跃远控会话卡片条（含一键切窗与刷新）。
- [x] **全局快捷命令面板（`Cmd/Ctrl + K`）**：新增 `desktop/widgets/command_palette.dart` 并在 `desktop_home_page.dart` 绑定 `Cmd/Ctrl + K` 快捷键，支持键盘导航瞬时搜设备（连接/文件/终端）与系统工具。
- [x] **桌面工具栏实时微状态胶囊**：在 `remote_toolbar.dart` 顶部及折叠态状态胶囊增加实时 FPS 与隐私屏提示；录屏按钮增加实时计时（`REC 00:12`）。

### 10. 文件传输体验升级
- [x] **补齐桌面拖放遮罩（`file_manager_page.dart` TODO）**：本地与远端分栏独立实现拖入高亮遮罩与目标方向提示。
- [x] **队列控制与反馈增强**：Linux 对齐新版队列卡片；进度条旁显示实时速度与预计剩余时间（ETA）、失败任务一键重试按钮，下载完成支持一键“打开文件夹”。
- [x] **目录导航与移动端增强**：桌面文件视图新增常用目录书签（Desktop / Downloads / Documents）；手机端 `mobile/pages/file_manager_page.dart` 支持直接从系统相册多选照片/视频发送，以及本地文件一键预览打开。

---

## P3 · 差异化产品壁垒与安全透明度

- [x] **设备级连接预设（Per-device Profile）**：新增 `common/device_profile.dart` 并接入设备卡片“更多”菜单，支持为每台设备独立配置默认连接模式、画质、隐私屏、音频与强制中继策略。
- [x] **首次上手轻引导与权限体检清单**：在 `AwesunFlutterOverlay` 中新增可跳过的 3 步环形鼠标首次引导条（持久化记忆）；在桌面 `desktop_home_page.dart`“本机被控”页新增主机就绪度体检卡片（服务/密码/权限）。
- [x] **本机来访历史记录 & 一键勿扰暂停被控**：新增 `common/incoming_history.dart`，在 `server_page.dart` 自动记录来访会话，在 `desktop_home_page.dart`“本机被控”页展示最近来访记录（支持清空）及一键暂停被控（支持 1 小时自动恢复）。
- [x] **白板标注 / 激光笔**：新增 `desktop/widgets/session_whiteboard.dart`（支持多色画笔、自动淡出激光笔、清空/关闭），并接入桌面 `RemoteToolbar` 与 `RemotePage`。
- [x] **移动端自定义常用快捷键宏栏**：新增 `mobile/widgets/macro_shortcut_bar.dart` 并集成至 `SessionKeyboard` 快捷键页，支持自定义置顶常用组合键（`Ctrl+C/V/Z`、`Alt+Tab`、`Win+D`、`Cmd+Space`、`TaskMgr`、`Win+L`）。
- [x] **品牌收口**：新增 `common/brand_links.dart` 集中管理官网/定价/下载/隐私外链（支持自定义客户端 buildin 覆盖），替换桌面与移动端分散的硬编码 `rustdesk.com/*` 链接。
