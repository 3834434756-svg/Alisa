import Foundation

// MARK: - Tool Executor

actor ToolExecutor {
    private let fileSystem: FileSystemService
    private let project: Project

    init(fileSystem: FileSystemService, project: Project) {
        self.fileSystem = fileSystem
        self.project = project
    }

    func execute(_ toolCall: ToolCall) async -> ToolResult {
        do {
            let result = try await executeTool(toolCall)
            return ToolResult(toolCallID: toolCall.id, content: result, isError: false)
        } catch {
            return ToolResult(toolCallID: toolCall.id, content: error.localizedDescription, isError: true)
        }
    }

    private func executeTool(_ toolCall: ToolCall) async throws -> String {
        let args = try JSONDecoder().decode(ToolArguments.self, from: Data(toolCall.arguments.utf8))

        switch toolCall.name {
        case "read_file":
            return try await readFile(path: args.path ?? "")
        case "write_file":
            return try await writeFile(path: args.path ?? "", content: args.content ?? "")
        case "edit_file":
            return try await editFile(path: args.path ?? "", oldText: args.oldText ?? "", newText: args.newText ?? "")
        case "list_files":
            return try await listFiles(path: args.path ?? ".")
        case "run_command":
            return try await runCommand(command: args.command ?? "", args: args.args ?? [])
        default:
            throw ToolExecutorError.unknownTool(toolCall.name)
        }
    }

    private func readFile(path: String) async throws -> String {
        let content = try await fileSystem.readFile(project: project, path: path)
        return "文件内容 (\(path)):\n```\n\(content)\n```"
    }

    private func writeFile(path: String, content: String) async throws -> String {
        try await fileSystem.writeFile(project: project, path: path, content: content)
        return "文件已写入: \(path) (\(content.count) 字符)"
    }

    private func editFile(path: String, oldText: String, newText: String) async throws -> String {
        let content = try await fileSystem.readFile(project: project, path: path)
        guard content.contains(oldText) else {
            throw ToolExecutorError.textNotFound(oldText)
        }
        let newContent = content.replacingOccurrences(of: oldText, with: newText)
        try await fileSystem.writeFile(project: project, path: path, content: newContent)
        return "文件已编辑: \(path) (替换 1 处)"
    }

    private func listFiles(path: String) async throws -> String {
        let projectURL = await fileSystem.projectURL(for: project)
        let targetURL = projectURL.appendingPathComponent(path)
        let contents = try FileManager.default.contentsOfDirectory(at: targetURL, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])

        var result = "目录列表 (\(path)):\n"
        for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let prefix = isDir ? "📁" : "📄"
            result += "\(prefix) \(url.lastPathComponent)\n"
        }
        return result
    }

    private func runCommand(command: String, args: [String]) async throws -> String {
        // Process is macOS-only; not available on iOS
        throw ToolExecutorError.commandNotAllowed("命令行执行仅支持 macOS 端")
    }

    // MARK: - Tool Definitions

    static let availableTools: [ToolDefinition] = [
        ToolDefinition(
            function: FunctionDefinition(
                name: "read_file",
                description: "读取项目中的文件内容",
                parameters: JSONSchema.object([
                    "path": JSONSchemaProperty.string(description: "文件相对路径")
                ], required: ["path"])
            )
        ),
        ToolDefinition(
            function: FunctionDefinition(
                name: "write_file",
                description: "创建或覆盖写入文件",
                parameters: JSONSchema.object([
                    "path": JSONSchemaProperty.string(description: "文件相对路径"),
                    "content": JSONSchemaProperty.string(description: "文件内容")
                ], required: ["path", "content"])
            )
        ),
        ToolDefinition(
            function: FunctionDefinition(
                name: "edit_file",
                description: "对文件进行精确编辑（搜索替换）",
                parameters: JSONSchema.object([
                    "path": JSONSchemaProperty.string(description: "文件相对路径"),
                    "oldText": JSONSchemaProperty.string(description: "要替换的原文本"),
                    "newText": JSONSchemaProperty.string(description: "新文本")
                ], required: ["path", "oldText", "newText"])
            )
        ),
        ToolDefinition(
            function: FunctionDefinition(
                name: "list_files",
                description: "列出目录下的文件",
                parameters: JSONSchema.object([
                    "path": JSONSchemaProperty.string(description: "目录相对路径，默认为项目根目录")
                ], required: [])
            )
        ),
        ToolDefinition(
            function: FunctionDefinition(
                name: "run_command",
                description: "在项目目录下执行允许的 shell 命令",
                parameters: JSONSchema.object([
                    "command": JSONSchemaProperty.string(description: "命令名称", enumValues: ["swift", "python3", "node", "npm", "bun", "git"]),
                    "args": JSONSchemaProperty.array(items: JSONSchemaProperty.string(description: "参数"), description: "命令参数")
                ], required: ["command"])
            )
        )
    ]
}

private struct ToolArguments: Decodable {
    let path: String?
    let content: String?
    let oldText: String?
    let newText: String?
    let command: String?
    let args: [String]?
}

enum ToolExecutorError: LocalizedError {
    case unknownTool(String)
    case textNotFound(String)
    case commandNotAllowed(String)
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unknownTool(let name): return "未知工具: \(name)"
        case .textNotFound(let text): return "未找到要替换的文本: \(text.prefix(50))"
        case .commandNotAllowed(let cmd): return "不允许执行的命令: \(cmd)"
        case .executionFailed(let msg): return "执行失败: \(msg)"
        }
    }
}