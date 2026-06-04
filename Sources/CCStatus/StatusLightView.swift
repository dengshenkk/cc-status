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
                // 立即捕获 session 信息，避免异步线程读取时数据不一致
                let session = sessions[i]
                let pid = Int32(session.pid)
                let sessionId = session.id
                DispatchQueue.global(qos: .userInitiated).async {
                    self.focusTerminal(pid: pid, sessionId: sessionId)
                }
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

    private func focusTerminal(pid: Int32, sessionId: String) {
        // 先尝试从当前进程获取 TTY
        var tty = ttyOfProcess(pid)

        // 如果当前进程没有 TTY，沿父进程链查找
        var currentPid = pid
        if tty == nil {
            for _ in 0..<8 {
                currentPid = parentPid(of: currentPid)
                guard currentPid > 0 else { break }
                tty = ttyOfProcess(currentPid)
                if tty != nil { break }
            }
        }

        if let tty = tty {
            print("[CCStatus] session=\(sessionId): 尝试按 TTY 聚焦终端，tty=\(tty)")
            if activateKnownTerminalByTTY(tty, sessionId: sessionId) {
                return
            }
        } else {
            print("[CCStatus] session=\(sessionId): 未找到 TTY，进入父进程 fallback")
        }

        // 重置 currentPid 用于查找终端应用，作为通用 fallback
        currentPid = pid
        for _ in 0..<8 {
            guard let app = NSRunningApplication(processIdentifier: currentPid) else {
                currentPid = parentPid(of: currentPid)
                guard currentPid > 0 else {
                    print("[CCStatus] session=\(sessionId): 未找到终端父进程")
                    return
                }
                continue
            }

            let bundleId = app.bundleIdentifier ?? ""
            let execName = (app.executableURL?.lastPathComponent ?? "").lowercased()

            let knownTerminals = [
                "com.googlecode.iterm2",
                "com.apple.Terminal",
                "com.apple.terminal",
                "net.kovidgoyal.kitty",
                "org.alacritty",
                "com.mitchellh.ghostty",
                "dev.warp.Warp-Stable", "dev.warp.Warp",
                "com.github.wez.wezterm",
                "co.zeit.hyper"
            ]
            let terminalKeywords = ["terminal", "iterm", "kitty", "alacritty", "ghostty", "warp", "wezterm", "hyper"]

            let isTerminal = knownTerminals.contains(bundleId) ||
                terminalKeywords.contains(where: { execName.contains($0) })

            if isTerminal {
                activateTerminalWindow(bundleId: bundleId, tty: tty, sessionId: sessionId)
                return
            }

            currentPid = parentPid(of: currentPid)
            guard currentPid > 0 else {
                print("[CCStatus] session=\(sessionId): 未找到终端父进程")
                return
            }
        }
        print("[CCStatus] session=\(sessionId): 查找终端失败，pid=\(pid)")
    }

    private func activateKnownTerminalByTTY(_ tty: String, sessionId: String) -> Bool {
        let ttyName = tty.replacingOccurrences(of: "/dev/", with: "")
        guard !ttyName.isEmpty else { return false }

        let runningBundleIds = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })

        if runningBundleIds.contains("com.googlecode.iterm2") {
            let script = """
            tell application "iTerm2"
                set found to false
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            try
                                if tty of s contains "\(ttyName)" then
                                    select s
                                    select t
                                    set index of w to 1
                                    set found to true
                                    exit repeat
                                end if
                            end try
                        end repeat
                        if found then exit repeat
                    end repeat
                    if found then exit repeat
                end repeat
                if found then activate
                return found
            end tell
            """
            if executeAppleScript(script, sessionId: sessionId) {
                return true
            }
        }

        if runningBundleIds.contains("com.apple.Terminal") || runningBundleIds.contains("com.apple.terminal") {
            let script = """
            tell application "Terminal"
                set found to false
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            if tty of t contains "\(ttyName)" then
                                set selected of t to true
                                set index of w to 1
                                set found to true
                                exit repeat
                            end if
                        end try
                    end repeat
                    if found then exit repeat
                end repeat
                if found then activate
                return found
            end tell
            """
            if executeAppleScript(script, sessionId: sessionId) {
                return true
            }
        }

        print("[CCStatus] session=\(sessionId): 未按 TTY 找到终端窗口，tty=\(tty)")
        return false
    }

    private func activateTerminalWindow(bundleId: String, tty: String?, sessionId: String) {
        let ttyName = tty?.replacingOccurrences(of: "/dev/", with: "") ?? ""

        let script: String
        if bundleId == "com.googlecode.iterm2" && !ttyName.isEmpty {
            script = """
            tell application "iTerm2"
                set found to false
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            try
                                if tty of s contains "\(ttyName)" then
                                    select s
                                    select t
                                    set index of w to 1
                                    set found to true
                                    exit repeat
                                end if
                            end try
                        end repeat
                        if found then exit repeat
                    end repeat
                    if found then exit repeat
                end repeat
                if found then activate
            end tell
            """
        } else if (bundleId == "com.apple.Terminal" || bundleId == "com.apple.terminal") && !ttyName.isEmpty {
            script = """
            tell application "Terminal"
                set found to false
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            if tty of t contains "\(ttyName)" then
                                set selected of t to true
                                set index of w to 1
                                set found to true
                                exit repeat
                            end if
                        end try
                    end repeat
                    if found then exit repeat
                end repeat
                if found then activate
            end tell
            """
        } else {
            guard !bundleId.isEmpty else {
                print("[CCStatus] session=\(sessionId): 终端进程缺少 bundleId，无法通用激活")
                return
            }
            script = """
            tell application id "\(bundleId)"
                activate
                try
                    set miniaturized of every window to false
                end try
            end tell
            """
        }

        DispatchQueue.main.async {
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if let err = error {
                    print("[CCStatus] session=\(sessionId): AppleScript 执行失败: \(err)")
                }
            }
        }
    }

    /// 同步执行 AppleScript 并返回布尔结果，用于判断是否成功找到并聚焦终端窗口
    private func executeAppleScript(_ source: String, sessionId: String) -> Bool {
        var result = false
        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.main.async {
            if let appleScript = NSAppleScript(source: source) {
                var error: NSDictionary?
                let output = appleScript.executeAndReturnError(&error)
                if let err = error {
                    print("[CCStatus] session=\(sessionId): AppleScript 执行失败: \(err)")
                } else {
                    result = output.booleanValue
                }
            }
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }

    private func ttyOfProcess(_ pid: Int32) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-p", String(pid)]
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
        } catch {}
        return nil
    }

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
