import Foundation

/// AI 聊天客户端（SSE 流式，经中继代理 → api.b.ai，与 Android 版一致）
@MainActor
final class ChatApiClient: ObservableObject {
    @Published var isStreaming = false

    private var task: URLSessionDataTask?
    private var cancelFlag = false

    func cancel() {
        cancelFlag = true
        task?.cancel()
    }

    /// 发送消息，流式回调（onDelta: 文本, 是否思考过程）
    /// - Returns: 完整回复（nil = 取消/失败）
    func sendMessage(history: [(role: String, content: String)],
                     userMessage: String,
                     model: String = ApiConfig.model,
                     onDelta: @escaping (String, Bool) -> Void) async -> String? {
        cancelFlag = false
        isStreaming = true
        defer { isStreaming = false }

        var messages: [[String: Any]] = [["role": "system", "content": ApiConfig.systemPrompt]]
        for h in history {
            messages.append(["role": h.role, "content": h.content])
        }
        messages.append(["role": "user", "content": userMessage])

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": true,
            "temperature": 0.7,
            "max_tokens": 2048
        ]

        guard let url = URL(string: "\(ApiConfig.baseURL)/chat/completions"),
              let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.httpBody = jsonData
        request.timeoutInterval = 120

        let session = URLSession(configuration: .default)
        do {
            let (bytes, _) = try await session.bytes(for: request)
            var buffer = Data()
            var full = ""
            var reasoningBuf = ""
            var contentBuf = ""
            var lastFlush = Date()

            for try await byte in bytes {
                if cancelFlag { break }
                buffer.append(byte)
                if byte == 0x0A {   // '\n'
                    let line = String(data: buffer, encoding: .utf8) ?? ""
                    buffer = Data()
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed.hasPrefix("data:") else { continue }
                    let data = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    if data.isEmpty || data == "[DONE]" { continue }
                    if let json = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any],
                       let choices = json["choices"] as? [[String: Any]],
                       let delta = choices.first?["delta"] as? [String: Any] {
                        let content = delta["content"] as? String ?? ""
                        let reasoning = delta["reasoning_content"] as? String ?? ""
                        if !reasoning.isEmpty { reasoningBuf += reasoning }
                        if !content.isEmpty {
                            full += content
                            contentBuf += content
                        }
                        if Date().timeIntervalSince(lastFlush) >= 0.05 {
                            flush(&reasoningBuf, &contentBuf, onDelta)
                            lastFlush = Date()
                        }
                    }
                }
            }
            flush(&reasoningBuf, &contentBuf, onDelta)
            isStreaming = false
            return full.isEmpty ? nil : full
        } catch {
            return nil
        }
    }

    private func flush(_ reasoning: inout String, _ content: inout String,
                       _ onDelta: @escaping (String, Bool) -> Void) {
        if !reasoning.isEmpty {
            onDelta(reasoning, true)
            reasoning = ""
        }
        if !content.isEmpty {
            onDelta(content, false)
            content = ""
        }
    }
}
