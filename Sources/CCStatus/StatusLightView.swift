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

    /// 点击灯后拉起对应终端窗口。
    /// 策略：
    ///   1. 从 session.pid 沿父进程链找到终端 app（NSRunningApplication）
    ///   2. 找到后先用 NSRunningApplication.activate 直接激活（无需 AppleScript）
    ///   3. 若激活的是 iTerm2/Terminal.app，再补一次 AppleScript 把正确 tab 前置
    private func focusTerminal(for session: SessionInfo) {
        let pid = Int32(session.pid)
        DispatchQueue.global(qos: .userInitiated).async {
            // 沿父进程链找终端
            if let (termApp, tty) = self.findTerminalApp(startingFrom: pid) {
                DispatchQueue.main.async {
                    self.activateTerminalApp(termApp, tty: tty, sessionId: session.id)
                }
            } else {
                // fallback：pid 不在任何终端下时，尝试激活所有已知终端
                print("[CCStatus] session=\(session.id): 未找到终端父进程，尝试 fallback")
                DispatchQueue.main.async {
                    self.fallbackActivateAnyTerminal()
                }
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
                app.activate(options: [.activateIgnoringOtherApps])
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

    /// 激活终端 app，对 iTerm2/Terminal.app 额外尝试 AppleScript 精确定位 tab。
    private func activateTerminalApp(_ app: NSRunningApplication, tty: String?, sessionId: String) {
        let bundleId = app.bundleIdentifier ?? ""

        // 先直接 activate，保证窗口一定能拉起（即使后续 AppleScript 失败）
        // 注意：从 DMG 启动的 app 第一次调用时系统会弹出自动化权限请求
        app.activate(options: [.activateIgnoringOtherApps])

        // iTerm2：尝试用 AppleScript 把对应 session 的 tab 前置
        if bundleId == "com.googlecode.iterm2", let tty = tty {
            let ttyName = tty.replacingOccurrences(of: "/dev/", with: "")
            guard !ttyName.isEmpty else { return }
            let script = """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            try
                                if tty of s contains "\(ttyName)" then
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
            if let appleScript = NSAppleScript(source: script) {
                var err: NSDictionary?
                appleScript.executeAndReturnError(&err)
                if let err = err {
                    print("[CCStatus] session=\(sessionId): iTerm2 AppleScript err: \(err)")
                }
            }
            return
        }

        // Terminal.app：尝试 AppleScript 定位 tab
        if (bundleId == "com.apple.Terminal" || bundleId == "com.apple.terminal"), let tty = tty {
            let ttyName = tty.replacingOccurrences(of: "/dev/", with: "")
            guard !ttyName.isEmpty else { return }
            let script = """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            if tty of t contains "\(ttyName)" then
                                set selected of t to true
                                set index of w to 1
                                exit repeat
                            end if
                        end try
                    end repeat
                end repeat
            end tell
            """
            if let appleScript = NSAppleScript(source: script) {
                var err: NSDictionary?
                appleScript.executeAndReturnError(&err)
                if let err = err {
                    print("[CCStatus] session=\(sessionId): Terminal AppleScript err: \(err)")
                }
            }
        }
        // 其他终端（Ghostty, Warp, kitty…）：activate 已经够了
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
