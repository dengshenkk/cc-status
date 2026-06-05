import AppKit

class StatusLightView: NSView {
    private var sessions: [SessionInfo] = []
    private var blinkPhase: Bool = true
    private var blinkTimer: Timer?
    var isVertical: Bool = true {
        didSet { needsDisplay = true }
    }

    // Colors matching the spec:
    // Running: Green solid
    // Idle: Yellow flash
    // Done: Green flash
    // Interrupted: Red solid
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
    /// 策略：用纯 Accessibility API（只需辅助功能权限，不需自动化权限）
    private func focusTerminal(for session: SessionInfo) {
        let pid = Int32(session.pid)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
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

    /// 根据 TTY 精确聚焦终端窗口（纯 Accessibility API，不需要自动化权限）
    private func activateTerminal(tty: String?, fallbackPid: Int32, sessionId: String) {
        guard let tty = tty else {
            fallbackActivateAnyTerminal()
            return
        }

        let ttyName = tty.replacingOccurrences(of: "/dev/", with: "")
        guard !ttyName.isEmpty else {
            fallbackActivateAnyTerminal()
            return
        }

        // 尝试 iTerm2
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").first {
            if focusTerminalWindowAX(app: app, ttyName: ttyName) {
                return
            }
        }

        // 尝试 Terminal.app
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").first {
            if focusTerminalWindowAX(app: app, ttyName: ttyName) {
                return
            }
        }

        fallbackActivateAnyTerminal()
    }

    /// 用 Accessibility API 聚焦终端窗口
    private func focusTerminalWindowAX(app: NSRunningApplication, ttyName: String) -> Bool {
        let pid = app.processIdentifier
        let appRef = AXUIElementCreateApplication(pid)

        // 获取所有窗口
        var windowsRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)

        guard err == .success, let windows = windowsRef as? [AXUIElement] else {
            // 窗口可能最小化了，先激活 app
            app.activate()
            return false
        }

        // 遍历窗口，找目标并前置
        for window in windows {
            // 检查窗口或其子元素是否包含 tty
            if windowContainsTTY(window, ttyName: ttyName) {
                // 先激活 app
                app.activate()

                // 取消最小化
                var minimizedRef: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef)
                if let minimized = minimizedRef as? Bool, minimized {
                    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
                }

                // 前置窗口
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)

                // 设置为主窗口
                AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, true as CFTypeRef)
                AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, true as CFTypeRef)

                return true
            }
        }

        // 没找到匹配窗口，至少激活 app
        app.activate()
        return false
    }

    /// 检查窗口是否包含指定 tty（递归检查子元素）
    private func windowContainsTTY(_ element: AXUIElement, ttyName: String) -> Bool {
        // 获取 value
        var valueRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        if let value = valueRef as? String, value.contains(ttyName) {
            return true
        }

        // 获取 description
        var descRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef)
        if let desc = descRef as? String, desc.contains(ttyName) {
            return true
        }

        // 获取 title
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        if let title = titleRef as? String, title.contains(ttyName) {
            return true
        }

        // 递归检查子元素
        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        if let children = childrenRef as? [AXUIElement] {
            for child in children {
                if windowContainsTTY(child, ttyName: ttyName) {
                    return true
                }
            }
        }

        return false
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

    deinit { blinkTimer?.invalidate() }
}
