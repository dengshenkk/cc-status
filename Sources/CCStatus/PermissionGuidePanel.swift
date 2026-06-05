import AppKit

/// 权限引导面板 - 指导用户清除 quarantine 或授权 AppleScript
class PermissionGuidePanel: NSPanel {

    private var commandText: String {
        // 根据运行方式动态生成命令
        if Bundle.main.bundlePath.hasSuffix(".app") {
            return "xattr -cr /Applications/CCStatus.app"
        } else {
            // 从命令行运行时的路径
            let execPath = ProcessInfo.processInfo.arguments[0]
            return "xattr -cr \(execPath)"
        }
    }

    convenience init() {
        self.init(contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
                  styleMask: [.titled, .closable],
                  backing: .buffered,
                  defer: false)
        title = "需要授权"
        isFloatingPanel = true
        level = .floating
        setupUI()
    }

    private func setupUI() {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 260))

        // 图标和标题
        let iconView = NSTextField(labelWithString: "⚠️")
        iconView.font = NSFont.systemFont(ofSize: 32)
        iconView.alignment = .center
        iconView.frame = NSRect(x: 180, y: 200, width: 60, height: 40)
        contentView.addSubview(iconView)

        // 说明文字
        let infoLabel = NSTextField(wrappingLabelWithString:
            "CC Status 需要权限才能切换终端窗口。\n\n请在终端运行以下命令：")
        infoLabel.font = NSFont.systemFont(ofSize: 13)
        infoLabel.alignment = .center
        infoLabel.frame = NSRect(x: 20, y: 120, width: 380, height: 70)
        contentView.addSubview(infoLabel)

        // 命令文本框
        let commandField = NSTextField(string: commandText)
        commandField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        commandField.isEditable = false
        commandField.isSelectable = true
        commandField.bezelStyle = .roundedBezel
        commandField.frame = NSRect(x: 30, y: 85, width: 280, height: 24)
        contentView.addSubview(commandField)

        // 复制按钮
        let copyButton = NSButton(title: "复制命令", target: self, action: #selector(copyCommand(_:)))
        copyButton.bezelStyle = .rounded
        copyButton.frame = NSRect(x: 320, y: 85, width: 80, height: 24)
        contentView.addSubview(copyButton)

        // 提示文字
        let tipLabel = NSTextField(labelWithString: "运行后重启 CC Status 即可生效。")
        tipLabel.font = NSFont.systemFont(ofSize: 12)
        tipLabel.textColor = .secondaryLabelColor
        tipLabel.frame = NSRect(x: 20, y: 50, width: 380, height: 20)
        contentView.addSubview(tipLabel)

        // 知道了按钮
        let okButton = NSButton(title: "知道了", target: self, action: #selector(closePanel(_:)))
        okButton.bezelStyle = .rounded
        okButton.frame = NSRect(x: 170, y: 12, width: 80, height: 28)
        contentView.addSubview(okButton)

        self.contentView = contentView
    }

    @objc private func copyCommand(_ sender: NSButton) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(commandText, forType: .string)

        // 按钮反馈
        let originalTitle = sender.title
        sender.title = "已复制 ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            sender.title = originalTitle
        }
    }

    @objc private func closePanel(_ sender: NSButton) {
        close()
    }

    /// 检测 App 是否被 quarantine
    static func isQuarantined() -> Bool {
        // 优先检测 app bundle，如果没有则检测可执行文件本身
        let appPath: String
        if Bundle.main.bundlePath.hasSuffix(".app") {
            appPath = Bundle.main.bundlePath
        } else {
            // 从命令行运行时，使用可执行文件路径
            appPath = ProcessInfo.processInfo.arguments[0]
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        task.arguments = ["-p", "com.apple.quarantine", appPath]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // 如果 exit code = 0 且有输出，说明存在 quarantine
            return task.terminationStatus == 0 && !output.isEmpty
        } catch {
            return false
        }
    }

    /// 显示引导面板
    static func showGuide() {
        let panel = PermissionGuidePanel()
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
