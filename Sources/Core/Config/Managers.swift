import Foundation
import Combine

// MARK: - Config Manager

@MainActor
final class ConfigManager: ObservableObject {
    static let shared = ConfigManager()

    @Published private(set) var configs: [APIConfig] = []
    @Published private(set) var activeConfig: APIConfig?

    private let repository: ConfigRepository
    private let keychain = KeychainService.shared

    private init() {
        self.repository = ConfigRepository(db: DatabaseManager.shared)
    }

    func load() async {
        do {
            configs = try await repository.getAll()
            activeConfig = try await repository.getActive()
        } catch {
            print("Failed to load configs: \(error)")
        }
    }

    func addConfig(name: String, baseURL: String, apiKey: String, model: String, customHeaders: [String: String]? = nil) async throws -> APIConfig {
        let keychainRef = "\(await keychain.serviceName).\(UUID().uuidString)"
        try await keychain.saveAPIKey(apiKey, for: UUID(uuidString: keychainRef.components(separatedBy: ".").last!)!)

        var config = APIConfig(
            name: name,
            baseURL: baseURL,
            keychainKeyRef: keychainRef,
            model: model,
            customHeaders: customHeaders,
            isActive: configs.isEmpty
        )

        try await repository.save(config)

        if config.isActive {
            activeConfig = config
        }
        configs.append(config)
        return config
    }

    func updateConfig(_ config: APIConfig) async throws {
        try await repository.save(config)
        if let index = configs.firstIndex(where: { $0.id == config.id }) {
            configs[index] = config
        }
        if config.isActive {
            activeConfig = config
        }
    }

    func deleteConfig(id: UUID) async throws {
        try await keychain.deleteAPIKey(for: id)
        try await repository.delete(id: id)
        configs.removeAll { $0.id == id }
        if activeConfig?.id == id {
            activeConfig = configs.first
            if let newActive = activeConfig {
                try await setActive(newActive.id)
            }
        }
    }

    func setActive(_ id: UUID) async throws {
        try await repository.setActive(id: id)
        activeConfig = configs.first { $0.id == id }
        for i in configs.indices {
            configs[i].isActive = configs[i].id == id
        }
    }

    func testConnection(_ config: APIConfig) async -> Bool {
        do {
            let apiKey = try await keychain.getAPIKey(for: config.id) ?? ""
            let headers = ["Authorization": "Bearer \(apiKey)", "Content-Type": "application/json"]
            let request = ChatCompletionRequest(
                model: config.model,
                messages: [ChatMessage(role: "user", content: "ping")],
                temperature: 0.1,
                topP: 1.0,
                maxTokens: 10,
                stream: false,
                tools: nil,
                toolChoice: .none
            )
            let _: ChatCompletionResponse = try await HTTPClient.shared.request(
                endpoint: "\(config.baseURL)/chat/completions",
                headers: headers,
                body: request
            )
            return true
        } catch {
            return false
        }
    }

    func getKeychainRef(for config: APIConfig) -> String {
        config.keychainKeyRef
    }
}

// MARK: - Role Manager

@MainActor
final class RoleManager: ObservableObject {
    static let shared = RoleManager()

    @Published private(set) var builtInRoles: [Role] = []
    @Published private(set) var customRoles: [Role] = []

    private let repository: RoleRepository

    private init() {
        self.repository = RoleRepository(db: DatabaseManager.shared)
    }

    func load() async {
        do {
            try await repository.initializeBuiltInRoles()
            builtInRoles = try await repository.getBuiltIn()
            customRoles = try await repository.getCustom()
        } catch {
            print("Failed to load roles: \(error)")
        }
    }

    func allRoles() -> [Role] {
        builtInRoles + customRoles
    }

    func getRole(id: UUID) -> Role? {
        allRoles().first { $0.id == id }
    }

    func saveRole(_ role: Role) async throws {
        try await repository.save(role)
        if role.isBuiltIn {
            if let index = builtInRoles.firstIndex(where: { $0.id == role.id }) {
                builtInRoles[index] = role
            } else {
                builtInRoles.append(role)
            }
        } else {
            if let index = customRoles.firstIndex(where: { $0.id == role.id }) {
                customRoles[index] = role
            } else {
                customRoles.append(role)
            }
        }
    }

    func deleteRole(id: UUID) async throws {
        try await repository.delete(id: id)
        customRoles.removeAll { $0.id == id }
    }

    func exportRoles() async throws -> Data {
        try await repository.exportRoles(customRoles)
    }

    func importRoles(from data: Data) async throws {
        let roles = try await repository.importRoles(from: data)
        customRoles.append(contentsOf: roles)
    }
}

// MARK: - Parameter Manager

@MainActor
final class ParameterManager: ObservableObject {
    static let shared = ParameterManager()

    @Published var parameters: AIParameters = AIParameters() {
        didSet { saveParameters() }
    }

    @Published private(set) var presets: [ParameterPreset] = ParameterPreset.builtInPresets

    private let settingsKey = "ai_parameters"

    private init() {
        loadParameters()
    }

    func loadParameters() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let params = try? JSONDecoder().decode(AIParameters.self, from: data) {
            parameters = params
        }
    }

    func saveParameters() {
        if let data = try? JSONEncoder().encode(parameters) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    func applyPreset(_ preset: ParameterPreset) {
        parameters = preset.parameters
    }

    func addPreset(_ preset: ParameterPreset) {
        presets.append(preset)
        savePresets()
    }

    func deletePreset(id: UUID) {
        presets.removeAll { $0.id == id }
        savePresets()
    }

    func updatePreset(_ preset: ParameterPreset) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
            savePresets()
        }
    }

    private func savePresets() {
        if let data = try? JSONEncoder().encode(presets.filter { !$0.isBuiltIn }) {
            UserDefaults.standard.set(data, forKey: "parameter_presets")
        }
    }

    func estimateTokens(for params: AIParameters? = nil) -> (estimatedTokens: Int, estimatedTime: Double) {
        let p = params ?? parameters
        let baseTokens = p.maxTokens
        let multiplier = p.thinkingDuration.estimatedMultiplier
        let intensityFactor = 1.0 + Double(p.thinkingIntensity) / 100.0 * 0.5

        let estimatedTokens = Int(Double(baseTokens) * multiplier * intensityFactor)
        let estimatedTime = Double(estimatedTokens) / 1000.0 * multiplier // rough estimate

        return (estimatedTokens, estimatedTime)
    }
}

struct ParameterPreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var description: String
    var parameters: AIParameters
    var isBuiltIn: Bool

    init(id: UUID = UUID(), name: String, description: String, parameters: AIParameters, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.description = description
        self.parameters = parameters
        self.isBuiltIn = isBuiltIn
    }

    static let builtInPresets: [ParameterPreset] = [
        ParameterPreset(
            name: "快速编码",
            description: "适合简单的代码生成、补全、重构任务",
            parameters: AIParameters(
                thinkingDuration: .fast,
                thinkingIntensity: 30,
                reasoningMode: .code,
                maxTokens: 4096,
                temperature: 0.2,
                topP: 0.9
            ),
            isBuiltIn: true
        ),
        ParameterPreset(
            name: "深度架构设计",
            description: "适合系统设计、架构决策、复杂问题分析",
            parameters: AIParameters(
                thinkingDuration: .deep,
                thinkingIntensity: 90,
                reasoningMode: .deep,
                maxTokens: 16384,
                temperature: 0.4,
                topP: 0.95
            ),
            isBuiltIn: true
        ),
        ParameterPreset(
            name: "调试排查",
            description: "适合错误分析、性能优化、代码审查",
            parameters: AIParameters(
                thinkingDuration: .balanced,
                thinkingIntensity: 70,
                reasoningMode: .code,
                maxTokens: 8192,
                temperature: 0.3,
                topP: 0.9
            ),
            isBuiltIn: true
        ),
        ParameterPreset(
            name: "代码审查",
            description: "适合 PR 审查、最佳实践检查、安全审计",
            parameters: AIParameters(
                thinkingDuration: .balanced,
                thinkingIntensity: 80,
                reasoningMode: .deep,
                maxTokens: 8192,
                temperature: 0.2,
                topP: 0.85
            ),
            isBuiltIn: true
        )
    ]
}

// MARK: - Project Manager

@MainActor
final class ProjectManager: ObservableObject {
    static let shared = ProjectManager()

    @Published private(set) var projects: [Project] = []
    @Published var currentProject: Project?

    private let repository: ProjectRepository
    private let fileSystem = FileSystemService.shared

    private init() {
        self.repository = ProjectRepository(db: DatabaseManager.shared)
    }

    func load() async {
        do {
            projects = try await repository.getAll()
            if let first = projects.first {
                currentProject = first
            }
        } catch {
            print("Failed to load projects: \(error)")
        }
    }

    func createProject(name: String, template: ProjectTemplate?) async throws -> Project {
        let (projectURL, rootPath) = try await fileSystem.createProjectDirectory(name: name, template: template)

        var project = Project(name: name, rootPath: rootPath, template: template)
        try await repository.create(project)

        projects.insert(project, at: 0)
        currentProject = project
        return project
    }

    func openProject(_ project: Project) async throws {
        currentProject = project
        try await repository.updateLastOpened(id: project.id)
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index].lastOpenedAt = Date()
        }
    }

    func deleteProject(_ project: Project) async throws {
        try await fileSystem.deleteProjectDirectory(project.rootPath)
        try await repository.delete(id: project.id)
        projects.removeAll { $0.id == project.id }
        if currentProject?.id == project.id {
            currentProject = projects.first
        }
    }

    func updateProject(_ project: Project) async throws {
        try await repository.update(project)
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        }
    }

    func getFileTree() async throws -> FileNode? {
        guard let project = currentProject else { return nil }
        return try await fileSystem.buildFileTree(project: project)
    }

    func readFile(path: String) async throws -> String {
        guard let project = currentProject else { throw ProjectError.noCurrentProject }
        return try await fileSystem.readFile(project: project, path: path)
    }

    func writeFile(path: String, content: String) async throws {
        guard let project = currentProject else { throw ProjectError.noCurrentProject }
        try await fileSystem.writeFile(project: project, path: path, content: content)
    }

    func createFile(path: String, content: String? = nil) async throws {
        guard let project = currentProject else { throw ProjectError.noCurrentProject }
        try await fileSystem.createFile(project: project, path: path, content: content)
    }

    func deleteFile(path: String) async throws {
        guard let project = currentProject else { throw ProjectError.noCurrentProject }
        try await fileSystem.deleteFile(project: project, path: path)
    }

    func moveFile(from: String, to: String) async throws {
        guard let project = currentProject else { throw ProjectError.noCurrentProject }
        try await fileSystem.moveFile(project: project, from: from, to: to)
    }

    func exportProject(_ project: Project, to url: URL) async throws {
        try await fileSystem.exportProject(project: project, to: url)
    }

    func importProject(from url: URL, name: String) async throws -> Project {
        let (_, rootPath) = try await fileSystem.importProject(from: url, projectName: name)
        var project = Project(name: name, rootPath: rootPath)
        try await repository.create(project)
        projects.insert(project, at: 0)
        currentProject = project
        return project
    }
}

enum ProjectError: LocalizedError {
    case noCurrentProject
    case projectNotFound

    var errorDescription: String? {
        switch self {
        case .noCurrentProject: return "没有当前打开的项目"
        case .projectNotFound: return "项目不存在"
        }
    }
}