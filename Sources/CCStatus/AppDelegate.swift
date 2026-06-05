import AppKit
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var menuBarController: MenuBarIcon!
    private var lightWindow: StatusLightWindow?
    private var monitor: SessionMonitor!
    private var timer: Timer?

    private var launchAtLogin: Bool {
        get { UserDefaults.standard.bool(forKey: "LaunchAtLogin") }
        set {
            UserDefaults.standard.set(newValue, forKey: "LaunchAtLogin")
            applyLaunchAtLogin(newValue)
        }
    }

    private var isVertical: Bool {
        get {
            let v = UserDefaults.standard.object(forKey: "WindowOrientation")
            return v == nil ? true : UserDefaults.standard.bool(forKey: "WindowOrientation")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "WindowOrientation")
            lightWindow?.isVertical = newValue
        }
    }

    private var showWindow: Bool {
        get {
            let v = UserDefaults.standard.object(forKey: "ShowWindow")
            return v == nil ? true : UserDefaults.standard.bool(forKey: "ShowWindow")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "ShowWindow")
            applyWindowVisibility()
        }
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        monitor = SessionMonitor()
        setupMenuBar()

        // 首次启动检测 quarantine
        checkQuarantineStatus()

        if showWindow {
            DispatchQueue.main.async { [weak self] in
                self?.setupLightWindow()
            }
        }

        timer = Timer(timeInterval: 0.1, target: self,
                      selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    // MARK: - Setup

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menuBarController = MenuBarIcon(statusItem: statusItem)

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "CC Status", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let windowItem = NSMenuItem(title: "显示窗口", action: #selector(toggleWindow(_:)), keyEquivalent: "w")
        windowItem.state = showWindow ? .on : .off
        menu.addItem(windowItem)

        let orientationItem = NSMenuItem(title: "水平方向", action: #selector(toggleOrientation(_:)), keyEquivalent: "")
        orientationItem.state = isVertical ? .off : .on
        menu.addItem(orientationItem)

        let launchItem = NSMenuItem(title: "开机自动启动", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launchItem.state = launchAtLogin ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())

        let authItem = NSMenuItem(title: "重新授权...", action: #selector(showPermissionGuide(_:)), keyEquivalent: "")
        menu.addItem(authItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func setupLightWindow() {
        lightWindow = StatusLightWindow()
        lightWindow?.isVertical = isVertical
        lightWindow?.show()
    }

    // MARK: - Actions

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        launchAtLogin = !launchAtLogin
        sender.state = launchAtLogin ? .on : .off
    }

    @objc private func toggleOrientation(_ sender: NSMenuItem) {
        isVertical = !isVertical
        sender.state = isVertical ? .off : .on
    }

    @objc private func toggleWindow(_ sender: NSMenuItem) {
        showWindow = !showWindow
        sender.state = showWindow ? .on : .off
    }

    private func applyWindowVisibility() {
        if showWindow {
            if lightWindow == nil { setupLightWindow() }
            lightWindow?.show()
        } else {
            lightWindow?.orderOut(nil)
        }
    }

    private func applyLaunchAtLogin(_ enable: Bool) {
        do {
            if enable { try SMAppService.mainApp.register() }
            else       { try SMAppService.mainApp.unregister() }
        } catch {
            print("Launch at login error: \(error)")
        }
    }

    // MARK: - Tick

    @objc private func tick() {
        let sessions = monitor.updateState()
        let aggregate = SessionMonitor.aggregateState(sessions)
        lightWindow?.updateSessions(sessions)
        menuBarController.updateState(aggregate)
    }

    // MARK: - Quarantine Detection

    private func checkQuarantineStatus() {
        // 只在首次启动时检测，避免每次启动都弹窗
        let didShowGuide = UserDefaults.standard.bool(forKey: "DidShowQuarantineGuide")
        guard !didShowGuide else { return }

        if PermissionGuidePanel.isQuarantined() {
            PermissionGuidePanel.showGuide()
            UserDefaults.standard.set(true, forKey: "DidShowQuarantineGuide")
        }
    }

    @objc private func showPermissionGuide(_ sender: NSMenuItem) {
        PermissionGuidePanel.showGuide()
    }
}
