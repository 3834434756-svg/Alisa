import Foundation

actor DatabaseManager {
    static let shared = DatabaseManager()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var dbURL: URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsURL.appendingPathComponent("alisa_data.json")
    }

    private func loadAll() -> DataStore {
        guard let data = try? Data(contentsOf: dbURL),
              let store = try? decoder.decode(DataStore.self, from: data) else {
            return DataStore()
        }
        return store
    }

    private func saveAll(_ store: DataStore) throws {
        let data = try encoder.encode(store)
        try data.write(to: dbURL, options: .atomic)
    }

    // MARK: - API Configs

    func saveConfig(_ config: APIConfig) async throws {
        var store = loadAll()
        store.apiConfigs.removeAll { $0.id == config.id }
        store.apiConfigs.append(config)
        try saveAll(store)
    }

    func getAllConfigs() async throws -> [APIConfig] {
        loadAll().apiConfigs
    }

    func getActiveConfig() async throws -> APIConfig? {
        loadAll().apiConfigs.first { $0.isActive }
    }

    func deleteConfig(id: UUID) async throws {
        var store = loadAll()
        store.apiConfigs.removeAll { $0.id == id }
        try saveAll(store)
    }

    func setActiveConfig(id: UUID) async throws {
        var store = loadAll()
        for i in store.apiConfigs.indices {
            store.apiConfigs[i].isActive = store.apiConfigs[i].id == id
        }
        try saveAll(store)
    }

    // MARK: - Roles

    func saveRole(_ role: Role) async throws {
        var store = loadAll()
        store.roles.removeAll { $0.id == role.id }
        store.roles.append(role)
        try saveAll(store)
    }

    func getAllRoles() async throws -> [Role] {
        loadAll().roles
    }

    func getBuiltInRoles() async throws -> [Role] {
        loadAll().roles.filter { $0.isBuiltIn }
    }

    func getCustomRoles() async throws -> [Role] {
        loadAll().roles.filter { !$0.isBuiltIn }
    }

    func deleteRole(id: UUID) async throws {
        var store = loadAll()
        store.roles.removeAll { $0.id == id }
        try saveAll(store)
    }

    // MARK: - Sessions

    func createSession(_ session: Session) async throws {
        var store = loadAll()
        store.sessions.append(session)
        try saveAll(store)
    }

    func getAllSessions(projectID: UUID? = nil) async throws -> [Session] {
        let store = loadAll()
        if let projectID = projectID {
            return store.sessions.filter { $0.projectID == projectID && !$0.isArchived }
        }
        return store.sessions.filter { !$0.isArchived }
    }

    func updateSession(_ session: Session) async throws {
        var store = loadAll()
        if let index = store.sessions.firstIndex(where: { $0.id == session.id }) {
            store.sessions[index] = session
        }
        try saveAll(store)
    }

    func deleteSession(id: UUID) async throws {
        var store = loadAll()
        store.sessions.removeAll { $0.id == id }
        store.messages.removeAll { $0.sessionID == id }
        try saveAll(store)
    }

    // MARK: - Messages

    func appendMessage(_ message: Message) async throws {
        var store = loadAll()
        store.messages.append(message)
        if let index = store.sessions.firstIndex(where: { $0.id == message.sessionID }) {
            store.sessions[index].messageCount += 1
            store.sessions[index].totalTokens += message.tokenCount
            store.sessions[index].updatedAt = Date()
        }
        try saveAll(store)
    }

    func getMessages(sessionID: UUID) async throws -> [Message] {
        loadAll().messages.filter { $0.sessionID == sessionID }.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Projects

    func saveProject(_ project: Project) async throws {
        var store = loadAll()
        store.projects.removeAll { $0.id == project.id }
        store.projects.append(project)
        try saveAll(store)
    }

    func getAllProjects() async throws -> [Project] {
        loadAll().projects
    }

    func deleteProject(id: UUID) async throws {
        var store = loadAll()
        store.projects.removeAll { $0.id == id }
        try saveAll(store)
    }

    // MARK: - Initialize Built-in Roles

    func initializeBuiltInRoles() async throws {
        var store = loadAll()
        if !store.roles.contains(where: { $0.isBuiltIn }) {
            let alisa = Role(
                name: "Alisa",
                systemPrompt: """
                你是 Alisa，一名资深程序工程师。你的专长包括：
                - 现代 iOS/macOS 开发（Swift、SwiftUI、Combine、Swift Concurrency）
                - 后端架构设计（微服务、数据库设计、API 设计、缓存策略）
                - 前端工程化（TypeScript、React、Vue、构建工具、性能优化）
                - 算法与数据结构、系统设计、代码审查最佳实践

                回答风格：专业、简洁、实用。优先提供可直接运行的代码方案。
                """,
                specialties: ["iOS开发", "架构设计", "代码审查", "性能优化"],
                defaultParameters: AIParameters(),
                isBuiltIn: true
            )
            store.roles.insert(alisa, at: 0)
            try saveAll(store)
        }
    }
}

struct DataStore: Codable {
    var apiConfigs: [APIConfig] = []
    var roles: [Role] = []
    var sessions: [Session] = []
    var messages: [Message] = []
    var projects: [Project] = []
}