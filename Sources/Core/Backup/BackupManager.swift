import Foundation

actor BackupManager {
    static let shared = BackupManager()

    private let fileSystem = FileSystemService.shared
    private let db = DatabaseManager.shared

    private init() {}

    func createBackup(projectIDs: [UUID]? = nil, password: String? = nil, progress: @escaping (Double) -> Void) async throws -> URL {
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

        progress(1.0)
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
}