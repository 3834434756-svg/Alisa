import Foundation

// MARK: - API Configuration

struct APIConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var baseURL: String
    var keychainKeyRef: String
    var model: String
    var customHeaders: [String: String]?
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, baseURL: String, keychainKeyRef: String, model: String, customHeaders: [String: String]? = nil, isActive: Bool = false) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.keychainKeyRef = keychainKeyRef
        self.model = model
        self.customHeaders = customHeaders
        self.isActive = isActive
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Role

struct Role: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var systemPrompt: String
    var specialties: [String]
    var defaultParameters: AIParameters?
    var isBuiltIn: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, systemPrompt: String, specialties: [String] = [], defaultParameters: AIParameters? = nil, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.specialties = specialties
        self.defaultParameters = defaultParameters
        self.isBuiltIn = isBuiltIn
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - AI Parameters

struct AIParameters: Codable, Equatable {
    var thinkingDuration: ThinkingDuration
    var thinkingIntensity: Int
    var reasoningMode: ReasoningMode
    var maxTokens: Int
    var temperature: Double
    var topP: Double
    var systemPrompt: String?

    init(thinkingDuration: ThinkingDuration = .balanced, thinkingIntensity: Int = 70, reasoningMode: ReasoningMode = .code, maxTokens: Int = 8192, temperature: Double = 0.3, topP: Double = 0.95, systemPrompt: String? = nil) {
        self.thinkingDuration = thinkingDuration
        self.thinkingIntensity = thinkingIntensity
        self.reasoningMode = reasoningMode
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.systemPrompt = systemPrompt
    }
}

enum ThinkingDuration: String, Codable, CaseIterable {
    case fast = "fast"
    case balanced = "balanced"
    case deep = "deep"

    var displayName: String {
        switch self {
        case .fast: return "快速"
        case .balanced: return "平衡"
        case .deep: return "深度"
        }
    }

    var estimatedMultiplier: Double {
        switch self {
        case .fast: return 0.5
        case .balanced: return 1.0
        case .deep: return 2.0
        }
    }
}

enum ReasoningMode: String, Codable, CaseIterable {
    case standard = "standard"
    case deep = "deep"
    case code = "code"

    var displayName: String {
        switch self {
        case .standard: return "标准"
        case .deep: return "深度思考"
        case .code: return "代码专用"
        }
    }
}

// MARK: - Session

struct Session: Codable, Identifiable, Equatable {
    var id: UUID
    var projectID: UUID?
    var roleID: UUID
    var title: String
    var messageCount: Int
    var totalTokens: Int
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), projectID: UUID? = nil, roleID: UUID, title: String = "新会话") {
        self.id = id
        self.projectID = projectID
        self.roleID = roleID
        self.title = title
        self.messageCount = 0
        self.totalTokens = 0
        self.isArchived = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Message

struct Message: Codable, Identifiable, Equatable {
    var id: UUID
    var sessionID: UUID
    var role: MessageRole
    var content: String
    var codeBlocks: [CodeBlock]?
    var fileReferences: [FileReference]?
    var toolCalls: [ToolCall]?
    var toolResults: [ToolResult]?
    var tokenCount: Int
    var status: MessageStatus
    var createdAt: Date

    init(id: UUID = UUID(), sessionID: UUID, role: MessageRole, content: String, codeBlocks: [CodeBlock]? = nil, fileReferences: [FileReference]? = nil, toolCalls: [ToolCall]? = nil, toolResults: [ToolResult]? = nil, tokenCount: Int = 0, status: MessageStatus = .completed) {
        self.id = id
        self.sessionID = sessionID
        self.role = role
        self.content = content
        self.codeBlocks = codeBlocks
        self.fileReferences = fileReferences
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.tokenCount = tokenCount
        self.status = status
        self.createdAt = Date()
    }
}

enum MessageRole: String, Codable {
    case user, assistant, system, tool
}

enum MessageStatus: String, Codable {
    case sending, streaming, completed, failed
}

// MARK: - Code Block

struct CodeBlock: Codable, Equatable, Identifiable {
    var id: UUID
    var language: String
    var code: String
    var filePath: String?
    var action: CodeBlockAction

    init(id: UUID = UUID(), language: String, code: String, filePath: String? = nil, action: CodeBlockAction = .create) {
        self.id = id
        self.language = language
        self.code = code
        self.filePath = filePath
        self.action = action
    }
}

enum CodeBlockAction: String, Codable {
    case create, replace, append, preview
}

// MARK: - File Reference

struct FileReference: Codable, Equatable {
    var path: String
    var content: String?
}

// MARK: - Tool Call / Result

struct ToolCall: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var arguments: String
}

struct ToolResult: Codable, Equatable {
    var toolCallID: String
    var content: String
    var isError: Bool
}

// MARK: - Project

struct Project: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var rootPath: String
    var template: ProjectTemplate?
    var lastOpenedAt: Date
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, rootPath: String, template: ProjectTemplate? = nil) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.template = template
        self.lastOpenedAt = Date()
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

enum ProjectTemplate: String, Codable, CaseIterable {
    case empty = "empty"
    case swiftPackage = "swift-package"
    case pythonScript = "python-script"
    case htmlSite = "html-site"

    var displayName: String {
        switch self {
        case .empty: return "空项目"
        case .swiftPackage: return "Swift Package"
        case .pythonScript: return "Python 脚本"
        case .htmlSite: return "静态网站"
        }
    }

    var defaultFiles: [String: String] {
        switch self {
        case .empty: return [:]
        case .swiftPackage:
            return [
                "Package.swift": "// swift-tools-version: 6.0\nimport PackageDescription\n\nlet package = Package(\n    name: \"MyPackage\",\n    products: [\n        .library(name: \"MyPackage\", targets: [\"MyPackage\"])\n    ],\n    targets: [\n        .target(name: \"MyPackage\"),\n        .testTarget(name: \"MyPackageTests\", dependencies: [\"MyPackage\"])\n    ]\n)",
                "Sources/MyPackage/MyPackage.swift": "public struct MyPackage {\n    public init() {}\n    public func hello() -> String { \"Hello, World!\" }\n}"
            ]
        case .htmlSite:
            return [
                "index.html": "<!DOCTYPE html>\n<html lang=\"zh-CN\">\n<head>\n    <meta charset=\"UTF-8\">\n    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n    <title>My Site</title>\n    <link rel=\"stylesheet\" href=\"style.css\">\n</head>\n<body>\n    <h1>Welcome</h1>\n</body>\n</html>",
                "style.css": "body { font-family: -apple-system, sans-serif; }"
            ]
        case .pythonScript:
            return ["main.py": "#!/usr/bin/env python3\nprint('Hello, World!')"]
        }
    }
}

// MARK: - File Node

struct FileNode: Codable, Equatable, Identifiable {
    var id: String { path }
    let name: String
    let path: String
    let isDirectory: Bool
    var children: [FileNode]?
    let modifiedAt: Date
    let size: Int64?

    init(name: String, path: String, isDirectory: Bool, children: [FileNode]? = nil, modifiedAt: Date = Date(), size: Int64? = nil) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.children = children
        self.modifiedAt = modifiedAt
        self.size = size
    }
}