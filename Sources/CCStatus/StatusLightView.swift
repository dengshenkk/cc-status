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

            if isActive {
                ctx.setFillColor(activeColor.withAlphaComponent(0.3).cgColor)
                ctx.fillEllipse(in: rect.insetBy(dx: -3, dy: -3))
            }

            ctx.setFillColor((isActive ? activeColor : offColor).cgColor)
            ctx.fillEllipse(in: rect)
        }
    }

    // MARK: - Terminal focus

    /// 点击灯后拉起对应终端窗口。
    ///
    /// 实现原理：
    /// 1. 用 /bin/ps 找 session.pid 的父进程链，定位终端 app 的 pid
    /// 2. 用 NSRunningApplication(processIdentifier:) 拿到终端 app
    /// 3. 先 activate() 保证窗口一定出来
    /// 4. 对 iTerm2 / Terminal.app 再用 AppleScript 精确把 tty 对应的 tab 前置
    ///
    /// 关键：整个流程不依赖 lsof（在 Gatekeeper quarantine 下容易被阻断）。
    /// tty 通过 /bin/ps -o tty= 获取，ps 是系统工具，始终可用。
    private func focusTerminal(for session: SessionInfo) {
        let sessionPid = Int32(session.pid)
        let sessionId  = session.id

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // 步骤1：从 session pid 沿父进程链找到终端 app
            guard let (termApp, ttyShort) = self.findTerminalApp(startingFromPid: sessionPid) else {
                print("[CCStatus] \(sessionId): 未找到父终端进程，尝试 fallback")
                DispatchQueue.main.async { self.fallbackActivateAnyTerminal() }
                return
            }

            DispatchQueue.main.async {
                self.activateTerminal(termApp, ttyShort: ttyShort, sessionId: sessionId)
            }
        }
    }

    // MARK: - 父进程链查找

    private struct TerminalMatch {
        let app: NSRunningApplication
        let ttyShort: String? // e.g. "ttys003"，nil 表示拿不到
    }

    /// 沿父进程链（最多 15 级）找第一个已知终端 app。
    /// 同时顺路用 ps -o tty= 拿 session 进程自身的 tty（速度最快、最可靠）。
    private func findTerminalApp(startingFromPid pid: Int32) -> (NSRunningApplication, String?)? {
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
        let terminalExecKeywords = ["iterm", "terminal", "kitty", "alacritty", "ghostty", "warp", "wezterm", "hyper"]

        // 先拿 session 进程的 tty（用 ps -o tty=，返回 "ttys003" 这样的短名）
        let ttyShort = ttyShortOfPid(pid)

        var currentPid = pid
        for _ in 0..<15 {
            guard currentPid > 1 else { break }

            if let app = NSRunningApplication(processIdentifier: currentPid) {
                let bundleId  = app.bundleIdentifier ?? ""
                let execName  = (app.executableURL?.lastPathComponent ?? "").lowercased()
                let isTerminal = knownBundleIds.contains(bundleId)
                    || terminalExecKeywords.contains(where: { execName.contains($0) })
                if isTerminal {
                    return (app, ttyShort)
                }
            }

            currentPid = ppidOfPid(currentPid)
        }
        return nil
    }

    // MARK: - 激活终端

    private func activateTerminal(_ app: NSRunningApplication, ttyShort: String?, sessionId: String) {
        let bundleId = app.bundleIdentifier ?? ""

        // 先直接 activate：保证即使后续 AppleScript 失败，窗口也一定会出来
        app.activate(options: [.activateIgnoringOtherApps])

        guard let tty = ttyShort, !tty.isEmpty else {
            // 拿不到 tty 就只做 activate，已经够了
            return
        }

        // iTerm2：用 AppleScript 精确把对应 session 的 tab 前置
        if bundleId == "com.googlecode.iterm2" {
            let script = """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            try
                                if tty of s ends with "\(tty)" then
                                    select s
                                    select t
                                    set index of w to 1
                                    exit repeat
                                end if
                            end try
                        end repeat
                    end repeat
                end repeat
            end tell
            """
            runAppleScript(script, context: "iTerm2 \(sessionId)")
            return
        }

        // Terminal.app：用 AppleScript 把对应 tab 前置
        if bundleId == "com.apple.Terminal" {
            let script = """
            tell application "Terminal"
                repeat with w in windows
                    set tabList to tabs of w
                    repeat with t in tabList
                        try
                            if tty of t ends with "\(tty)" then
                                set selected of t to true
                                set index of w to 1
                                exit repeat
                            end if
                        end try
                    end repeat
                end repeat
            end tell
            """
            runAppleScript(script, context: "Terminal \(sessionId)")
            return
        }

        // 其他终端（Ghostty、Warp、kitty…）：activate 已经足够
    }

    /// 执行 AppleScript，打印错误但不崩溃
    private func runAppleScript(_ source: String, context: String) {
        guard let script = NSAppleScript(source: source) else { return }
        var errorDict: NSDictionary?
        script.executeAndReturnError(&errorDict)
        if let err = errorDict {
            print("[CCStatus] AppleScript[\(context)] error: \(err)")
        }
    }

    // MARK: - Fallback

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
            if let app = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleId).first {
                app.activate(options: [.activateIgnoringOtherApps])
                return
            }
        }
    }

    // MARK: - ps 工具函数

    /// 用 `ps -o tty= -p <pid>` 获取进程的 tty 短名（如 "ttys003"）。
    /// ps 是 macOS 内置系统工具，不受 Gatekeeper quarantine 影响。
    private func ttyShortOfPid(_ pid: Int32) -> String? {
        return runPs(args: ["-o", "tty=", "-p", String(pid)])
    }

    /// 用 `ps -o ppid= -p <pid>` 获取父进程 PID。
    private func ppidOfPid(_ pid: Int32) -> Int32 {
        guard let s = runPs(args: ["-o", "ppid=", "-p", String(pid)]) else { return 0 }
        return Int32(s) ?? 0
    }

    /// 运行 /bin/ps，返回 stdout 第一行（trim 后），失败返回 nil。
    private func runPs(args: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError  = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // ps 用 "??" 表示没有 tty
            return (out.isEmpty || out == "??") ? nil : out
        } catch {
            return nil
        }
    }

    deinit { blinkTimer?.invalidate() }
}
