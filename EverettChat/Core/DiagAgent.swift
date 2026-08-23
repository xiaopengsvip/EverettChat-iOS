import Foundation
import UIKit

/// 远程诊断 Agent（日志缓冲 + 远程命令执行）
/// 通过 relay 的 /log 和 /cmd 端点对接，Hermes 可远程查状态/发命令
@MainActor
final class DiagAgent {
    static let shared = DiagAgent()

    // 环状日志缓冲（最近 200 条）
    private var logBuffer: [LogEntry] = []
    private let maxLogs = 200
    private let httpBase = PublicRelay.httpURL

    struct LogEntry: Codable {
        let t: Double           // timestamp
        let lvl: String         // debug | info | warn | error
        let msg: String
    }

    private init() {
        // 自动上报关键事件
        log("info", "DiagAgent initialized")
        NotificationCenter.default.addObserver(
            self, selector: #selector(onAppStateChange),
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
    }

    @objc private func onAppStateChange() {
        log("info", "App became active")
    }

    // MARK: - 日志

    /// 写入本地日志缓冲
    func log(_ lvl: String, _ msg: String, file: String = #file, line: Int = #line) {
        let entry = LogEntry(t: Date().timeIntervalSince1970, lvl: lvl, msg: "[\(file.split(separator: "/").last ?? ""):\(line)] \(msg)")
        logBuffer.append(entry)
        if logBuffer.count > maxLogs { logBuffer.removeFirst(logBuffer.count - maxLogs) }
        #if DEBUG
        print("[Diag] \(lvl.uppercased()): \(msg)")
        #endif
    }

    /// 获取最近日志（倒序）
    func recentLogs(_ limit: Int = 50) -> [LogEntry] {
        Array(logBuffer.suffix(limit).reversed())
    }

    // MARK: - 主动上报到 relay

    /// 上报日志到 relay（通过 HTTP POST /log）
    func flushLogs() async {
        guard !logBuffer.isEmpty, let url = URL(string: "\(httpBase)/log") else { return }
        let deviceId = DeviceIdentity.shared.deviceId
        let deviceName = DeviceIdentity.shared.deviceName
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let body: [String: Any] = [
            "deviceId": deviceId, "device": deviceName, "version": "iOS-v\(appVersion)-\(build)",
            "logs": logBuffer.map { ["t": $0.t, "lvl": $0.lvl, "msg": $0.msg] }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        do {
            let (_, _) = try await URLSession.shared.data(for: req)
            logBuffer.removeAll()  // 上报后清本地缓冲
            log("info", "Logs flushed to relay")
        } catch {
            log("warn", "Log flush failed: \(error.localizedDescription)")
        }
    }

    // MARK: - 远程命令处理

    /// 处理来自 relay 的远程命令（由 RelayTransport 的 __cmd__ 分支调用）
    func handleCommand(_ cmd: String, requestId: String) async -> String {
        log("info", "Executing cmd: \(cmd) (req=\(requestId))")
        switch cmd {
        case "version", "v":
            return await getVersionInfo()
        case "status", "st":
            return await getStatus()
        case "log":
            return await getLogJSON()
        case "ping":
            return "pong"
        case "reconnect":
            return await reconnect()
        case "clear_logs":
            logBuffer.removeAll()
            return "logs cleared"
        default:
            return "unknown command: \(cmd)"
        }
    }

    // MARK: - 命令实现

    private func getVersionInfo() async -> String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let device = DeviceIdentity.shared.deviceName
        let shortId = DeviceIdentity.shared.shortId
        let os = "iOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        return "EVO iOS v\(appVersion)(\(build)) · \(device) · \(shortId) · \(os) · E2Ev1"
    }

    private func getStatus() async -> String {
        let relay = RelayTransport.shared
        let isConnected = relay.isConnected
        let onlineCount = relay.onlineUsers.count
        let peerName = relay.peerName
        let conn = ConnectionManager.shared
        let connState = conn.state
        return "connected=\(isConnected) · online=\(onlineCount) · peer=\(peerName) · connState=\(connState.rawValue)"
    }

    private func getLogJSON() async -> String {
        let logs = recentLogs(30)
        guard let data = try? JSONSerialization.data(withJSONObject: logs.map { ["t": $0.t, "lvl": $0.lvl, "msg": $0.msg] }),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }

    private func reconnect() async -> String {
        let relay = RelayTransport.shared
        relay.disconnect()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        relay.connect()
        return "reconnect triggered"
    }
}