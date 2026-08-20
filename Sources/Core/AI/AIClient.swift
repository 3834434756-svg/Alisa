import Foundation

// MARK: - AI Client

@MainActor
final class AIClient {
    static let shared = AIClient()

    private let httpClient = HTTPClient.shared
    private let contextManager = ContextWindowManager()
    private let streamParser: StreamParser?

    private init() {
        self.streamParser = nil
    }

    // MARK: - Configuration

    private var currentConfig: APIConfig?
    private var currentParameters: AIParameters = AIParameters()

    func configure(config: APIConfig, parameters: AIParameters) {
        self.currentConfig = config
        self.currentParameters = parameters
    }

    // MARK: - Send Message (Streaming)

    func sendMessage(
        _ message: String,
        context: AIContext,
        parameters: AIParameters? = nil,
        onToken: @escaping (String) -> Void,
        onToolCall: @escaping (ToolCall) -> Void,
        onComplete: @escaping (Result<AIResponse, Error>) -> Void
    ) async {
        guard let config = currentConfig else {
            onComplete(.failure(AIClientError.notConfigured))
            return
        }

        let params = parameters ?? currentParameters
        let apiKey: String
        do {
            apiKey = try await KeychainService.shared.getAPIKey(for: config.id) ?? ""
        } catch {
            onComplete(.failure(error))
            return
        }

        guard !apiKey.isEmpty else {
            onComplete(.failure(AIClientError.missingAPIKey))
            return
        }

        let request = buildRequest(message: message, context: context, config: config, parameters: params, apiKey: apiKey)

        httpClient.streamRequest(
            endpoint: "\(config.baseURL)/chat/completions",
            headers: buildHeaders(apiKey: apiKey, config: config),
            body: try? JSONEncoder().encode(request),
            onEvent: { data in
                Task { @MainActor in
                    self.parseStreamEvent(data, onToken: onToken, onToolCall: onToolCall, onComplete: onComplete)
                }
            },
            onComplete: { error in
                Task { @MainActor in
                    if let error = error {
                        onComplete(.failure(error))
                    }
                }
            }
        )
    }

    // MARK: - Send Message with Tools (Full Flow)

    func sendMessageWithTools(
        _ message: String,
        context: AIContext,
        parameters: AIParameters? = nil,
        availableTools: [ToolDefinition] = ToolExecutor.availableTools,
        onToken: @escaping (String) -> Void,
        onToolCall: @escaping (ToolCall) -> Void,
        onToolResult: @escaping (ToolResult) -> Void,
        onComplete: @escaping (Result<AIResponse, Error>) -> Void
    ) async {
        guard let config = currentConfig else {
            onComplete(.failure(AIClientError.notConfigured))
            return
        }

        let params = parameters ?? currentParameters
        let apiKey: String
        do {
            apiKey = try await KeychainService.shared.getAPIKey(for: config.id) ?? ""
        } catch {
            onComplete(.failure(error))
            return
        }

        await executeToolLoop(
            initialMessage: message,
            context: context,
            config: config,
            parameters: params,
            apiKey: apiKey,
            availableTools: availableTools,
            onToken: onToken,
            onToolCall: onToolCall,
            onToolResult: onToolResult,
            onComplete: onComplete
        )
    }

    private func executeToolLoop(
        initialMessage: String,
        context: AIContext,
        config: APIConfig,
        parameters: AIParameters,
        apiKey: String,
        availableTools: [ToolDefinition],
        onToken: @escaping (String) -> Void,
        onToolCall: @escaping (ToolCall) -> Void,
        onToolResult: @escaping (ToolResult) -> Void,
        onComplete: @escaping (Result<AIResponse, Error>) -> Void
    ) async {
        var messages = context.messages
        messages.append(ChatMessage(role: "user", content: initialMessage))

        var allContent = ""
        var allToolCalls: [ToolCall] = []
        var finalUsage: TokenUsage?
        var finishReason: String?

        for iteration in 0..<5 { // Max 5 tool iterations
            let request = buildRequest(
                messages: messages,
                config: config,
                parameters: parameters,
                tools: iteration == 0 ? availableTools : [],
                toolChoice: iteration == 0 ? .auto : .none
            )

            do {
                let response = try await performStreamingRequest(
                    request: request,
                    endpoint: "\(config.baseURL)/chat/completions",
                    headers: buildHeaders(apiKey: apiKey, config: config),
                    onToken: onToken,
                    onToolCall: onToolCall
                )

                allContent += response.content
                allToolCalls.append(contentsOf: response.toolCalls)
                finalUsage = response.usage
                finishReason = response.finishReason

                if response.toolCalls.isEmpty {
                    break
                }

                // Execute tools
                let toolExecutor = ToolExecutor(fileSystem: FileSystemService.shared, project: context.project ?? Project(name: "default", rootPath: "."))
                for toolCall in response.toolCalls {
                    let result = await toolExecutor.execute(toolCall)
                    onToolResult(result)

                    messages.append(ChatMessage(
                        role: "tool",
                        content: result.content,
                        toolCallID: toolCall.id
                    ))
                }

                messages.append(ChatMessage(
                    role: "assistant",
                    content: response.content,
                    toolCalls: response.toolCalls.map { ToolCallRequest(id: $0.id, function: FunctionCall(name: $0.name, arguments: $0.arguments)) }
                ))

            } catch {
                onComplete(.failure(error))
                return
            }
        }

        let response = AIResponse(
            content: allContent,
            codeBlocks: extractCodeBlocks(allContent),
            toolCalls: allToolCalls,
            usage: finalUsage ?? TokenUsage(promptTokens: 0, completionTokens: 0, totalTokens: 0),
            finishReason: finishReason ?? "stop"
        )

        onComplete(.success(response))
    }

    // MARK: - Request Building

    private func buildRequest(
        message: String,
        context: AIContext,
        config: APIConfig,
        parameters: AIParameters,
        apiKey: String
    ) -> ChatCompletionRequest {
        var messages = context.messages
        messages.append(ChatMessage(role: "user", content: message))

        return buildRequest(
            messages: messages,
            config: config,
            parameters: parameters,
            tools: ToolExecutor.availableTools,
            toolChoice: .auto
        )
    }

    private func buildRequest(
        messages: [ChatMessage],
        config: APIConfig,
        parameters: AIParameters,
        tools: [ToolDefinition],
        toolChoice: ToolChoice
    ) -> ChatCompletionRequest {
        var temp = parameters
        if temp.temperature > 1.0 { temp.temperature = 1.0 }
        if temp.topP > 1.0 { temp.topP = 1.0 }

        let systemPrompt = buildSystemPrompt(parameters: parameters)
        var finalMessages = messages
        if !systemPrompt.isEmpty {
            finalMessages.insert(ChatMessage(role: "system", content: systemPrompt), at: 0)
        }

        return ChatCompletionRequest(
            model: config.model,
            messages: finalMessages,
            temperature: temp.temperature,
            topP: temp.topP,
            maxTokens: temp.maxTokens,
            stream: true,
            tools: tools.isEmpty ? nil : tools,
            toolChoice: toolChoice
        )
    }

    private func buildSystemPrompt(parameters: AIParameters) -> String {
        var parts: [String] = []

        if let customPrompt = parameters.systemPrompt, !customPrompt.isEmpty {
            parts.append(customPrompt)
        }

        switch parameters.thinkingDuration {
        case .fast:
            parts.append("思考模式：快速响应，简洁直接。")
        case .balanced:
            parts.append("思考模式：平衡深度与速度，提供充分分析。")
        case .deep:
            parts.append("思考模式：深度思考，详细分析问题，提供全面方案。")
        }

        parts.append("推理强度：\(parameters.thinkingIntensity)/100")

        switch parameters.reasoningMode {
        case .standard:
            parts.append("推理模式：标准模式。")
        case .deep:
            parts.append("推理模式：深度推理，展示思考过程。")
        case .code:
            parts.append("推理模式：代码专用，优先提供可运行代码，遵循最佳实践。")
        }

        return parts.joined(separator: "\n\n")
    }

    private func buildHeaders(apiKey: String, config: APIConfig) -> [String: String] {
        var headers = [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json"
        ]
        if let customHeaders = config.customHeaders {
            headers.merge(customHeaders) { _, new in new }
        }
        return headers
    }

    // MARK: - Streaming Request

    private func performStreamingRequest(
        request: ChatCompletionRequest,
        endpoint: String,
        headers: [String: String],
        onToken: @escaping (String) -> Void,
        onToolCall: @escaping (ToolCall) -> Void
    ) async throws -> ParsedResponse {
        try await withCheckedThrowingContinuation { continuation in
            var accumulatedContent = ""
            var accumulatedToolCalls: [ToolCall] = []
            var finishReason: String?
            var usage: TokenUsage?

            httpClient.streamRequest(
                endpoint: endpoint,
                headers: headers,
                body: try? JSONEncoder().encode(request),
                onEvent: { data in
                    let events = SSEEvent.parse(data)
                    for event in events {
                        if event.data == "[DONE]" { continue }
                        guard let jsonData = event.data.data(using: .utf8),
                              let response = try? JSONDecoder().decode(ChatCompletionResponse.self, from: jsonData) else {
                            continue
                        }

                        if let u = response.usage {
                            usage = TokenUsage(promptTokens: u.promptTokens, completionTokens: u.completionTokens, totalTokens: u.totalTokens)
                        }

                        for choice in response.choices {
                            if let fr = choice.finishReason { finishReason = fr }

                            if let delta = choice.delta {
                                if let content = delta.content {
                                    accumulatedContent += content
                                    Task { @MainActor in onToken(content) }
                                }
                                if let toolCalls = delta.toolCalls {
                                    for tc in toolCalls {
                                        if let name = tc.function?.name, let args = tc.function?.arguments {
                                            let toolCall = ToolCall(id: tc.id ?? UUID().uuidString, name: name, arguments: args)
                                            accumulatedToolCalls.append(toolCall)
                                            Task { @MainActor in onToolCall(toolCall) }
                                        }
                                    }
                                }
                            } else {
                                let message = choice.message
                                if let content = message.content {
                                    accumulatedContent += content
                                    Task { @MainActor in onToken(content) }
                                }
                                if let toolCalls = message.toolCalls {
                                    for tc in toolCalls {
                                        let toolCall = ToolCall(id: tc.id, name: tc.function.name, arguments: tc.function.arguments)
                                        accumulatedToolCalls.append(toolCall)
                                        Task { @MainActor in onToolCall(toolCall) }
                                    }
                                }
                            }
                        }
                    }
                },
                onComplete: { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        let parsed = ParsedResponse(
                            content: accumulatedContent,
                            toolCalls: accumulatedToolCalls,
                            finishReason: finishReason ?? "stop",
                            usage: usage
                        )
                        continuation.resume(returning: parsed)
                    }
                }
            )
        }
    }

    // MARK: - Simple Stream Event Parsing

    private func parseStreamEvent(
        _ data: Data,
        onToken: @escaping (String) -> Void,
        onToolCall: @escaping (ToolCall) -> Void,
        onComplete: @escaping (Result<AIResponse, Error>) -> Void
    ) {
        // This is a simplified inline parser for the basic sendMessage method
        // For full tool support, use sendMessageWithTools
        let events = SSEEvent.parse(data)
        for event in events {
            guard event.data != "[DONE]" else { return }
            guard let jsonData = event.data.data(using: .utf8),
                  let response = try? JSONDecoder().decode(ChatCompletionResponse.self, from: jsonData) else {
                continue
            }

            for choice in response.choices {
                if let delta = choice.delta {
                    if let content = delta.content {
                        onToken(content)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func extractCodeBlocks(_ content: String) -> [CodeBlock] {
        var blocks: [CodeBlock] = []
        let pattern = "```(\\w+)?\\n([\\s\\S]*?)```"
        let regex = try? NSRegularExpression(pattern: pattern)
        let matches = regex?.matches(in: content, range: NSRange(content.startIndex..., in: content)) ?? []

        for match in matches {
            let languageRange = match.range(at: 1)
            let codeRange = match.range(at: 2)

            let language = languageRange.location != NSNotFound
                ? String(content[Range(languageRange, in: content)!])
                : "text"
            let code = String(content[Range(codeRange, in: content)!])

            blocks.append(CodeBlock(language: language, code: code))
        }
        return blocks
    }
}

// MARK: - Response Models

struct AIResponse {
    let content: String
    let codeBlocks: [CodeBlock]
    let toolCalls: [ToolCall]
    let usage: TokenUsage
    let finishReason: String
}

enum AIClientError: LocalizedError {
    case notConfigured
    case missingAPIKey
    case invalidResponse
    case streamError(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "AI 客户端未配置"
        case .missingAPIKey: return "缺少 API Key"
        case .invalidResponse: return "无效的响应"
        case .streamError(let msg): return "流式传输错误: \(msg)"
        }
    }
}

