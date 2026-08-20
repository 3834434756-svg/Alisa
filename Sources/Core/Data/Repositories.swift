import Foundation

// MARK: - Config Repository

struct ConfigRepository {
    let db: DatabaseManager

    func save(_ config: APIConfig) async throws {
        try await db.saveConfig(config)
    }

    func getAll() async throws -> [APIConfig] {
        try await db.getAllConfigs()
    }

    func get(id: UUID) async throws -> APIConfig? {
        try await db.getAllConfigs().first { $0.id == id }
    }

    func getActive() async throws -> APIConfig? {
        try await db.getActiveConfig()
    }

    func delete(id: UUID) async throws {
        try await db.deleteConfig(id: id)
    }

    func setActive(id: UUID) async throws {
        try await db.setActiveConfig(id: id)
    }
}

// MARK: - Role Repository

struct RoleRepository {
    let db: DatabaseManager

    func save(_ role: Role) async throws {
        try await db.saveRole(role)
    }

    func getAll() async throws -> [Role] {
        try await db.getAllRoles()
    }

    func getBuiltIn() async throws -> [Role] {
        try await db.getBuiltInRoles()
    }

    func getCustom() async throws -> [Role] {
        try await db.getCustomRoles()
    }

    func get(id: UUID) async throws -> Role? {
        try await db.getAllRoles().first { $0.id == id }
    }

    func delete(id: UUID) async throws {
        try await db.deleteRole(id: id)
    }

    func initializeBuiltInRoles() async throws {
        try await db.initializeBuiltInRoles()
    }

    func exportRoles(_ roles: [Role]) async throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(roles)
    }

    func importRoles(from data: Data) async throws -> [Role] {
        let decoder = JSONDecoder()
        var roles = try decoder.decode([Role].self, from: data)
        for i in roles.indices {
            roles[i].id = UUID()
            roles[i].isBuiltIn = false
        }
        for role in roles {
            try await db.saveRole(role)
        }
        return roles
    }
}

// MARK: - Session Repository

struct SessionRepository {
    let db: DatabaseManager

    func create(projectID: UUID?, roleID: UUID, title: String = "新会话") async throws -> Session {
        let session = Session(projectID: projectID, roleID: roleID, title: title)
        try await db.createSession(session)
        return session
    }

    func getAll(projectID: UUID? = nil) async throws -> [Session] {
        try await db.getAllSessions(projectID: projectID)
    }

    func get(id: UUID) async throws -> Session? {
        let sessions = try await db.getAllSessions()
        return sessions.first { $0.id == id }
    }

    func update(_ session: Session) async throws {
        var s = session
        s.updatedAt = Date()
        try await db.updateSession(s)
    }

    func archive(id: UUID) async throws {
        guard var session = try await get(id: id) else { return }
        session.isArchived = true
        session.updatedAt = Date()
        try await db.updateSession(session)
    }

    func delete(id: UUID) async throws {
        try await db.deleteSession(id: id)
    }

    func appendMessage(_ message: Message, to sessionID: UUID) async throws {
        try await db.appendMessage(message)
    }
}

// MARK: - Message Repository

struct MessageRepository {
    let db: DatabaseManager

    func getAll(sessionID: UUID) async throws -> [Message] {
        try await db.getMessages(sessionID: sessionID)
    }

    func save(_ message: Message) async throws {
        try await db.appendMessage(message)
    }
}

// MARK: - Project Repository

struct ProjectRepository {
    let db: DatabaseManager

    func create(_ project: Project) async throws {
        try await db.saveProject(project)
    }

    func getAll() async throws -> [Project] {
        try await db.getAllProjects()
    }

    func get(id: UUID) async throws -> Project? {
        try await db.getAllProjects().first { $0.id == id }
    }

    func update(_ project: Project) async throws {
        var p = project
        p.updatedAt = Date()
        p.lastOpenedAt = Date()
        try await db.saveProject(p)
    }

    func updateLastOpened(id: UUID) async throws {
        guard var project = try await get(id: id) else { return }
        project.lastOpenedAt = Date()
        try await db.saveProject(project)
    }

    func delete(id: UUID) async throws {
        try await db.deleteProject(id: id)
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

    var projectsDir: URL { projectsDirectory }

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

    func writeFile(project: Project, path: String, content: String) async throws {
        let fileURL = projectURL(for: project).appendingPathComponent(path)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
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
        try buildNode(for: projectURL(for: project), projectRoot: projectURL(for: project))
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
        try FileManager.default.copyItem(at: projectURL, to: destinationURL)
    }

    func importProject(from sourceURL: URL, projectName: String) async throws -> (URL, String) {
        let (projectURL, uniqueName) = try await createProjectDirectory(name: projectName, template: nil)
        let contents = try FileManager.default.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil)
        for item in contents {
            let dest = projectURL.appendingPathComponent(item.lastPathComponent)
            try FileManager.default.copyItem(at: item, to: dest)
        }
        return (projectURL, uniqueName)
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

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): return "文件不存在: \(path)"
        case .permissionDenied: return "权限不足"
        }
    }
}