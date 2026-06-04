# CC Status

macOS 菜单栏应用，实时监控 Claude Code 会话状态。每个 Claude Code 窗口对应一个独立指示灯。

## 功能

- **多会话独立监控**：每个 Claude Code 会话对应一个独立指示灯，灯数 = 当前活跃会话数
- **菜单栏状态**：聚合显示所有会话状态
- **浮动窗口**：始终置顶的半透明浮动面板，可拖拽
- **点击聚焦**：点击指示灯直接聚焦对应终端窗口
- **自动启动**：支持开机自启
- **方向切换**：支持垂直/水平布局

## 状态说明

| 会话状态 | 灯光颜色 | 菜单栏图标 |
|---------|---------|-----------|
| 执行中 (busy) | 🟢 绿色常亮 | 绿色圆点 |
| 空闲 (idle) | 🟡 黄色闪烁 | 黄灰交替 |
| 断开 (inactive) | 🔴 红色闪烁 | 红灰交替 |
| 无会话 | ⚫ 灰色 | 灰色圆点 |

菜单栏聚合逻辑：任一会话空闲 → 闪黄灯；全部执行中 → 绿灯；全部结束 → 灰灯。

## 安装

1. 下载 `CC-Status.dmg`
2. 挂载后拖拽 `CCStatus.app` 到 Applications
3. 首次打开需在系统设置 → 隐私与安全性 中允许

## 从源码构建

```bash
swiftc \
  Sources/CCStatus/main.swift \
  Sources/CCStatus/AppDelegate.swift \
  Sources/CCStatus/SessionMonitor.swift \
  Sources/CCStatus/StatusLightView.swift \
  Sources/CCStatus/StatusLightWindow.swift \
  Sources/CCStatus/MenuBarIcon.swift \
  -o cc-status \
  -framework AppKit \
  -framework Foundation \
  -framework ServiceManagement \
  -swift-version 5

./cc-status
```

## 系统要求

- macOS 12.0+
- Claude Code（需已安装，会话文件位于 `~/.claude/sessions/`）

## 进程检测说明

CC Status 通过两步验证确认 Claude Code 进程：
1. 检查可执行文件路径是否包含 `/claude`
2. 检查完整命令行是否包含 `claude-code` 或 `@anthropic-ai/claude-code`

兼容 npm/nvm/homebrew 等多种安装方式。
