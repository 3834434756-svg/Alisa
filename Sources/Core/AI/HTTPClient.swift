import Foundation

@MainActor
final class HTTPClient {
    static let shared = HTTPClient()

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let serialQueue = DispatchQueue(label: "com.alisa.httpclient", qos: .utility)

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = true
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
    }

    // MARK: - Streaming Request

    func streamRequest(
        endpoint: String,
        method: String = "POST",
        headers: [String: String],
        body: Data?,
        onEvent: @escaping (Data) -> Void,
        onComplete: @escaping (Error?) -> Void
    ) {
        guard let url = URL(string: endpoint) else {
            onComplete(HTTPClientError.invalidURL)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let body = body {
            request.httpBody = body
        }

        let task = StreamingTask(session: session, request: request, onEvent: onEvent, onComplete: onComplete)
        task.resume()
    }

    // MARK: - Regular Request

    func request<T: Decodable>(
        endpoint: String,
        method: String = "POST",
        headers: [String: String] = [:],
        body: (any Encodable)? = nil
    ) async throws -> T {
        guard let url = URL(string: endpoint) else { throw HTTPClientError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let body = body {
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPClientError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw HTTPClientError.httpError(statusCode: httpResponse.statusCode, data: data)
        }

        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Certificate Pinning Support

    func setCertificatePinning(_ pins: [String]) {
        // Implementation would use a custom URLSessionDelegate
        // For now, relying on system trust store
    }
}

private class StreamingTask: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let session: URLSession
    let request: URLRequest
    let onEvent: (Data) -> Void
    let onComplete: (Error?) -> Void

    private var buffer = Data()
    private var task: URLSessionDataTask?

    init(session: URLSession, request: URLRequest, onEvent: @escaping (Data) -> Void, onComplete: @escaping (Error?) -> Void) {
        self.session = session
        self.request = request
        self.onEvent = onEvent
        self.onComplete = onComplete
        super.init()
    }

    func resume() {
        task = session.dataTask(with: request)
        task?.delegate = self
        task?.resume()
    }

    func cancel() {
        task?.cancel()
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        processBuffer()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            onComplete(error)
        } else {
            processRemainingBuffer()
            onComplete(nil)
        }
    }

    private func processBuffer() {
        guard let separator = "\n\n".data(using: .utf8) else { return }

        while let range = buffer.range(of: separator) {
            let eventData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)

            if !eventData.isEmpty {
                onEvent(eventData)
            }
        }
    }

    private func processRemainingBuffer() {
        if !buffer.isEmpty {
            onEvent(buffer)
            buffer.removeAll()
        }
    }
}

enum HTTPClientError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, data: Data)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的 URL"
        case .invalidResponse: return "无效的响应"
        case .httpError(let code, let data):
            let message = String(data: data, encoding: .utf8) ?? "无详细信息"
            return "HTTP 错误 \(code): \(message)"
        case .decodingError(let error): return "解码错误: \(error.localizedDescription)"
        }
    }
}

// MARK: - Request/Response Models

struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double?
    let topP: Double?
    let maxTokens: Int?
    let stream: Bool
    let tools: [ToolDefinition]?
    let toolChoice: ToolChoice?
}

struct ChatMessage: Encodable {
    let role: String
    let content: String
    let toolCalls: [ToolCallRequest]?
    let toolCallID: String?
    let name: String?

    init(role: String, content: String, toolCalls: [ToolCallRequest]? = nil, toolCallID: String? = nil, name: String? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.name = name
    }
}

struct ToolDefinition: Encodable {
    let type: String = "function"
    let function: FunctionDefinition
}

struct FunctionDefinition: Encodable {
    let name: String
    let description: String
    let parameters: JSONSchema
}

struct JSONSchema: Encodable {
    let type: String = "object"
    let properties: [String: JSONSchemaProperty]
    let required: [String]?

    static func object(_ properties: [String: JSONSchemaProperty], required: [String]? = nil) -> JSONSchema {
        JSONSchema(properties: properties, required: required)
    }
}

struct JSONSchemaProperty: Encodable {
    let type: String
    let description: String?
    let enumValues: [String]?

    static func string(description: String? = nil, enumValues: [String]? = nil) -> JSONSchemaProperty {
        JSONSchemaProperty(type: "string", description: description, enumValues: enumValues)
    }

    static func integer(description: String? = nil) -> JSONSchemaProperty {
        JSONSchemaProperty(type: "integer", description: description, enumValues: nil)
    }

    static func array(items: JSONSchemaProperty, description: String? = nil) -> JSONSchemaProperty {
        JSONSchemaProperty(type: "array", description: description, enumValues: nil)
    }
}

enum ToolChoice: Encodable {
    case auto
    case none
    case required
    case specific(String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .auto: try container.encode("auto")
        case .none: try container.encode("none")
        case .required: try container.encode("required")
        case .specific(let name):
            var keyed = encoder.container(keyedBy: CodingKeys.self)
            try keyed.encode("function", forKey: .type)
            var nested = keyed.nestedContainer(keyedBy: FunctionCodingKeys.self, forKey: .function)
            try nested.encode(name, forKey: .name)
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, function
    }

    enum FunctionCodingKeys: String, CodingKey {
        case name
    }
}

struct ChatCompletionResponse: Decodable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]
    let usage: Usage?
}

struct Choice: Decodable {
    let index: Int
    let message: ChatMessageResponse
    let finishReason: String?
    let delta: ChatMessageDelta?
}

struct ChatMessageResponse: Decodable {
    let role: String
    let content: String?
    let toolCalls: [ToolCallResponse]?
}

struct ChatMessageDelta: Decodable {
    let role: String?
    let content: String?
    let toolCalls: [ToolCallDelta]?
}

struct ToolCallResponse: Decodable {
    let id: String
    let type: String
    let function: FunctionCall
}

struct FunctionCall: Codable {
    let name: String
    let arguments: String
}

struct ToolCallDelta: Decodable {
    let index: Int?
    let id: String?
    let type: String?
    let function: FunctionCallDelta?
}

struct FunctionCallDelta: Decodable {
    let name: String?
    let arguments: String?
}

struct ToolCallRequest: Encodable {
    let id: String
    let type: String = "function"
    let function: FunctionCall
}

struct Usage: Decodable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - SSE Event Parsing

struct SSEEvent {
    let event: String?
    let data: String
    let id: String?
    let retry: Int?

    static func parse(_ data: Data) -> [SSEEvent] {
        guard let string = String(data: data, encoding: .utf8) else { return [] }
        var events: [SSEEvent] = []
        var currentEvent: String?
        var currentData = ""
        var currentID: String?
        var currentRetry: Int?

        for line in string.components(separatedBy: .newlines) {
            if line.hasPrefix("event:") {
                currentEvent = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                currentData += line.dropFirst(5).trimmingCharacters(in: .whitespaces) + "\n"
            } else if line.hasPrefix("id:") {
                currentID = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("retry:") {
                currentRetry = Int(line.dropFirst(6).trimmingCharacters(in: .whitespaces))
            } else if line.isEmpty {
                events.append(SSEEvent(event: currentEvent, data: currentData.trimmingCharacters(in: .newlines), id: currentID, retry: currentRetry))
                currentEvent = nil
                currentData = ""
                currentID = nil
                currentRetry = nil
            }
        }

        if !currentData.isEmpty {
            events.append(SSEEvent(event: currentEvent, data: currentData.trimmingCharacters(in: .newlines), id: currentID, retry: currentRetry))
        }

        return events
    }
}