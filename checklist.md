# Checklist

- [x] 确认当前工作目录
- [x] 检查流程文件是否存在
- [x] 探索项目文档和关键 Swift 源码
- [x] 初始化 git 仓库并提交基线版本
- [x] 用户确认采用方案 A：补强现有点击聚焦实现
- [x] 实施方案 A 的代码改动
- [x] 编译验证
- [x] 提交修改到 git
- [x] 用户反馈点击后没有拉起窗口
- [x] 分析根因：iTerm2 父进程链是 iTermServer，NSRunningApplication 找不到终端 App
- [x] 实现按 TTY 直接聚焦 iTerm2/Terminal 的路径
- [x] 用户验证修复效果 - 可用
- [x] 提交修复到 git
- [x] 创建 GitHub Actions CI/CD workflow
- [x] 推送到 GitHub

## 任务2（2026-06-05）：点击灯精确聚焦终端窗口（方案A）

- [x] 分析当前代码，定位不精确根因（窗口前置错误 / 无取消最小化 / 时序错误）
- [x] 确认环境：iTerm2(3 窗口) + Terminal.app，验证 iTerm2 AppleScript 可枚举 tty
- [x] 用户确认方案 A + iTerm2 最小化折中
- [x] 重写 focusTerminal：直接读 tty（绕过 iTermServer 父进程链坑）
- [x] 实现 iTerm2 精确聚焦脚本（tty 匹配 + miniaturized + System Events AXRaise/AXMain/AXFocused）
- [x] 实现 Terminal.app 精确聚焦脚本（tty 匹配 + miniaturized + frontmost + AXRaise）
- [x] 修复"最小化恢复后被覆盖"：加 AXMain + AXFocused 锁定主窗口
- [x] 修复"拉起所有最小化窗口"回归：移除 iTerm2 activate，改用 System Events frontmost
- [x] 编译验证
- [x] 运行 + 手动测试聚焦精确性（多窗口 + 最小化）- 用户验证通过
- [x] 更新 solution.md
- [x] 提交到 git（commit 5931b3d）
- [x] 发布新版本 v1.2.0（tag 推送，触发 CI/CD）
