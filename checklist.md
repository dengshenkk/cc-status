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
- [ ] 用户验证修复效果
- [ ] 提交修复到 git
