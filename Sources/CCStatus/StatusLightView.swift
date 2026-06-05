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
    /// 策略：
    /// 1. 用 ps -o tty= 拿到 session 进程的 tty（如 "ttys003"）
    /// 2. 在正在运行的 app 列表里找已知终端（不走父进程链，因为 iTermServer 不是 GUI app）
    /// 3. activate() 保证窗口出来
    /// 4. 对 iTerm2 / Terminal.app 用 AppleScript 按 tty 精确前置对应 tab
    private func focusTerminal(for session: SessionInfo) {
        let sessionPid = Int32(session.pid)
        let sessionId  = session.id

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // 拿 tty（ps 是内核工具，不受 quarantine 影响）
            let tty = self.ttyShortOfPid(sessionPid)
            print("[CCStatus] \(sessionId): pid=\(sessionPid) tty=\(tty ?? "nil")")

            // 在运行中的 app 列表找终端（不依赖父进程链）
            let termApp = self.findRunningTerminalApp()
            print("[CCStatus] \(sessionId): termApp=\(termApp?.bundleIdentifier ?? "nil")")

            DispatchQueue.main.async {
                if let app = termApp {
                    self.activateTerminal(app, ttyShort: tty, sessionId: sessionId)
                } else {
                    print("[CCStatus] \(sessionId): 没有运行中的终端 app")
                }
            }
        }
    }

    // MARK: - 查找运行中的终端 app

    /// 按优先级在运行中的 app 列表查找终端，不依赖父进程链。
    /// iTermServer 等后台服务进程不是 NSRunningApplication，但 iTerm2 主进程是。
    private func findRunningTerminalApp() -> NSRunningApplication? {
        let orderedBundleIds = [
            "com.googlecode.iterm2",
            "com.apple.Terminal",
            "com.mitchellh.ghostty",
            "dev.warp.Warp-Stable",
            "dev.warp.Warp",
            "net.kovidgoyal.kitty",
            "org.alacritty",
            "com.github.wez.wezterm",
            "co.zeit.hyper",
        ]
        for bundleId in orderedBundleIds {
            if let app = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleId).first {
                return app
            }
        }
        return nil
    }

    // MARK: - 激活终端

    private func activateTerminal(_ app: NSRunningApplication, ttyShort: String?, sessionId: String) {
        let bundleId = app.bundleIdentifier ?? ""

        // 先 activate 保底：即使 AppleScript 失败窗口也会出来
        app.activate(options: [.activateIgnoringOtherApps])

        guard let tty = ttyShort, !tty.isEmpty else {
            print("[CCStatus] \(sessionId): 无 tty，仅做 activate")
            return
        }

        // iTerm2：AppleScript 精确把对应 session 的 tab 前置
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

        // Terminal.app：AppleScript 把对应 tab 前置
        if bundleId == "com.apple.Terminal" {
            let script = """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
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

    private func runAppleScript(_ source: String, context: String) {
        guard let script = NSAppleScript(source: source) else { return }
        var errorDict: NSDictionary?
        script.executeAndReturnError(&errorDict)
        if let err = errorDict {
            print("[CCStatus] AppleScript[\(context)] error: \(err)")
        }
    }

    // MARK: - ps 工具函数

    private func ttyShortOfPid(_ pid: Int32) -> String? {
        return runPs(args: ["-o", "tty=", "-p", String(pid)])
    }

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
            return (out.isEmpty || out == "??") ? nil : out
        } catch {
            return nil
        }
    }

    deinit { blinkTimer?.invalidate() }
}
