# Solution

## 执行结果

| 项目 | 值 |
|------|-----|
| 基线提交 | `4267e5b` - Initial cc status baseline |
| 方案A提交 | `a75472e` - Improve terminal focus on light click |
| 修复提交 | `0dfc479` - Fix terminal focus: prioritize TTY-based activation |
| CI/CD提交 | `d0dd45b` - Add GitHub Actions release workflow |
| GitHub仓库 | https://github.com/dengshenkk/cc-status |

## 修复内容

**问题根因**：iTerm2 场景下，Claude Code 的父进程链是 `iTermServer`，不是 iTerm2 GUI 主应用，导致 `NSRunningApplication(processIdentifier:)` 返回 `nil`，AppleScript 聚焦逻辑未执行。

**修复方案**：
1. 新增 `activateKnownTerminalByTTY(_:_:)` - 按 TTY 直接执行 iTerm2/Terminal AppleScript
2. 新增 `executeAppleScript(_:_:)` - 同步执行 AppleScript 并返回布尔结果
3. 修正 Terminal.app 的 bundle id 大小写兼容
4. 在 `focusTerminal` 中获取 TTY 后优先调用 TTY 直接聚焦路径，失败后再走父进程 fallback

## GitHub CI/CD 使用方式

```bash
# 创建并推送标签触发自动发布
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions 会自动：
1. 在 macOS runner 上编译
2. 打包 CCStatus.app
3. 创建 CC-Status.dmg
4. 发布 GitHub Release
