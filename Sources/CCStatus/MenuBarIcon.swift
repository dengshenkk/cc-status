import AppKit

class MenuBarIcon {
    private let statusItem: NSStatusItem

    private let greenColor  = NSColor(red: 0.2,  green: 0.85, blue: 0.3,  alpha: 1.0)
    private let yellowColor = NSColor(red: 1.0,  green: 0.80, blue: 0.0,  alpha: 1.0)
    private let redColor    = NSColor(red: 0.95, green: 0.2,  blue: 0.15, alpha: 1.0)
    private let grayColor   = NSColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 1.0)

    private var currentState: CCState = .noSession
    private var blinkPhase: Bool = true
    private var blinkTimer: Timer?

    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        blinkTimer = Timer(timeInterval: 0.5, target: self,
                           selector: #selector(toggleBlink), userInfo: nil, repeats: true)
        RunLoop.main.add(blinkTimer!, forMode: .common)
        updateIcon(color: grayColor)
    }

    @objc private func toggleBlink() {
        blinkPhase.toggle()
        updateState(currentState)
    }

    func updateState(_ state: CCState) {
        currentState = state
        let color: NSColor
        switch state {
        case .busy:     color = greenColor
        case .idle:     color = blinkPhase ? yellowColor : grayColor
        case .inactive: color = blinkPhase ? redColor    : grayColor
        case .noSession: color = grayColor
        }
        updateIcon(color: color)
    }

    private func updateIcon(color: NSColor) {
        let size: CGFloat = 14
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSGraphicsContext.current!.cgContext.setFillColor(color.cgColor)
            NSGraphicsContext.current!.cgContext.fillEllipse(in: rect)
            return true
        }
        image.isTemplate = false
        statusItem.button?.image = image
    }

    deinit { blinkTimer?.invalidate() }
}
