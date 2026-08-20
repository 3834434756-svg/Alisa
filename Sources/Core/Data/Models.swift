import Foundation

// MARK: - API Configuration

struct APIConfig: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    var id: UUID
    var name: String
    var baseURL: String
    var keychainKeyRef: String
    var model: String
    var customHeaders: [String: String]?
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    static let databaseTableName = "api_configs"

    enum Columns: String, ColumnExpression {
        case id, name, baseURL, keychainKeyRef, model, customHeaders, isActive, createdAt, updatedAt
    }

    init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        keychainKeyRef: String,
        model: String,
        customHeaders: [String: String]? = nil,
        isActive: Bool = false
    ) {
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

    mutating func didInsert(_ inserted: InsertionSuccess) {
        // GRDB required
    }
}

// MARK: - Role

struct Role: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    var id: UUID
    var name: String
    var systemPrompt: String
    var specialties: [String]
    var defaultParametersData: Data?
    var isBuiltIn: Bool
    var createdAt: Date
    var updatedAt: Date

    static let databaseTableName = "roles"

    enum Columns: String, ColumnExpression {
        case id, name, systemPrompt, specialties, defaultParametersData, isBuiltIn, createdAt, updatedAt
    }

    var defaultParameters: AIParameters? {
        get {
            guard let data = defaultParametersData else { return nil }
            return try? JSONDecoder().decode(AIParameters.self, from: data)
        }
        set {
            defaultParametersData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        systemPrompt: String,
        specialties: [String] = [],
        defaultParameters: AIParameters? = nil,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.specialties = specialties
        self.defaultParametersData = defaultParameters.flatMap { try? JSONEncoder().encode($0) }
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

    init(
        thinkingDuration: ThinkingDuration = .balanced,
        thinkingIntensity: Int = 70,
        reasoningMode: ReasoningMode = .code,
        maxTokens: Int = 8192,
        temperature: Double = 0.3,
        topP: Double = 0.95,
        systemPrompt: String? = nil
    ) {
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

struct Session: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    var id: UUID
    var projectID: UUID?
    var roleID: UUID
    var title: String
    var messageCount: Int
    var totalTokens: Int
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    static let databaseTableName = "sessions"

    enum Columns: String, ColumnExpression {
        case id, projectID, roleID, title, messageCount, totalTokens, isArchived, createdAt, updatedAt
    }

    init(
        id: UUID = UUID(),
        projectID: UUID? = nil,
        roleID: UUID,
        title: String = "新会话"
    ) {
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

struct Message: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    var id: UUID
    var sessionID: UUID
    var role: MessageRole
    var content: String
    var codeBlocksData: Data?
    var fileReferencesData: Data?
    var toolCallsData: Data?
    var toolResultsData: Data?
    var tokenCount: Int
    var status: MessageStatus
    var createdAt: Date

    static let databaseTableName = "messages"

    enum Columns: String, ColumnExpression {
        case id, sessionID, role, content, codeBlocksData, fileReferencesData, toolCallsData, toolResultsData, tokenCount, status, createdAt
    }

    var codeBlocks: [CodeBlock]? {
        get { codeBlocksData.flatMap { try? JSONDecoder().decode([CodeBlock].self, from: $0) } }
        set { codeBlocksData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var fileReferences: [FileReference]? {
        get { fileReferencesData.flatMap { try? JSONDecoder().decode([FileReference].self, from: $0) } }
        set { fileReferencesData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var toolCalls: [ToolCall]? {
        get { toolCallsData.flatMap { try? JSONDecoder().decode([ToolCall].self, from: $0) } }
        set { toolCallsData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var toolResults: [ToolResult]? {
        get { toolResultsData.flatMap { try? JSONDecoder().decode([ToolResult].self, from: $0) } }
        set { toolResultsData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        role: MessageRole,
        content: String,
        codeBlocks: [CodeBlock]? = nil,
        fileReferences: [FileReference]? = nil,
        toolCalls: [ToolCall]? = nil,
        toolResults: [ToolResult]? = nil,
        tokenCount: Int = 0,
        status: MessageStatus = .completed
    ) {
        self.id = id
        self.sessionID = sessionID
        self.role = role
        self.content = content
        self.codeBlocksData = codeBlocks.flatMap { try? JSONEncoder().encode($0) }
        self.fileReferencesData = fileReferences.flatMap { try? JSONEncoder().encode($0) }
        self.toolCallsData = toolCalls.flatMap { try? JSONEncoder().encode($0) }
        self.toolResultsData = toolResults.flatMap { try? JSONEncoder().encode($0) }
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

    init(
        id: UUID = UUID(),
        language: String,
        code: String,
        filePath: String? = nil,
        action: CodeBlockAction = .create
    ) {
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

struct ToolCall: Codable, Equatable {
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

struct Project: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    var id: UUID
    var name: String
    var rootPath: String
    var template: ProjectTemplate?
    var lastOpenedAt: Date
    var createdAt: Date
    var updatedAt: Date

    static let databaseTableName = "projects"

    enum Columns: String, ColumnExpression {
        case id, name, rootPath, template, lastOpenedAt, createdAt, updatedAt
    }

    init(
        id: UUID = UUID(),
        name: String,
        rootPath: String,
        template: ProjectTemplate? = nil
    ) {
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
    case reactNative = "react-native"
    case pythonScript = "python-script"
    case htmlSite = "html-site"
    case viteVue = "vite-vue"
    case nextJS = "nextjs"

    var displayName: String {
        switch self {
        case .empty: return "空项目"
        case .swiftPackage: return "Swift Package"
        case .reactNative: return "React Native"
        case .pythonScript: return "Python 脚本"
        case .htmlSite: return "静态网站"
        case .viteVue: return "Vite + Vue"
        case .nextJS: return "Next.js"
        }
    }

    var defaultFiles: [String: String] {
        switch self {
        case .empty: return [:]
        case .swiftPackage:
            return [
                "Package.swift": "// swift-tools-version: 6.0\nimport PackageDescription\n\nlet package = Package(\n    name: \"MyPackage\",\n    products: [\n        .library(name: \"MyPackage\", targets: [\"MyPackage\"])\n    ],\n    targets: [\n        .target(name: \"MyPackage\"),\n        .testTarget(name: \"MyPackageTests\", dependencies: [\"MyPackage\"])\n    ]\n)",
                "Sources/MyPackage/MyPackage.swift": "public struct MyPackage {\n    public init() {}\n    public func hello() -> String { \"Hello, World!\" }\n}",
                "Tests/MyPackageTests/MyPackageTests.swift": "import Testing\nimport MyPackage\n\n@Test func testHello() {\n    #expect(MyPackage().hello() == \"Hello, World!\")\n}"
            ]
        case .htmlSite:
            return [
                "index.html": "<!DOCTYPE html>\n<html lang=\"zh-CN\">\n<head>\n    <meta charset=\"UTF-8\">\n    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n    <title>My Site</title>\n    <link rel=\"stylesheet\" href=\"style.css\">\n</head>\n<body>\n    <h1>Welcome to My Site</h1>\n    <script src=\"script.js\"></script>\n</body>\n</html>",
                "style.css": "body { font-family: -apple-system, sans-serif; max-width: 800px; margin: 2rem auto; padding: 0 1rem; }",
                "script.js": "console.log('Site loaded');"
            ]
        case .pythonScript:
            return ["main.py": "#!/usr/bin/env python3\nprint('Hello, World!')"]
        case .viteVue, .nextJS, .reactNative:
            return ["package.json": "{\n  \"name\": \"my-app\",\n  \"version\": \"1.0.0\",\n  \"private\": true\n}"]
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

// MARK: - File Metadata (for indexing)

struct FileMetadata: Codable, FetchableRecord, MutablePersistableRecord {
    var id: UUID
    var projectID: UUID
    var path: String
    var isDirectory: Bool
    var size: Int64?
    var modifiedAt: Date

    static let databaseTableName = "file_metadata"

    enum Columns: String, ColumnExpression {
        case id, projectID, path, isDirectory, size, modifiedAt
    }

    init(id: UUID = UUID(), projectID: UUID, path: String, isDirectory: Bool, size: Int64? = nil, modifiedAt: Date = Date()) {
        self.id = id
        self.projectID = projectID
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.modifiedAt = modifiedAt
    }
}