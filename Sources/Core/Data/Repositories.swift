import Foundation
import GRDB

// MARK: - Config Repository

struct ConfigRepository {
    let db: DatabaseManager

    func save(_ config: APIConfig) async throws {
        try await db.writer.write { db in
            try config.save(db)
        }
    }

    func getAll() async throws -> [APIConfig] {
        try await db.reader.read { db in
            try APIConfig.fetchAll(db)
        }
    }

    func get(id: UUID) async throws -> APIConfig? {
        try await db.reader.read { db in
            try APIConfig.fetchOne(db, key: id.uuidString)
        }
    }

    func getActive() async throws -> APIConfig? {
        try await db.reader.read { db in
            try APIConfig.filter(Column("isActive") == true).fetchOne(db)
        }
    }

    func delete(id: UUID) async throws {
        try await db.writer.write { db in
            _ = try APIConfig.deleteOne(db, key: id.uuidString)
        }
    }

    func setActive(id: UUID) async throws {
        try await db.writer.write { db in
            try db.execute(sql: "UPDATE api_configs SET isActive = 0")
            var config = try APIConfig.fetchOne(db, key: id.uuidString)
            config?.isActive = true
            config?.updatedAt = Date()
            try config?.save(db)
        }
    }
}

// MARK: - Role Repository

struct RoleRepository {
    let db: DatabaseManager

    func save(_ role: Role) async throws {
        try await db.writer.write { db in
            try role.save(db)
        }
    }

    func getAll() async throws -> [Role] {
        try await db.reader.read { db in
            try Role.fetchAll(db, sql: "SELECT * FROM roles ORDER BY isBuiltIn DESC, name")
        }
    }

    func getBuiltIn() async throws -> [Role] {
        try await db.reader.read { db in
            try Role.filter(Column("isBuiltIn") == true).fetchAll(db)
        }
    }

    func getCustom() async throws -> [Role] {
        try await db.reader.read { db in
            try Role.filter(Column("isBuiltIn") == false).fetchAll(db)
        }
    }

    func get(id: UUID) async throws -> Role? {
        try await db.reader.read { db in
            try Role.fetchOne(db, key: id.uuidString)
        }
    }

    func delete(id: UUID) async throws {
        try await db.writer.write { db in
            let role = try Role.fetchOne(db, key: id.uuidString)
            guard let role = role, !role.isBuiltIn else {
                throw RepositoryError.cannotDeleteBuiltIn
            }
            _ = try Role.deleteOne(db, key: id.uuidString)
        }
    }

    func initializeBuiltInRoles() async throws {
        try await db.writer.write { db in
            let count = try Role.fetchCount(db)
            guard count == 0 else { return }

            let alisa = Role(
                name: "Alisa",
                systemPrompt: """
                你是 Alisa，一名资深程序工程师。你的专长包括：
                - 现代 iOS/macOS 开发（Swift、SwiftUI、Combine、Swift Concurrency）
                - 后端架构设计（微服务、数据库设计、API 设计、缓存策略）
                - 前端工程化（TypeScript、React、Vue、构建工具、性能优化）
                - 算法与数据结构、系统设计、代码审查最佳实践

                回答风格：专业、简洁、实用。优先提供可直接运行的代码方案。
                代码规范：遵循 Apple Swift API Design Guidelines、Clean Code 原则。
                """,
                specialties: ["iOS开发", "架构设计", "代码审查", "性能优化"],
                defaultParameters: AIParameters(
                    thinkingDuration: .balanced,
                    thinkingIntensity: 70,
                    reasoningMode: .code,
                    maxTokens: 8192,
                    temperature: 0.3,
                    topP: 0.95
                ),
                isBuiltIn: true
            )
            try alisa.save(db)
        }
    }

    func exportRoles(_ roles: [Role]) async throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(roles)
    }

    func importRoles(from data: Data) async throws -> [Role] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let roles = try decoder.decode([Role].self, from: data)

        try await db.writer.write { db in
            for var role in roles {
                role.id = UUID()
                role.isBuiltIn = false
                role.createdAt = Date()
                role.updatedAt = Date()
                try role.save(db)
            }
        }
        return roles
    }
}

enum RepositoryError: LocalizedError {
    case cannotDeleteBuiltIn
    case notFound
    case conflict

    var errorDescription: String? {
        switch self {
        case .cannotDeleteBuiltIn: return "内置角色不可删除"
        case .notFound: return "记录不存在"
        case .conflict: return "数据冲突"
        }
    }
}

// MARK: - Session Repository

struct SessionRepository {
    let db: DatabaseManager

    func create(projectID: UUID?, roleID: UUID, title: String = "新会话") async throws -> Session {
        var session = Session(projectID: projectID, roleID: roleID, title: title)
        try await db.writer.write { db in
            try session.save(db)
        }
        return session
    }

    func getAll(projectID: UUID? = nil) async throws -> [Session] {
        try await db.reader.read { db in
            let request: QueryInterfaceRequest<Session>
            if let projectID = projectID {
                request = Session.filter(Column("projectID") == projectID.uuidString)
            } else {
                request = Session.all()
            }
            return try request
                .filter(Column("isArchived") == false)
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    func getArchived(projectID: UUID? = nil) async throws -> [Session] {
        try await db.reader.read { db in
            let request: QueryInterfaceRequest<Session>
            if let projectID = projectID {
                request = Session.filter(Column("projectID") == projectID.uuidString)
            } else {
                request = Session.all()
            }
            return try request
                .filter(Column("isArchived") == true)
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    func get(id: UUID) async throws -> Session? {
        try await db.reader.read { db in
            try Session.fetchOne(db, key: id.uuidString)
        }
    }

    func update(_ session: Session) async throws {
        var session = session
        session.updatedAt = Date()
        try await db.writer.write { db in
            try session.save(db)
        }
    }

    func archive(id: UUID) async throws {
        try await db.writer.write { db in
            var session = try Session.fetchOne(db, key: id.uuidString)
            session?.isArchived = true
            session?.updatedAt = Date()
            try session?.save(db)
        }
    }

    func unarchive(id: UUID) async throws {
        try await db.writer.write { db in
            var session = try Session.fetchOne(db, key: id.uuidString)
            session?.isArchived = false
            session?.updatedAt = Date()
            try session?.save(db)
        }
    }

    func delete(id: UUID) async throws {
        try await db.writer.write { db in
            _ = try Session.deleteOne(db, key: id.uuidString)
        }
    }

    func appendMessage(_ message: Message, to sessionID: UUID) async throws {
        try await db.writer.write { db in
            try message.save(db)
            var session = try Session.fetchOne(db, key: sessionID.uuidString)
            session?.messageCount += 1
            session?.totalTokens += message.tokenCount
            session?.updatedAt = Date()
            try session?.save(db)
        }
    }

    func getContextWindow(sessionID: UUID, maxTokens: Int, systemPrompt: String?) async throws -> [Message] {
        try await db.reader.read { db in
            let messages = try Message
                .filter(Column("sessionID") == sessionID.uuidString)
                .order(Column("createdAt"))
                .fetchAll(db)

            var totalTokens = 0
            var result: [Message] = []

            if let systemPrompt = systemPrompt {
                totalTokens += estimateTokens(systemPrompt)
            }

            for message in messages.reversed() {
                if totalTokens + message.tokenCount > maxTokens { break }
                result.insert(message, at: 0)
                totalTokens += message.tokenCount
            }

            return result
        }
    }

    private func estimateTokens(_ text: String) -> Int {
        max(1, text.count / 3)
    }
}

// MARK: - Message Repository

struct MessageRepository {
    let db: DatabaseManager

    func save(_ message: Message) async throws {
        try await db.writer.write { db in
            try message.save(db)
        }
    }

    func getAll(sessionID: UUID) async throws -> [Message] {
        try await db.reader.read { db in
            try Message
                .filter(Column("sessionID") == sessionID.uuidString)
                .order(Column("createdAt"))
                .fetchAll(db)
        }
    }

    func getRecent(sessionID: UUID, limit: Int) async throws -> [Message] {
        try await db.reader.read { db in
            try Message
                .filter(Column("sessionID") == sessionID.uuidString)
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
                .reversed()
        }
    }

    func update(_ message: Message) async throws {
        try await db.writer.write { db in
            try message.save(db)
        }
    }

    func delete(sessionID: UUID) async throws {
        try await db.writer.write { db in
            try Message.filter(Column("sessionID") == sessionID.uuidString).deleteAll(db)
        }
    }
}

// MARK: - Project Repository

struct ProjectRepository {
    let db: DatabaseManager

    func create(_ project: Project) async throws {
        try await db.writer.write { db in
            try project.save(db)
        }
    }

    func getAll() async throws -> [Project] {
        try await db.reader.read { db in
            try Project.order(Column("lastOpenedAt").desc).fetchAll(db)
        }
    }

    func get(id: UUID) async throws -> Project? {
        try await db.reader.read { db in
            try Project.fetchOne(db, key: id.uuidString)
        }
    }

    func update(_ project: Project) async throws {
        var project = project
        project.updatedAt = Date()
        project.lastOpenedAt = Date()
        try await db.writer.write { db in
            try project.save(db)
        }
    }

    func updateLastOpened(id: UUID) async throws {
        try await db.writer.write { db in
            var project = try Project.fetchOne(db, key: id.uuidString)
            project?.lastOpenedAt = Date()
            project?.updatedAt = Date()
            try project?.save(db)
        }
    }

    func delete(id: UUID) async throws {
        try await db.writer.write { db in
            _ = try Project.deleteOne(db, key: id.uuidString)
        }
    }

    // File Metadata
    func saveFileMetadata(_ metadata: FileMetadata) async throws {
        try await db.writer.write { db in
            try metadata.save(db)
        }
    }

    func getFileMetadata(projectID: UUID) async throws -> [FileMetadata] {
        try await db.reader.read { db in
            try FileMetadata
                .filter(Column("projectID") == projectID.uuidString)
                .fetchAll(db)
        }
    }

    func deleteFileMetadata(projectID: UUID, path: String) async throws {
        try await db.writer.write { db in
            try FileMetadata
                .filter(Column("projectID") == projectID.uuidString && Column("path") == path)
                .deleteAll(db)
        }
    }

    func clearFileMetadata(projectID: UUID) async throws {
        try await db.writer.write { db in
            try FileMetadata.filter(Column("projectID") == projectID.uuidString).deleteAll(db)
        }
    }
}

// MARK: - File System Service

actor FileSystemService {
    static let shared = FileSystemService()

    private let projectsDirectory: URL

    private init() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        projectsDirectory = documentsURL.appendingPathComponent("Projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
    }

    func projectURL(for project: Project) -> URL {
        projectsDirectory.appendingPathComponent(project.rootPath, isDirectory: true)
    }

    func createProjectDirectory(name: String, template: ProjectTemplate?) async throws -> (URL, String) {
        let folderName = name.replacingOccurrences(of: "/", with: "-")
        let uniqueName = "\(folderName)-\(UUID().uuidString.prefix(8))"
        let projectURL = projectsDirectory.appendingPathComponent(uniqueName, isDirectory: true)

        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        if let template = template {
            for (path, content) in template.defaultFiles {
                let fileURL = projectURL.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }

        return (projectURL, uniqueName)
    }

    func readFile(project: Project, path: String) async throws -> String {
        let fileURL = projectURL(for: project).appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw FileSystemError.fileNotFound(path)
        }
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    func readFileData(project: Project, path: String) async throws -> Data {
        let fileURL = projectURL(for: project).appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw FileSystemError.fileNotFound(path)
        }
        return try Data(contentsOf: fileURL)
    }

    func writeFile(project: Project, path: String, content: String, encoding: String.Encoding = .utf8) async throws {
        let fileURL = projectURL(for: project).appendingPathComponent(path)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: fileURL, atomically: true, encoding: encoding)
    }

    func writeFileData(project: Project, path: String, data: Data) async throws {
        let fileURL = projectURL(for: project).appendingPathComponent(path)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    func createFile(project: Project, path: String, content: String? = nil) async throws {
        let fileURL = projectURL(for: project).appendingPathComponent(path)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: fileURL.path, contents: content?.data(using: .utf8))
    }

    func deleteFile(project: Project, path: String) async throws {
        let fileURL = projectURL(for: project).appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw FileSystemError.fileNotFound(path)
        }
        try FileManager.default.removeItem(at: fileURL)
    }

    func moveFile(project: Project, from: String, to: String) async throws {
        let fromURL = projectURL(for: project).appendingPathComponent(from)
        let toURL = projectURL(for: project).appendingPathComponent(to)
        guard FileManager.default.fileExists(atPath: fromURL.path) else {
            throw FileSystemError.fileNotFound(from)
        }
        try FileManager.default.createDirectory(at: toURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: fromURL, to: toURL)
    }

    func buildFileTree(project: Project) async throws -> FileNode {
        let projectURL = projectURL(for: project)
        return try buildNode(for: projectURL, projectRoot: projectURL)
    }

    private func buildNode(for url: URL, projectRoot: URL) throws -> FileNode {
        let relativePath = url.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
        let name = url.lastPathComponent
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        let size = isDirectory ? nil : (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init))

        var children: [FileNode]?
        if isDirectory {
            let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey])
            children = try contents.map { try buildNode(for: $0, projectRoot: projectRoot) }
                .sorted { ($0.isDirectory && !$1.isDirectory) || ($0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending) }
        }

        return FileNode(name: name, path: relativePath, isDirectory: isDirectory, children: children, modifiedAt: modifiedAt, size: size)
    }

    func exportProject(project: Project, to destinationURL: URL) async throws {
        let projectURL = projectURL(for: project)
        try ZIPFoundation.zipItem(at: projectURL, to: destinationURL, shouldKeepParent: false, compressionMethod: .deflate, progress: nil)
    }

    func importProject(from sourceURL: URL, projectName: String) async throws -> (URL, String) {
        let (projectURL, uniqueName) = try await createProjectDirectory(name: projectName, template: nil)
        try ZIPFoundation.unzipItem(at: sourceURL, to: projectURL)
        return (projectURL, uniqueName)
    }

    func listProjects() async -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: projectsDirectory, includingPropertiesForKeys: [.isDirectoryKey]).filter { $0.hasDirectoryPath }) ?? []
    }

    func deleteProjectDirectory(_ rootPath: String) async throws {
        let projectURL = projectsDirectory.appendingPathComponent(rootPath)
        guard FileManager.default.fileExists(atPath: projectURL.path) else { return }
        try FileManager.default.removeItem(at: projectURL)
    }
}

enum FileSystemError: LocalizedError {
    case fileNotFound(String)
    case permissionDenied
    case diskFull
    case invalidPath

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): return "文件不存在: \(path)"
        case .permissionDenied: return "权限不足，无法访问文件"
        case .diskFull: return "存储空间不足"
        case .invalidPath: return "无效的文件路径"
        }
    }
}