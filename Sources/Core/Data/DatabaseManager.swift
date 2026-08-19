import Foundation
import GRDB

actor DatabaseManager {
    static let shared = DatabaseManager()

    private var dbQueue: DatabaseQueue?
    private let databaseName = "alisa.sqlite"

    private init() {}

    func setup() async throws {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dbURL = documentsPath.appendingPathComponent(databaseName)

        let configuration = Configuration()
        configuration.prepareDatabase { db in
            db.trace { print("SQL: \($0)") }
        }

        dbQueue = try DatabaseQueue(path: dbURL.path, configuration: configuration)
        try await migrate()
    }

    var reader: DatabaseReader {
        guard let dbQueue else { fatalError("Database not initialized. Call setup() first.") }
        return dbQueue
    }

    var writer: DatabaseWriter {
        guard let dbQueue else { fatalError("Database not initialized. Call setup() first.") }
        return dbQueue
    }

    private func migrate() async throws {
        try await writer.write { db in
            var migrator = DatabaseMigrator()

            migrator.registerMigration("v1_create_tables") { db in
                try db.create(table: "api_configs") { t in
                    t.column("id", .text).primaryKey()
                    t.column("name", .text).notNull()
                    t.column("baseURL", .text).notNull()
                    t.column("keychainKeyRef", .text).notNull()
                    t.column("model", .text).notNull()
                    t.column("customHeaders", .text)
                    t.column("isActive", .boolean).notNull().defaults(to: false)
                    t.column("createdAt", .datetime).notNull()
                    t.column("updatedAt", .datetime).notNull()
                }

                try db.create(table: "roles") { t in
                    t.column("id", .text).primaryKey()
                    t.column("name", .text).notNull()
                    t.column("systemPrompt", .text).notNull()
                    t.column("specialties", .text).notNull()
                    t.column("defaultParametersData", .blob)
                    t.column("isBuiltIn", .boolean).notNull().defaults(to: false)
                    t.column("createdAt", .datetime).notNull()
                    t.column("updatedAt", .datetime).notNull()
                }

                try db.create(table: "sessions") { t in
                    t.column("id", .text).primaryKey()
                    t.column("projectID", .text)
                    t.column("roleID", .text).notNull()
                    t.column("title", .text).notNull()
                    t.column("messageCount", .integer).notNull().defaults(to: 0)
                    t.column("totalTokens", .integer).notNull().defaults(to: 0)
                    t.column("isArchived", .boolean).notNull().defaults(to: false)
                    t.column("createdAt", .datetime).notNull()
                    t.column("updatedAt", .datetime).notNull()
                    t.foreignKey(["roleID"], references: "roles", columns: ["id"], onDelete: .restrict)
                }

                try db.create(table: "messages") { t in
                    t.column("id", .text).primaryKey()
                    t.column("sessionID", .text).notNull()
                    t.column("role", .text).notNull()
                    t.column("content", .text).notNull()
                    t.column("codeBlocksData", .blob)
                    t.column("fileReferencesData", .blob)
                    t.column("toolCallsData", .blob)
                    t.column("toolResultsData", .blob)
                    t.column("tokenCount", .integer).notNull().defaults(to: 0)
                    t.column("status", .text).notNull()
                    t.column("createdAt", .datetime).notNull()
                    t.foreignKey(["sessionID"], references: "sessions", columns: ["id"], onDelete: .cascade)
                }
                try db.create(index: "idx_messages_session", on: "messages", columns: ["sessionID"])
                try db.create(index: "idx_messages_created", on: "messages", columns: ["createdAt"])

                try db.create(table: "projects") { t in
                    t.column("id", .text).primaryKey()
                    t.column("name", .text).notNull()
                    t.column("rootPath", .text).notNull()
                    t.column("template", .text)
                    t.column("lastOpenedAt", .datetime).notNull()
                    t.column("createdAt", .datetime).notNull()
                    t.column("updatedAt", .datetime).notNull()
                }

                try db.create(table: "file_metadata") { t in
                    t.column("id", .text).primaryKey()
                    t.column("projectID", .text).notNull()
                    t.column("path", .text).notNull()
                    t.column("isDirectory", .boolean).notNull()
                    t.column("size", .integer)
                    t.column("modifiedAt", .datetime).notNull()
                    t.foreignKey(["projectID"], references: "projects", columns: ["id"], onDelete: .cascade)
                }
                try db.create(index: "idx_file_meta_project", on: "file_metadata", columns: ["projectID"])
                try db.create(index: "idx_file_meta_path", on: "file_metadata", columns: ["path"])
            }

            migrator.registerMigration("v2_add_active_config_unique") { db in
                try db.create(index: "idx_api_configs_active_unique", on: "api_configs", columns: ["isActive"], unique: true, condition: "isActive = 1")
            }

            migrator.registerMigration("v3_add_settings_table") { db in
                try db.create(table: "app_settings") { t in
                    t.column("key", .text).primaryKey()
                    t.column("value", .text).notNull()
                    t.column("updatedAt", .datetime).notNull()
                }
            }

            try migrator.migrate(db)
        }
    }

    func close() {
        dbQueue = nil
    }
}

// MARK: - App Settings Helpers

extension DatabaseManager {
    func getSetting(_ key: String) async throws -> String? {
        try await reader.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM app_settings WHERE key = ?", arguments: [key])
        }
    }

    func setSetting(_ key: String, value: String) async throws {
        try await writer.write { db in
            try db.execute(sql: """
                INSERT INTO app_settings (key, value, updatedAt) VALUES (?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value, updatedAt = excluded.updatedAt
                """, arguments: [key, value, Date()])
        }
    }
}