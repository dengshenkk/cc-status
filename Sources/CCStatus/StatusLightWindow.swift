import AppKit

class StatusLightWindow: NSWindow {
    private(set) var lightView: StatusLightView!
    private var currentSessions: [SessionInfo] = []
    var isVertical: Bool = true {
        didSet {
            lightView.isVertical = isVertical
            resizeForSessions(currentSessions)
        }
    }

    private let fixedCrossAxis: CGFloat = 60  // 垂直时宽度 / 水平时高度

    init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.visibleFrame
        // 初始为 0 个 session（空状态），等第一次 tick 后立即更新
        let initialSize = NSSize(width: 60, height: 60)
        let x = screenFrame.maxX - initialSize.width - 20
        let y = screenFrame.maxY - initialSize.height - 40

        super.init(contentRect: NSRect(origin: NSPoint(x: x, y: y), size: initialSize),
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        hidesOnDeactivate = false

        lightView = StatusLightView(frame: NSRect(origin: .zero, size: initialSize))
        contentView = lightView
    }

    // MARK: - Size calculation

    /// 根据 session 数量和方向，精确计算窗口尺寸。
    /// 尺寸 = padding*2 + N*circleSize + (N-1)*spacing，至少保证能显示 1 个灯。
    private func sizeForSessions(_ sessions: [SessionInfo]) -> NSSize {
        let count = max(sessions.count, 1)
        let v = lightView!  // 使用 View 里定义的常量，保持一致
        let contentLength = CGFloat(count) * v.circleSize
                          + CGFloat(count - 1) * v.spacing
                          + v.padding * 2
        return isVertical
            ? NSSize(width: fixedCrossAxis, height: contentLength)
            : NSSize(width: contentLength, height: fixedCrossAxis)
    }

    private func resizeForSessions(_ sessions: [SessionInfo]) {
        let newSize = sizeForSessions(sessions)
        let oldFrame = frame
        // 保持窗口顶部/左端位置不变，向下/右扩展
        let newFrame = NSRect(
            x: oldFrame.origin.x,
            y: oldFrame.origin.y + oldFrame.height - newSize.height,
            width: newSize.width,
            height: newSize.height
        )
        setFrame(newFrame, display: true, animate: false)
        lightView.frame = NSRect(origin: .zero, size: newSize)
    }

    // MARK: - Update

    func updateSessions(_ sessions: [SessionInfo]) {
        let newSize = sizeForSessions(sessions)
        if newSize.width != frame.width || newSize.height != frame.height {
            resizeForSessions(sessions)
        }
        currentSessions = sessions
        lightView.updateSessions(sessions)
    }
}
