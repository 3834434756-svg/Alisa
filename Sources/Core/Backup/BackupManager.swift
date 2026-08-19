import Foundation
import CryptoKit

// MARK: - Backup Manager

actor BackupManager {
    static let shared = BackupManager()

    private let fileSystem = FileSystemService.shared
    private let db = DatabaseManager.shared

    private init() {}

    // MARK: - Create Backup

    func createBackup(
        projectIDs: [UUID]? = nil,
        includeSessions: Bool = true,
        includeConfigs: Bool = true,
        password: String? = nil,
        progress: @escaping (Double) -> Void
    ) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AlisaBackup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projects = try await getProjectsToBackup(projectIDs)
        let totalSteps = projects.count + (includeSessions ? 1 : 0) + (includeConfigs ? 1 : 0)
        var completedSteps = 0

        // Export projects
        for (index, project) in projects.enumerated() {
            let projectBackupDir = tempDir.appendingPathComponent("projects/\(project.id.uuidString)")
            try FileManager.default.createDirectory(at: projectBackupDir, withIntermediateDirectories: true)

            // Copy project files
            let projectURL = await fileSystem.projectURL(for: project)
            let destURL = projectBackupDir.appendingPathComponent("files")
            try FileManager.default.copyItem(at: projectURL, to: destURL)

            // Export project metadata
            let metadata = ProjectBackupMetadata(
                id: project.id,
                name: project.name,
                rootPath: project.rootPath,
                template: project.template,
                lastOpenedAt: project.lastOpenedAt,
                createdAt: project.createdAt,
                updatedAt: project.updatedAt
            )
            let metadataURL = projectBackupDir.appendingPathComponent("metadata.json")
            try JSONEncoder().encode(metadata).write(to: metadataURL)

            completedSteps += 1
            progress(Double(completedSteps) / Double(totalSteps))
        }

        // Export sessions
        if includeSessions {
            let sessions = try await getAllSessions()
            let sessionsURL = tempDir.appendingPathComponent("sessions.json")
            try JSONEncoder().encode(sessions).write(to: sessionsURL)
            completedSteps += 1
            progress(Double(completedSteps) / Double(totalSteps))
        }

        // Export configs
        if includeConfigs {
            let configs = try await getAllConfigs()
            let configsURL = tempDir.appendingPathComponent("configs.json")
            try JSONEncoder().encode(configs).write(to: configsURL)
            completedSteps += 1
            progress(Double(completedSteps) / Double(totalSteps))
        }

        // Create manifest
        let manifest = BackupManifest(
            version: 1,
            createdAt: Date(),
            projectCount: projects.count,
            includesSessions: includeSessions,
            includesConfigs: includeConfigs,
            isEncrypted: password != nil
        )
        let manifestURL = tempDir.appendingPathComponent("manifest.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL)

        // Create ZIP
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let backupURL = documentsURL.appendingPathComponent("Alisa-Backup-\(Date().ISO8601Format()).zip")

        try ZIPFoundation.zipItem(at: tempDir, to: backupURL, shouldKeepParent: false, compressionMethod: .deflate) { progress in
            // ZIP progress
        }

        // Encrypt if password provided
        if let password = password {
            try await encryptBackup(at: backupURL, password: password)
        }

        progress(1.0)
        return backupURL
    }

    // MARK: - Restore Backup

    func restoreBackup(
        from url: URL,
        password: String? = nil,
        progress: @escaping (Double) -> Void
    ) async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AlisaRestore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer { try? FileManager.default.removeItem(at: tempDir) }

        var workingURL = url

        // Decrypt if needed
        if let password = password {
            let decryptedURL = tempDir.appendingPathComponent("backup.zip")
            try await decryptBackup(from: url, to: decryptedURL, password: password)
            workingURL = decryptedURL
        }

        progress(0.1)

        // Unzip
        try ZIPFoundation.unzipItem(at: workingURL, to: tempDir)
        progress(0.3)

        // Read manifest
        let manifestURL = tempDir.appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(BackupManifest.self, from: manifestData)

        // Restore projects
        let projectsDir = tempDir.appendingPathComponent("projects")
        if FileManager.default.fileExists(atPath: projectsDir.path) {
            let projectDirs = try FileManager.default.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil)
            let totalProjects = projectDirs.count

            for (index, projectDir) in projectDirs.enumerated() {
                let metadataURL = projectDir.appendingPathComponent("metadata.json")
                let metadata = try JSONDecoder().decode(ProjectBackupMetadata.self, from: Data(contentsOf: metadataURL))

                let filesDir = projectDir.appendingPathComponent("files")
                let destURL = await fileSystem.projectsDirectory.appendingPathComponent(metadata.rootPath)

                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.copyItem(at: filesDir, to: destURL)

                var project = Project(
                    id: metadata.id,
                    name: metadata.name,
                    rootPath: metadata.rootPath,
                    template: metadata.template
                )
                project.lastOpenedAt = metadata.lastOpenedAt
                project.createdAt = metadata.createdAt
                project.updatedAt = metadata.updatedAt

                try await db.writer.write { db in
                    try project.save(db)
                }

                progress(0.3 + 0.5 * Double(index + 1) / Double(totalProjects))
            }
        }

        // Restore sessions
        if manifest.includesSessions {
            let sessionsURL = tempDir.appendingPathComponent("sessions.json")
            if FileManager.default.fileExists(atPath: sessionsURL.path) {
                let sessions = try JSONDecoder().decode([Session].self, from: Data(contentsOf: sessionsURL))
                try await db.writer.write { db in
                    for session in sessions {
                        try session.save(db)
                    }
                }
            }
            progress(0.8)
        }

        // Restore configs
        if manifest.includesConfigs {
            let configsURL = tempDir.appendingPathComponent("configs.json")
            if FileManager.default.fileExists(atPath: configsURL.path) {
                let configs = try JSONDecoder().decode([APIConfig].self, from: Data(contentsOf: configsURL))
                try await db.writer.write { db in
                    for config in configs {
                        try config.save(db)
                    }
                }
            }
            progress(0.9)
        }

        progress(1.0)
    }

    // MARK: - Encryption

    private func encryptBackup(at url: URL, password: String) async throws {
        let data = try Data(contentsOf: url)
        let key = deriveKey(from: password)
        let sealedBox = try AES.GCM.seal(data, using: key)
        let encryptedData = sealedBox.combined!
        try encryptedData.write(to: url)
    }

    private func decryptBackup(from url: URL, to destinationURL: URL, password: String) async throws {
        let encryptedData = try Data(contentsOf: url)
        let key = deriveKey(from: password)
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        try decryptedData.write(to: destinationURL)
    }

    private func deriveKey(from password: String) -> SymmetricKey {
        let passwordData = password.data(using: .utf8)!
        let salt = "AlisaBackupSalt".data(using: .utf8)!
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: passwordData),
            salt: salt,
            info: Data(),
            outputByteCount: 32
        )
        return key
    }

    // MARK: - Helpers

    private func getProjectsToBackup(_ ids: [UUID]?) async throws -> [Project] {
        try await db.reader.read { db in
            if let ids = ids {
                return try Project.filter(ids.map { $0.uuidString }.contains(Column("id"))).fetchAll(db)
            } else {
                return try Project.fetchAll(db)
            }
        }
    }

    private func getAllSessions() async throws -> [Session] {
        try await db.reader.read { db in
            try Session.fetchAll(db)
        }
    }

    private func getAllConfigs() async throws -> [APIConfig] {
        try await db.reader.read { db in
            try APIConfig.fetchAll(db)
        }
    }
}

// MARK: - Backup Models

struct BackupManifest: Codable {
    let version: Int
    let createdAt: Date
    let projectCount: Int
    let includesSessions: Bool
    let includesConfigs: Bool
    let isEncrypted: Bool
}

struct ProjectBackupMetadata: Codable {
    let id: UUID
    let name: String
    let rootPath: String
    let template: ProjectTemplate?
    let lastOpenedAt: Date
    let createdAt: Date
    let updatedAt: Date
}