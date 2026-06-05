import AppKit

class StatusLightView: NSView {
    private var sessions: [SessionInfo] = []
    private var blinkPhase: Bool = true
    private var blinkTimer: Timer?
    var isVertical: Bool = true {
        didSet { needsDisplay = true }
    }

    private let greenColor  = NSColor(red: 0.2,  green: 0.85, blue: 0.3,  alpha: 1.0)
    private let yellowColor = NSColor(red: 1.0,  green: 0.80, blue: 0.0,  alpha: 1.0)
    private let redColor    = NSColor(red: 0.95, green: 0.2,  blue: 0.15, alpha: 1.0)
    private let offColor    = NSColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1.0)

    let circleSize: CGFloat = 28
    let spacing: CGFloat    = 6
    let padding: CGFloat    = 8

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.92).cgColor
        startBlinkTimer()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func startBlinkTimer() {
        blinkTimer = Timer(timeInterval: 0.5, target: self,
                           selector: #selector(toggleBlink), userInfo: nil, repeats: true)
        RunLoop.main.add(blinkTimer!, forMode: .common)
    }

    @objc private func toggleBlink() {
        blinkPhase.toggle()
        needsDisplay = true
    }

    func updateSessions(_ sessions: [SessionInfo]) {
        let changed = sessions.count != self.sessions.count ||
            !zip(sessions, self.sessions).allSatisfy { $0.status == $1.status && $0.id == $1.id }
        if changed {
            self.sessions = sessions
            needsDisplay = true
        }
    }

    // MARK: - Light layout

    func lightCenters() -> [CGPoint] {
        let w = bounds.width
        let h = bounds.height
        let count = sessions.count
        guard count > 0 else { return [] }

        let availableLength = isVertical ? h : w
        let totalContentLength = CGFloat(count) * circleSize + CGFloat(count - 1) * spacing
        let startOffset = (availableLength - totalContentLength) / 2.0 + circleSize / 2.0

        return sessions.indices.map { i in
            let offset = startOffset + CGFloat(i) * (circleSize + spacing)
            return isVertical
                ? CGPoint(x: w / 2, y: h - offset)
                : CGPoint(x: offset, y: h / 2)
        }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let centers = lightCenters()
        let hitRadius = circleSize / 2.0 + 4

        for (i, center) in centers.enumerated() {
            let dx = point.x - center.x
            let dy = point.y - center.y
            if dx * dx + dy * dy <= hitRadius * hitRadius {
                let session = sessions[i]
                focusTerminal(for: session)
                return
            }
        }
        super.mouseDown(with: event)
    }

    // MARK: - Draw

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let centers = lightCenters()
        guard !centers.isEmpty else { return }

        for (i, session) in sessions.enumerated() {
            let center = centers[i]
            let activeColor: NSColor
            let isActive: Bool

            switch session.status {
            case .busy:
                activeColor = greenColor
                isActive = true
            case .idle:
                activeColor = yellowColor
                isActive = blinkPhase
            case .inactive, .noSession:
                activeColor = redColor
                isActive = blinkPhase
            }

            let rect = CGRect(x: center.x - circleSize / 2, y: center.y - circleSize / 2,
                              width: circleSize, height: circleSize)

            // Glow
            if isActive {
                ctx.setFillColor(activeColor.withAlphaComponent(0.3).cgColor)
                ctx.fillEllipse(in: rect.insetBy(dx: -3, dy: -3))
            }

            ctx.setFillColor((isActive ? activeColor : offColor).cgColor)
            ctx.fillEllipse(in: rect)
        }
    }

    // MARK: - Terminal focus

    /// 点击灯后精确拉起对应终端窗口。
    /// 策略（修复 iTerm2 用 iTermServer 托管 shell、GUI 进程不在父进程链上导致定位失败的问题）：
    ///   1. 直接读取 claude 进程的 TTY（不依赖父进程链找 GUI app）
    ///   2. 对运行中的已知终端（iTerm2 / Terminal.app）逐个跑 AppleScript 按 TTY 匹配，
    ///      命中后：取消最小化 → 选中 session/tab → 前置窗口 → activate
    ///   3. 都没命中再退化到父进程链 / 任意终端激活
    private func focusTerminal(for session: SessionInfo) {
        let pid = Int32(session.pid)
        DispatchQueue.global(qos: .userInitiated).async {
            let tty = self.ttyOfProcess(pid)
            DispatchQueue.main.async {
                self.activateTerminal(tty: tty, fallbackPid: pid, sessionId: session.id)
            }
        }
    }

    /// 找不到父终端时，激活当前运行中的任意终端 app（最后手段）
    private func fallbackActivateAnyTerminal() {
        let knownBundleIds = [
            "com.googlecode.iterm2",
            "com.apple.Terminal",
            "net.kovidgoyal.kitty",
            "org.alacritty",
            "com.mitchellh.ghostty",
            "dev.warp.Warp-Stable",
            "dev.warp.Warp",
            "com.github.wez.wezterm",
            "co.zeit.hyper",
        ]
        for bundleId in knownBundleIds {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
                app.activate()
                return
            }
        }
    }

    /// 从给定 pid 出发沿父进程链，找到第一个已知终端 NSRunningApplication。
    /// 同时尽量顺路读取 TTY（用于 iTerm2 精确 tab 定位）。
    private func findTerminalApp(startingFrom pid: Int32) -> (NSRunningApplication, String?)? {
        let knownBundleIds: Set<String> = [
            "com.googlecode.iterm2",
            "com.apple.Terminal",
            "net.kovidgoyal.kitty",
            "org.alacritty",
            "com.mitchellh.ghostty",
            "dev.warp.Warp-Stable",
            "dev.warp.Warp",
            "com.github.wez.wezterm",
            "co.zeit.hyper",
        ]
        let terminalKeywords = ["terminal", "iterm", "kitty", "alacritty", "ghostty", "warp", "wezterm", "hyper"]

        var currentPid = pid
        var tty: String? = nil

        for _ in 0..<12 {
            guard currentPid > 0 else { break }

            // 顺路收集 TTY（不中断流程）
            if tty == nil, let t = ttyOfProcess(currentPid) {
                tty = t
            }

            if let app = NSRunningApplication(processIdentifier: currentPid) {
                let bundleId = app.bundleIdentifier ?? ""
                let execName = (app.executableURL?.lastPathComponent ?? "").lowercased()
                let isTerminal = knownBundleIds.contains(bundleId) ||
                    terminalKeywords.contains(where: { execName.contains($0) })
                if isTerminal {
                    return (app, tty)
                }
            }

            currentPid = parentPid(of: currentPid)
        }
        return nil
    }

    /// 根据 TTY 精确聚焦终端窗口，失败则逐级降级。
    private func activateTerminal(tty: String?, fallbackPid: Int32, sessionId: String) {
        // 1. 有 TTY：对运行中的已知终端按 TTY 精确匹配聚焦
        if let tty = tty {
            let ttyName = tty.replacingOccurrences(of: "/dev/", with: "")
            if !ttyName.isEmpty {
                if isAppRunning("com.googlecode.iterm2"),
                   focusITerm2(ttyName: ttyName, sessionId: sessionId) {
                    return
                }
                if isAppRunning("com.apple.Terminal"),
                   focusTerminalApp(ttyName: ttyName, sessionId: sessionId) {
                    return
                }
            }
        }

        // 2. 降级：沿父进程链找 GUI 终端（覆盖 Ghostty/Warp/kitty 等非 server 架构终端）
        if let (app, _) = findTerminalApp(startingFrom: fallbackPid) {
            app.activate()
            return
        }

        // 3. 兜底：激活任意已知终端
        print("[CCStatus] session=\(sessionId): TTY/父进程均未命中，fallback 激活任意终端")
        fallbackActivateAnyTerminal()
    }

    /// iTerm2：按 TTY 匹配 session → 取消最小化 → 记录 bounds，
    /// 再用 System Events 按 position 匹配执行：AXRaise + AXMain + AXFocused + frontmost。
    /// 注意：不能用 iTerm2 的 activate（会恢复所有最小化窗口），必须用 System Events 精确激活。
    /// 返回是否命中目标 session。
    private func focusITerm2(ttyName: String, sessionId: String) -> Bool {
        let script = """
        tell application "iTerm2"
            set matched to false
            set tx to -99999
            set ty to -99999
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        try
                            if tty of s contains "\(ttyName)" then
                                set miniaturized of w to false
                                select s
                                set b to bounds of w
                                set tx to (item 1 of b)
                                set ty to (item 2 of b)
                                set matched to true
                            end if
                        end try
                    end repeat
                end repeat
            end repeat
        end tell
        if matched then
            delay 0.3
            tell application "System Events"
                if exists (process "iTerm2") then
                    tell process "iTerm2"
                        set frontmost to true
                        repeat with win in windows
                            try
                                set p to position of win
                                if (item 1 of p) = tx and (item 2 of p) = ty then
                                    perform action "AXRaise" of win
                                    try
                                        set value of attribute "AXMain" of win to true
                                    end try
                                    try
                                        set value of attribute "AXFocused" of win to true
                                    end try
                                end if
                            end try
                        end repeat
                    end tell
                end if
            end tell
        end if
        return matched
        """
        return runAppleScriptReturningBool(script, label: "iTerm2", sessionId: sessionId)
    }

    /// Terminal.app：按 TTY 匹配 tab → 取消最小化 → 选中 tab → 前置 → activate，
    /// 再用 System Events 的 AXRaise（按窗口左上角坐标匹配）强制前置兜底。
    /// 返回是否命中目标 tab。
    private func focusTerminalApp(ttyName: String, sessionId: String) -> Bool {
        let script = """
        tell application "Terminal"
            set matched to false
            set tx to -99999
            set ty to -99999
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        if tty of t contains "\(ttyName)" then
                            set miniaturized of w to false
                            set selected of t to true
                            set frontmost of w to true
                            set b to bounds of w
                            set tx to (item 1 of b)
                            set ty to (item 2 of b)
                            set matched to true
                        end if
                    end try
                end repeat
            end repeat
            if matched then activate
        end tell
        if matched then
            delay 0.3
            tell application "System Events"
                if exists (process "Terminal") then
                    tell process "Terminal"
                        set frontmost to true
                        repeat with win in windows
                            try
                                set p to position of win
                                if (item 1 of p) = tx and (item 2 of p) = ty then
                                    perform action "AXRaise" of win
                                    try
                                        set value of attribute "AXMain" of win to true
                                    end try
                                    try
                                        set value of attribute "AXFocused" of win to true
                                    end try
                                end if
                            end try
                        end repeat
                    end tell
                end if
            end tell
        end if
        return matched
        """
        return runAppleScriptReturningBool(script, label: "Terminal", sessionId: sessionId)
    }

    /// 判断指定 bundleId 的 app 是否在运行
    private func isAppRunning(_ bundleId: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
    }

    /// 执行 AppleScript 并返回其布尔结果（脚本出错或非布尔返回时为 false）
    private func runAppleScriptReturningBool(_ source: String, label: String, sessionId: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var err: NSDictionary?
        let result = script.executeAndReturnError(&err)
        if let err = err {
            print("[CCStatus] session=\(sessionId): \(label) AppleScript err: \(err)")
            return false
        }
        return result.booleanValue
    }

    // MARK: - System helpers

    /// 通过 lsof 找进程持有的 TTY 设备路径
    private func ttyOfProcess(_ pid: Int32) -> String? {
        // 使用绝对路径，防止 PATH 在某些运行环境下不完整
        let lsofPath = "/usr/sbin/lsof"
        guard FileManager.default.fileExists(atPath: lsofPath) else { return nil }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: lsofPath)
        task.arguments = ["-p", String(pid), "-a", "-d", "0,1,2"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            for line in output.components(separatedBy: "\n") {
                if line.contains("/dev/ttys") {
                    if let last = line.split(separator: " ").last { return String(last) }
                }
            }
        } catch {
            print("[CCStatus] lsof error for pid \(pid): \(error)")
        }
        return nil
    }

    /// 通过 ps 获取父进程 PID
    private func parentPid(of pid: Int32) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-o", "ppid=", "-p", String(pid)]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return Int32(String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "0") ?? 0
        } catch { return 0 }
    }

    deinit { blinkTimer?.invalidate() }
}
