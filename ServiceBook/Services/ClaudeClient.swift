import Foundation

// MARK: - Public types

/// Live progress reported while Claude works.
enum AIEvent: Sendable, Equatable {
    case status(String)
    case searching(String)          // web search query
    case reading(String)            // URL being fetched
    case results(Int)               // search results received
    case writing(Int)               // schedule items written so far
    case retrying(seconds: Int, reason: String)
}

/// Tokens and server-tool calls used by a request (summed across continuations).
struct AIUsage: Codable, Equatable, Sendable {
    var inputTokens = 0
    var outputTokens = 0
    var webSearches = 0
    var webFetches = 0

    mutating func add(_ other: AIUsage) {
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        webSearches += other.webSearches
        webFetches += other.webFetches
    }

    var summary: String {
        var parts = [L("%@ input + %@ output tokens", Self.compact(inputTokens), Self.compact(outputTokens))]
        if webSearches > 0 { parts.append(L("%lld searches", webSearches)) }
        if webFetches > 0 { parts.append(L("%lld pages read", webFetches)) }
        return parts.joined(separator: " · ")
    }

    static func compact(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : String(n)
    }
}

struct ModelInfo: Identifiable, Hashable, Sendable {
    var id: String
    var displayName: String
    var supportsWebSearch: Bool?
    var supportsPDF: Bool?
    var maxTokens: Int?
}

// MARK: - Stream parsing (pure, unit-tested)

/// Rebuilds a Messages API response from its server-sent events.
/// Blocks are kept as raw JSON so server-tool blocks (with encrypted fields)
/// can be sent back unchanged when the API pauses a long turn.
struct StreamAccumulator {
    private(set) var blocks: [Int: [String: Any]] = [:]
    private var partialJSON: [Int: String] = [:]
    private var writingCount: [Int: Int] = [:]
    private(set) var stopReason: String?
    private(set) var usage = AIUsage()
    private(set) var errorType: String?
    private(set) var errorMessage: String?

    /// Content blocks in order, ready to be sent back as an assistant turn.
    var content: [[String: Any]] {
        blocks.keys.sorted().compactMap { blocks[$0] }.filter { block in
            // The API rejects empty text blocks.
            !((block["type"] as? String) == "text" && ((block["text"] as? String) ?? "").isEmpty)
        }
    }

    /// Text written after the last tool result (the final answer).
    var finalText: String {
        var text = ""
        for block in blocks.keys.sorted().compactMap({ blocks[$0] }) {
            let type = block["type"] as? String ?? ""
            if type == "text" { text += block["text"] as? String ?? "" }
            else if type.hasSuffix("_tool_result") { text = "" }
        }
        return text
    }

    /// First client tool call with the given name (input fully parsed).
    func toolInput(named name: String) -> [String: Any]? {
        for block in blocks.keys.sorted().compactMap({ blocks[$0] })
        where block["type"] as? String == "tool_use" && block["name"] as? String == name {
            return block["input"] as? [String: Any]
        }
        return nil
    }

    /// Feeds one line of the SSE stream; returns the progress events it produced.
    mutating func consume(line: String) -> [AIEvent] {
        guard line.hasPrefix("data:") else { return [] }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let data = payload.data(using: .utf8),
              let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = event["type"] as? String else { return [] }

        var events: [AIEvent] = []
        switch type {
        case "message_start":
            if let u = (event["message"] as? [String: Any])?["usage"] as? [String: Any] { readUsage(u) }

        case "content_block_start":
            guard let index = event["index"] as? Int, let block = event["content_block"] as? [String: Any] else { break }
            blocks[index] = block
            if block["type"] as? String == "web_search_tool_result", let results = block["content"] as? [Any] {
                events.append(.results(results.count))
            }

        case "content_block_delta":
            guard let index = event["index"] as? Int, let delta = event["delta"] as? [String: Any],
                  var block = blocks[index] else { break }
            switch delta["type"] as? String {
            case "text_delta":
                block["text"] = (block["text"] as? String ?? "") + (delta["text"] as? String ?? "")
            case "input_json_delta":
                let json = (partialJSON[index] ?? "") + (delta["partial_json"] as? String ?? "")
                partialJSON[index] = json
                if block["type"] as? String == "tool_use" {
                    let count = json.components(separatedBy: "\"title\"").count - 1
                    if count != writingCount[index] {
                        writingCount[index] = count
                        events.append(.writing(count))
                    }
                }
            case "citations_delta":
                if let c = delta["citation"] {
                    block["citations"] = (block["citations"] as? [Any] ?? []) + [c]
                }
            case "thinking_delta":
                block["thinking"] = (block["thinking"] as? String ?? "") + (delta["thinking"] as? String ?? "")
            case "signature_delta":
                block["signature"] = delta["signature"] as? String ?? ""
            default:
                break
            }
            blocks[index] = block

        case "content_block_stop":
            guard let index = event["index"] as? Int, var block = blocks[index] else { break }
            if let json = partialJSON.removeValue(forKey: index) {
                let parsed = json.isEmpty ? [:] : ((try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:])
                block["input"] = parsed
                blocks[index] = block
            }
            if block["type"] as? String == "server_tool_use", let input = block["input"] as? [String: Any] {
                if let q = input["query"] as? String { events.append(.searching(q)) }
                if let u = input["url"] as? String { events.append(.reading(u)) }
            }

        case "message_delta":
            if let d = event["delta"] as? [String: Any], let reason = d["stop_reason"] as? String { stopReason = reason }
            if let u = event["usage"] as? [String: Any] { readUsage(u) }

        case "error":
            let e = event["error"] as? [String: Any]
            errorType = e?["type"] as? String ?? "error"
            errorMessage = e?["message"] as? String ?? "Unknown streaming error"

        default:
            break   // ping, message_stop and future event types
        }
        return events
    }

    /// Usage values in the stream are cumulative for the message, so they replace earlier ones.
    private mutating func readUsage(_ u: [String: Any]) {
        if let i = u["input_tokens"] as? Int {
            usage.inputTokens = i + (u["cache_read_input_tokens"] as? Int ?? 0) + (u["cache_creation_input_tokens"] as? Int ?? 0)
        }
        if let o = u["output_tokens"] as? Int { usage.outputTokens = o }
        if let s = u["server_tool_use"] as? [String: Any] {
            if let n = s["web_search_requests"] as? Int { usage.webSearches = n }
            if let n = s["web_fetch_requests"] as? Int { usage.webFetches = n }
        }
    }
}

// MARK: - Client

/// Small client for the Claude Messages API (https://docs.claude.com), using streaming.
struct ClaudeClient {
    let apiKey: String
    let model: String
    var maxTokens: Int = 16_000

    static let apiVersion = "2023-06-01"
    static let baseURL = URL(string: "https://api.anthropic.com/v1/")!

    enum ClientError: LocalizedError, Equatable {
        case invalidKey
        case permission(String)
        case noCredit
        case modelUnavailable(String)
        case rateLimited
        case overloaded
        case tooLarge
        case badRequest(String)
        case server(Int, String)
        case truncated
        case refused
        case badResponse
        case network(String)

        var errorDescription: String? {
            switch self {
            case .invalidKey: L("Your Claude API key was rejected. Check it in Settings → Claude connection.")
            case .permission(let m): L("This API key isn't allowed to do that: %@", m)
            case .noCredit: L("Your Anthropic account has no credit left. Add credit at console.anthropic.com, then try again.")
            case .modelUnavailable(let m): L("The model “%@” isn't available for your key. Pick another one in Settings → Claude connection.", m)
            case .rateLimited: L("Too many requests right now. Wait a minute and try again.")
            case .overloaded: L("Claude is overloaded at the moment. Try again in a few minutes.")
            case .tooLarge: L("The request is too large. Try a smaller PDF (only the maintenance chapter).")
            case .badRequest(let m): L("The Claude API refused the request: %@", m)
            case .server(let code, let m): L("Claude API error %lld: %@", code, m)
            case .truncated: L("The answer was cut off because it was too long. Try again, or choose a model with a larger output limit.")
            case .refused: L("Claude declined to answer this request.")
            case .badResponse: L("Unexpected response from the Claude API.")
            case .network(let m): L("Network problem: %@", m)
            }
        }

        var isRetryable: Bool {
            switch self {
            case .rateLimited, .overloaded, .network: true
            case .server(let code, _): code >= 500
            default: false
            }
        }
    }

    struct Outcome {
        var text: String
        var toolInput: [String: Any]?
        var usage: AIUsage
    }

    private func request(path: String, method: String) -> URLRequest {
        var r = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        r.httpMethod = method
        r.timeoutInterval = 300
        r.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        r.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        return r
    }

    // MARK: Models

    /// Lists the models available to this key. Also serves as the connection test.
    func listModels() async throws -> [ModelInfo] {
        var req = request(path: "models", method: "GET")
        req.url = URL(string: Self.baseURL.appendingPathComponent("models").absoluteString + "?limit=100")
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw ClientError.network(error.localizedDescription)
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw Self.mapError(status: code, body: data, model: model) }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else { throw ClientError.badResponse }

        return list.compactMap { m -> ModelInfo? in
            guard let id = m["id"] as? String else { return nil }
            if let lifecycle = m["lifecycle"] as? String, lifecycle == "retired" { return nil }
            let caps = m["capabilities"] as? [String: Any]
            let tools = caps?["server_tools"] as? [String: Any]
            let web = (tools?["web_search"] as? [String: Any])?["supported"] as? Bool
            let pdf = (caps?["pdf_input"] as? [String: Any])?["supported"] as? Bool
            return ModelInfo(id: id, displayName: m["display_name"] as? String ?? id,
                             supportsWebSearch: web, supportsPDF: pdf, maxTokens: m["max_tokens"] as? Int)
        }
    }

    // MARK: Messages

    /// Runs a conversation turn until Claude calls `finalTool` (when given) or finishes.
    /// Handles `pause_turn` continuations, retries transient errors, and reports live events.
    func run(system: String,
             userContent: [[String: Any]],
             tools: [[String: Any]] = [],
             finalTool: String? = nil,
             forceFinalTool: Bool = false,
             onEvent: @escaping @Sendable (AIEvent) -> Void) async throws -> Outcome {
        var messages: [[String: Any]] = [["role": "user", "content": userContent]]
        var usage = AIUsage()
        var forced = forceFinalTool

        for _ in 0..<10 {
            try Task.checkCancellation()
            var body: [String: Any] = [
                "model": model,
                "max_tokens": maxTokens,
                "system": system,
                "messages": messages,
                "stream": true,
            ]
            if !tools.isEmpty { body["tools"] = tools }
            if forced, let finalTool { body["tool_choice"] = ["type": "tool", "name": finalTool] }

            let message = try await streamWithRetry(body, onEvent: onEvent)
            usage.add(message.usage)

            if let finalTool, let input = message.toolInput(named: finalTool) {
                return Outcome(text: message.finalText, toolInput: input, usage: usage)
            }

            switch message.stopReason {
            case "pause_turn":
                messages.append(["role": "assistant", "content": message.content])
            case "max_tokens":
                throw ClientError.truncated
            case "refusal":
                throw ClientError.refused
            default:
                // Finished without calling the final tool: ask once more, forcing it.
                if let finalTool, !forced {
                    let content = message.content
                    if !content.isEmpty { messages.append(["role": "assistant", "content": content]) }
                    messages.append(["role": "user", "content": [["type": "text",
                        "text": "Now call \(finalTool) with everything you found. Leave out anything you could not confirm."]]])
                    forced = true
                    onEvent(.status(L("Writing the schedule…")))
                } else {
                    return Outcome(text: message.finalText, toolInput: nil, usage: usage)
                }
            }
        }
        throw ClientError.badResponse
    }

    private func streamWithRetry(_ body: [String: Any], onEvent: @escaping @Sendable (AIEvent) -> Void) async throws -> StreamAccumulator {
        var attempt = 0
        while true {
            do {
                return try await stream(body, onEvent: onEvent)
            } catch let e as ClientError where e.isRetryable && attempt < 3 {
                attempt += 1
                let wait = [3, 10, 30][attempt - 1]
                onEvent(.retrying(seconds: wait, reason: e.localizedDescription))
                try await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000_000)
            }
        }
    }

    private func stream(_ body: [String: Any], onEvent: @escaping @Sendable (AIEvent) -> Void) async throws -> StreamAccumulator {
        var req = request(path: "messages", method: "POST")
        req.setValue("text/event-stream", forHTTPHeaderField: "accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let bytes: URLSession.AsyncBytes, response: URLResponse
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: req)
        } catch is CancellationError {
            throw CancellationError()
        } catch let e as URLError where e.code == .cancelled {
            throw CancellationError()
        } catch {
            throw ClientError.network(error.localizedDescription)
        }

        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code != 200 {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > 65_536 { break }
            }
            throw Self.mapError(status: code, body: data, model: model)
        }

        var acc = StreamAccumulator()
        do {
            for try await line in bytes.lines {
                for event in acc.consume(line: line) { onEvent(event) }
            }
        } catch let e as URLError where e.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ClientError.network(error.localizedDescription)
        }
        try Task.checkCancellation()

        if let type = acc.errorType {
            switch type {
            case "overloaded_error": throw ClientError.overloaded
            case "rate_limit_error": throw ClientError.rateLimited
            default: throw ClientError.server(500, acc.errorMessage ?? type)
            }
        }
        guard acc.stopReason != nil else { throw ClientError.network(L("The connection closed before Claude finished.")) }
        return acc
    }

    /// Maps an HTTP error response to a friendly error.
    static func mapError(status: Int, body: Data, model: String) -> ClientError {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let message = ((json?["error"] as? [String: Any])?["message"] as? String)
            ?? String(data: body, encoding: .utf8) ?? "unknown error"
        let lower = message.lowercased()
        switch status {
        case 401: return .invalidKey
        case 403: return .permission(message)
        case 404 where lower.contains("model"): return .modelUnavailable(model)
        case 400 where lower.contains("credit balance"): return .noCredit
        case 400 where lower.hasPrefix("model:"): return .modelUnavailable(model)
        case 400: return .badRequest(message)
        case 413: return .tooLarge
        case 429: return .rateLimited
        case 529: return .overloaded
        case 500...599: return .server(status, message)
        default: return .server(status, message)
        }
    }

    /// Extracts the outermost JSON object from a model reply (tolerates ```json fences and prose).
    static func extractJSON(from text: String) -> Data? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return String(text[start...end]).data(using: .utf8)
    }
}
