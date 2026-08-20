import Foundation

actor BackupManager {
    static let shared = BackupManager()

    private let fileSystem = FileSystemService.shared
    private let db = DatabaseManager.shared

    private init() {}

    // MARK: - Backup

    func createBackup(projectIDs: [UUID]? = nil, password: String? = nil) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AlisaBackup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let data = try await db.getAllProjects()
        let metadataURL = tempDir.appendingPathComponent("projects.json")
        try JSONEncoder().encode(data).write(to: metadataURL)

        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let backupURL = documentsURL.appendingPathComponent("Alisa-Backup-\(Date().ISO8601Format()).json")
        let backupData = try await createBackupData(projectIDs: projectIDs)
        try backupData.write(to: backupURL)

        return backupURL
    }

    private func createBackupData(projectIDs: [UUID]?) async throws -> Data {
        let projects = try await db.getAllProjects()
        let sessions = try await db.getAllSessions()
        let configs = try await db.getAllConfigs()
        let roles = try await db.getAllRoles()

        let backup: [String: Any] = [
            "version": 1,
            "createdAt": Date().timeIntervalSince1970,
            "projects": projects.map { try? JSONEncoder().encode($0).base64EncodedString() ?? "" },
            "sessions": sessions.map { try? JSONEncoder().encode($0).base64EncodedString() ?? "" },
            "configs": configs.map { try? JSONEncoder().encode($0).base64EncodedString() ?? "" },
            "roles": roles.map { try? JSONEncoder().encode($0).base64EncodedString() ?? "" }
        ]

        return try JSONSerialization.data(withJSONObject: backup, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: - Restore

    func restoreFromBackup(url: URL) async throws {
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BackupError.invalidFormat
        }

        let version = json["version"] as? Int ?? 0
        guard version == 1 else {
            throw BackupError.unsupportedVersion(version)
        }

        // Restore roles first (no dependencies)
        if let rolesData = json["roles"] as? [String] {
            for roleBase64 in rolesData {
                if let data = Data(base64Encoded: roleBase64),
                   let role = try? JSONDecoder().decode(Role.self, from: data) {
                    try? await db.saveRole(role)
                }
            }
        }

        // Restore configs
        if let configsData = json["configs"] as? [String] {
            for configBase64 in configsData {
                if let data = Data(base64Encoded: configBase64),
                   let config = try? JSONDecoder().decode(APIConfig.self, from: data) {
                    try? await db.saveConfig(config)
                }
            }
        }

        // Restore projects
        if let projectsData = json["projects"] as? [String] {
            for projectBase64 in projectsData {
                if let data = Data(base64Encoded: projectBase64),
                   let project = try? JSONDecoder().decode(Project.self, from: data) {
                    try? await db.saveProject(project)
                }
            }
        }

        // Restore sessions
        if let sessionsData = json["sessions"] as? [String] {
            for sessionBase64 in sessionsData {
                if let data = Data(base64Encoded: sessionBase64),
                   let session = try? JSONDecoder().decode(Session.self, from: data) {
                    try? await db.saveSession(session)
                }
            }
        }
    }
}

// MARK: - Backup Error

enum BackupError: LocalizedError {
    case invalidFormat
    case unsupportedVersion(Int)
    case restoreFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "备份文件格式无效"
        case .unsupportedVersion(let version):
            return "不支持的备份版本: \(version)"
        case .restoreFailed(let reason):
            return "恢复失败: \(reason)"
        }
    }
}