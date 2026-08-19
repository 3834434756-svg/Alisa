import Foundation

// Preview Server - will use NWListener from Network framework in production
// Currently using a stub implementation to simplify CI build

@MainActor
final class PreviewServerManager: ObservableObject {
    static let shared = PreviewServerManager()

    @Published private(set) var isRunning = false
    @Published private(set) var serverURL: URL?
    @Published private(set) var currentProjectID: UUID?
    @Published private(set) var error: String?

    private init() {}

    func start(for projectID: UUID, projectPath: String) async throws {
        stop()
        // TODO: Implement with NWListener (iOS 17+ built-in)
        // For now, just set the URL to the file path for local preview
        let fileURL = URL(fileURLWithPath: projectPath).appendingPathComponent("index.html")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            self.currentProjectID = projectID
            self.isRunning = true
            self.serverURL = fileURL
            self.error = nil
        } else {
            throw PreviewError.projectNotFound
        }
    }

    func stop() {
        isRunning = false
        serverURL = nil
        currentProjectID = nil
        error = nil
    }

    func reload() {}
}

enum PreviewError: LocalizedError {
    case projectNotFound
    case notSupported

    var errorDescription: String? {
        switch self {
        case .projectNotFound: return "项目中没有 index.html 文件"
        case .notSupported: return "预览服务器暂不支持此功能"
        }
    }
}