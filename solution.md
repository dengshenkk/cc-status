# Solution

## 当前结论

项目中已经存在“点击浮动窗口中的状态灯，尝试拉起对应终端窗口并聚焦”的实现，核心代码位于：

- `Sources/CCStatus/StatusLightView.swift:72`：处理鼠标点击并判断命中的灯
- `Sources/CCStatus/StatusLightView.swift:132`：根据 Claude Code 会话 PID 查找终端应用
- `Sources/CCStatus/StatusLightView.swift:170`：通过 AppleScript 激活对应终端窗口或终端应用
- `Sources/CCStatus/StatusLightView.swift:237`：通过 `lsof` 获取进程 TTY
- `Sources/CCStatus/StatusLightView.swift:258`：通过 `ps` 获取父进程 PID

## 现有执行链路

1. 浮动窗口通过 `StatusLightWindow.updateSessions(_:)` 把会话列表传给 `StatusLightView`。
2. `StatusLightView.mouseDown(with:)` 根据点击位置匹配灯的中心点。
3. 命中某个灯后取 `sessions[i].pid`。
4. 后台线程调用 `focusTerminal(pid:)`。
5. `focusTerminal(pid:)` 获取该进程的 TTY，并沿父进程向上查找终端应用。
6. 找到终端后调用 `activateTerminalWindow(bundleId:tty:)`：
   - iTerm2 / Terminal.app：尝试按 TTY 精确选择窗口和标签页。
   - 其他终端：退化为激活对应应用。

## 待确认事项

当前需要确认用户目标是：

- 只验证现有实现是否能工作；还是
- 补强现有实现，例如增加失败日志、权限提示、更多终端兼容、无法精确匹配时的 fallback。
