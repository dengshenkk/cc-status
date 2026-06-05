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

---

## 任务2（2026-06-05）：点击灯精确聚焦终端窗口

### 问题
点击状态灯能激活终端窗口，但不精确：
1. 多窗口时聚焦随机/错乱
2. 窗口最小化时拉不起来
3. 拉起后被其他窗口覆盖

### 根因分析
1. **入口级坑**：iTerm2 用 iTermServer 托管 shell，GUI 进程不在父进程链上 → `findTerminalApp` 找不到终端 app
2. **前置错误**：iTerm2 的 `select w`/`set index`/`frontmost` 无法可靠 raise 窗口
3. **最小化恢复后不前置**：`AXRaise` 只提升层级，没设 `AXMain`/`AXFocused` 锁定主窗口
4. **拉起所有最小化窗口**：iTerm2 的 `activate` 会恢复所有最小化窗口

### 最终方案
**纯 AppleScript + System Events 精确聚焦**：
1. 直接读取 claude 进程的 TTY（绕过父进程链）
2. iTerm2：tty 匹配 → `set miniaturized false` → System Events `AXRaise + AXMain + AXFocused + frontmost`
3. Terminal.app：tty 匹配 → `set miniaturized false` + `frontmost true` + System Events `AXRaise`
4. **不用 iTerm2 的 `activate`**（会恢复所有最小化窗口），改用 System Events 精确激活

### 验证结果
✅ 多窗口切换精确
✅ 最小化恢复单个窗口（不拉起其他）
✅ 恢复后稳定前置（不被覆盖）
✅ 后台遮挡窗口能 raise 到最前
