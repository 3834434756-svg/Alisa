import Foundation

// MARK: - Stream Parser

actor StreamParser {
    private var buffer = ""
    private let onToken: (String) -> Void
    private let onToolCall: (ToolCall) -> Void
    private let onComplete: (Result<ParsedResponse, Error>) -> Void

    private var currentToolCalls: [String: PartialToolCall] = [:]
    private var accumulatedContent = ""
    private var finishReason: String?
    private var usage: TokenUsage?

    init(
        onToken: @escaping (String) -> Void,
        onToolCall: @escaping (ToolCall) -> Void,
        onComplete: @escaping (Result<ParsedResponse, Error>) -> Void
    ) {
        self.onToken = onToken
        self.onToolCall = onToolCall
        self.onComplete = onComplete
    }

    func parse(_ data: Data) {
        let events = SSEEvent.parse(data)
        for event in events {
            handleEvent(event)
        }
    }

    private func handleEvent(_ event: SSEEvent) {
        guard event.event != "error" else {
            onComplete(.failure(StreamParserError.serverError(event.data)))
            return
        }

        guard event.data != "[DONE]" else {
            finish()
            return
        }

        guard let jsonData = event.data.data(using: .utf8),
              let response = try? JSONDecoder().decode(ChatCompletionResponse.self, from: jsonData) else {
            return
        }

        if let usage = response.usage {
            self.usage = TokenUsage(
                promptTokens: usage.promptTokens,
                completionTokens: usage.completionTokens,
                totalTokens: usage.totalTokens
            )
        }

        for choice in response.choices {
            if let finishReason = choice.finishReason {
                self.finishReason = finishReason
            }

            if let delta = choice.delta {
                handleDelta(delta)
            } else {
                handleMessage(choice.message)
            }
        }
    }

    private func handleDelta(_ delta: ChatMessageDelta) {
        if let content = delta.content {
            accumulatedContent += content
            onToken(content)
        }

        if let toolCalls = delta.toolCalls {
            for delta in toolCalls {
                handleToolCallDelta(delta)
            }
        }
    }

    private func handleMessage(_ message: ChatMessageResponse) {
        if let content = message.content {
            accumulatedContent += content
            onToken(content)
        }

        if let toolCalls = message.toolCalls {
            for tc in toolCalls {
                let toolCall = ToolCall(
                    id: tc.id,
                    name: tc.function.name,
                    arguments: tc.function.arguments
                )
                onToolCall(toolCall)
            }
        }
    }

    private func handleToolCallDelta(_ delta: ToolCallDelta) {
        let index = delta.index ?? 0
        let key = "tool_\(index)"

        var partial = currentToolCalls[key] ?? PartialToolCall(id: delta.id ?? "", name: "", arguments: "")

        if let id = delta.id { partial.id = id }
        if let name = delta.function?.name { partial.name = name }
        if let args = delta.function?.arguments { partial.arguments += args }

        currentToolCalls[key] = partial

        if delta.function?.name != nil || (delta.id != nil && !partial.name.isEmpty) {
            if !partial.name.isEmpty && !partial.arguments.isEmpty {
                let toolCall = ToolCall(id: partial.id, name: partial.name, arguments: partial.arguments)
                currentToolCalls.removeValue(forKey: key)
                onToolCall(toolCall)
            }
        }
    }

    private func finish() {
        let response = ParsedResponse(
            content: accumulatedContent,
            toolCalls: Array(currentToolCalls.values.map { ToolCall(id: $0.id, name: $0.name, arguments: $0.arguments) }),
            finishReason: finishReason ?? "stop",
            usage: usage
        )
        onComplete(.success(response))
    }
}

private struct PartialToolCall {
    var id: String
    var name: String
    var arguments: String
}

struct ParsedResponse {
    let content: String
    let toolCalls: [ToolCall]
    let finishReason: String
    let usage: TokenUsage?
}

struct TokenUsage {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
}

enum StreamParserError: LocalizedError {
    case serverError(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .serverError(let msg): return "服务器错误: \(msg)"
        case .parseError(let msg): return "解析错误: \(msg)"
        }
    }
}

// MARK: - Token Estimator

struct TokenEstimator {
    static func estimate(_ text: String) -> Int {
        max(1, text.count / 3)
    }

    static func estimateMessages(_ messages: [ChatMessage], systemPrompt: String?) -> Int {
        var total = systemPrompt.map { estimate($0) } ?? 0
        for msg in messages {
            total += estimate(msg.content)
            total += 4 // role + formatting overhead
            if let toolCalls = msg.toolCalls {
                for tc in toolCalls {
                    total += estimate(tc.function.name) + estimate(tc.function.arguments) + 10
                }
            }
        }
        return total
    }
}

// MARK: - Context Window Manager

actor ContextWindowManager {
    private let modelContextLimit: Int
    private let reserveRatio: Double = 0.2

    init(modelContextLimit: Int = 128000) {
        self.modelContextLimit = modelContextLimit
    }

    var maxInputTokens: Int {
        Int(Double(modelContextLimit) * (1 - reserveRatio))
    }

    func buildContext(
        systemPrompt: String?,
        messages: [Message],
        referencedFiles: [FileContent],
        selectedCode: String?,
        currentFile: FileContent?
    ) -> (context: AIContext, estimatedTokens: Int) {
        var contextMessages: [ChatMessage] = []

        if let systemPrompt = systemPrompt {
            contextMessages.append(ChatMessage(role: "system", content: systemPrompt))
        }

        var fileContext = ""
        if !referencedFiles.isEmpty {
            fileContext += "\n\n=== 参照文件 ===\n"
            for file in referencedFiles {
                fileContext += "\n--- \(file.path) ---\n```\n\(file.content)\n```\n"
            }
        }

        if let selectedCode = selectedCode, !selectedCode.isEmpty {
            fileContext += "\n\n=== 选中代码 ===\n```\n\(selectedCode)\n```\n"
        }

        if let currentFile = currentFile {
            fileContext += "\n\n=== 当前文件 ===\n--- \(currentFile.path) ---\n```\n\(currentFile.content)\n```\n"
        }

        if !fileContext.isEmpty {
            contextMessages.append(ChatMessage(role: "system", content: fileContext))
        }

        for message in messages {
            let role = message.role.rawValue
            var content = message.content

            if let codeBlocks = message.codeBlocks, !codeBlocks.isEmpty {
                content += "\n\n[代码块: \(codeBlocks.count) 个]"
            }

            contextMessages.append(ChatMessage(role: role, content: content))
        }

        let estimatedTokens = TokenEstimator.estimateMessages(contextMessages, systemPrompt: nil)

        let context = AIContext(
            messages: contextMessages,
            referencedFiles: referencedFiles,
            selectedCode: selectedCode,
            currentFile: currentFile,
            project: nil
        )

        return (context, estimatedTokens)
    }

    func trimMessages(_ messages: [Message], maxTokens: Int, systemPromptTokens: Int) -> [Message] {
        var totalTokens = systemPromptTokens
        var result: [Message] = []

        for message in messages.reversed() {
            let msgTokens = message.tokenCount > 0 ? message.tokenCount : TokenEstimator.estimate(message.content)
            if totalTokens + msgTokens > maxTokens { break }
            result.insert(message, at: 0)
            totalTokens += msgTokens
        }

        return result
    }

    func summarizeOldMessages(_ messages: [Message], keepRecent: Int) -> String {
        guard messages.count > keepRecent else { return "" }
        let oldMessages = messages.dropLast(keepRecent)
        let summary = oldMessages.map { "[\($0.role.rawValue)]: \($0.content.prefix(100))" }.joined(separator: "\n")
        return "=== 历史对话摘要 ===\n\(summary)\n=== 摘要结束 ===\n"
    }
}

// MARK: - AI Context

struct AIContext {
    let messages: [ChatMessage]
    let referencedFiles: [FileContent]
    let selectedCode: String?
    let currentFile: FileContent?
    let project: Project?
}

struct FileContent {
    let path: String
    let content: String
}