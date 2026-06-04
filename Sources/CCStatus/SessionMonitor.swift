import Foundation

enum CCState {
    case busy
    case idle
    case inactive
    case noSession
}

struct SessionInfo: Equatable {
    let id: String
    let pid: Int
    let cwd: String
    let status: CCState
}

class SessionMonitor {
    private let sessionsPath: String

    init() {
        sessionsPath = NSString(string: "~/.claude/sessions").expandingTildeInPath
    }

    func updateState() -> [SessionInfo] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: sessionsPath) else {
            return []
        }

        let jsonFiles = files.filter { $0.hasSuffix(".json") }
        guard !jsonFiles.isEmpty else { return [] }

        var sessions: [SessionInfo] = []

        for file in jsonFiles {
            let path = (sessionsPath as NSString).appendingPathComponent(file)
            guard let data = FileManager.default.contents(atPath: path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String,
                  let sessionId = json["sessionId"] as? String,
                  let pid = json["pid"] as? Int else {
                continue
            }

            let cwd = json["cwd"] as? String ?? ""
            let kind = json["kind"] as? String ?? "interactive"

            // 只显示交互式会话，过滤后台 agent
            guard kind == "interactive" else { continue }

            // 确认进程还活着
            guard kill(pid_t(pid), 0) == 0 else { continue }

            // 确认是 Claude Code 进程（兼容多种安装方式）
            guard isClaudeCodeProcess(pid_t(pid)) else { continue }

            let sessionStatus: CCState
            switch status {
            case "busy":
                sessionStatus = .busy
            case "idle", "waiting":
                sessionStatus = .idle
            default:
                sessionStatus = .inactive
            }

            sessions.append(SessionInfo(id: sessionId, pid: pid, cwd: cwd, status: sessionStatus))
        }

        return sessions.sorted { $0.id < $1.id }
    }

    static func aggregateState(_ sessions: [SessionInfo]) -> CCState {
        if sessions.isEmpty { return .noSession }
        if sessions.contains(where: { $0.status == .idle }) { return .idle }
        if sessions.allSatisfy({ $0.status == .busy }) { return .busy }
        return .inactive
    }

    // MARK: - Process validation

    /// 判断 PID 是否属于 Claude Code 进程。
    /// Claude Code 通常以 Node.js 运行，可执行文件路径本身不含 "claude"，
    /// 因此需要检查进程路径 OR 命令行参数中是否包含 claude-code 相关标识。
    private func isClaudeCodeProcess(_ pid: pid_t) -> Bool {
        // 1. 先检查可执行文件路径（部分安装方式路径含 claude）
        var buf = [CChar](repeating: 0, count: 4096)
        if proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 {
            let execPath = String(cString: buf).lowercased()
            if execPath.contains("/claude") {
                return true
            }
        }

        // 2. 检查进程命令行参数（node 运行 claude-code 的情况）
        if let cmdline = processCommandLine(pid) {
            let lower = cmdline.lowercased()
            if lower.contains("claude-code") ||
               lower.contains("@anthropic-ai/claude-code") ||
               lower.contains("claude_code") ||
               lower.contains("/claude/") {
                return true
            }
        }

        // 3. 检查进程环境变量或工作目录辅助判断
        if let cwd = processCwd(pid) {
            // 如果 session json 里有 cwd，进程自身的 cwd 也可以作为次要参考
            // 这里主要依赖前两项，cwd 仅作 fallback
            _ = cwd
        }

        return false
    }

    /// 读取进程的完整命令行（argv 拼接），用于判断是否是 claude-code
    private func processCommandLine(_ pid: pid_t) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-p", String(pid), "-o", "command="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// 读取进程当前工作目录
    private func processCwd(_ pid: pid_t) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-p", String(pid), "-a", "-d", "cwd", "-F", "n"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            for line in output.components(separatedBy: "\n") {
                if line.hasPrefix("n") { return String(line.dropFirst()) }
            }
        } catch {}
        return nil
    }
}
