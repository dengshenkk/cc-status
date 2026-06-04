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

## 执行结果

- 基线提交：`4267e5b` - `Initial cc status baseline`
- 修改提交：`a75472e` - `Improve terminal focus on light click: capture session early, better TTY lookup, add failure logs`

## 方案 A 改动内容

1. `mouseDown` 立即捕获 `session` 的 `pid` 和 `sessionId`，避免异步线程读取 `sessions` 数组时数据不一致。
2. `focusTerminal` 增加 `sessionId` 参数用于日志；先从当前进程获取 TTY，如果失败再沿父进程链查找；查找失败时打印日志。
3. `activateTerminalWindow` 增加 `sessionId` 参数；AppleScript 执行失败时打印错误详情。
