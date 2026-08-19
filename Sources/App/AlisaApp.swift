import SwiftUI
import SwiftData

@main
struct AlisaApp: App {
    @StateObject private var appState = AppState.shared
    @StateObject private var configManager = ConfigManager.shared
    @StateObject private var roleManager = RoleManager.shared
    @StateObject private var projectManager = ProjectManager.shared
    @StateObject private var parameterManager = ParameterManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(configManager)
                .environmentObject(roleManager)
                .environmentObject(projectManager)
                .environmentObject(parameterManager)
                .task {
                    await initializeApp()
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
        .modelContainer(for: [])
    }

    private func initializeApp() async {
        do {
            try await DatabaseManager.shared.setup()
            await configManager.load()
            await roleManager.load()
            await projectManager.load()
            await appState.restoreSession()
        } catch {
            print("App initialization failed: \(error)")
            appState.initializationError = error
        }
    }

    private func handleDeepLink(_ url: URL) {
        // Handle import URLs, project links, etc.
        if url.scheme == "alisa" {
            switch url.host {
            case "import":
                if let projectURL = URL(string: url.absoluteString.replacingOccurrences(of: "alisa://import?", with: "")) {
                    Task {
                        try? await projectManager.importProject(from: projectURL, name: "Imported Project")
                    }
                }
            case "project":
                if let projectID = UUID(uuidString: url.lastPathComponent) {
                    Task {
                        if let project = projectManager.projects.first(where: { $0.id == projectID }) {
                            try? await projectManager.openProject(project)
                        }
                    }
                }
            default:
                break
            }
        }
    }
}

// MARK: - App State

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var initializationError: Error?
    @Published var isFirstLaunch = false
    @Published var currentTab: Tab = .projects
    @Published var showingSettings = false
    @Published var showingNewProject = false
    @Published var showingImportProject = false

    private init() {
        isFirstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if isFirstLaunch {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        }
    }

    func restoreSession() async {
        // Restore last opened project, session, editor tabs
    }

    func completeOnboarding() {
        isFirstLaunch = false
    }
}

enum Tab: String, CaseIterable, Identifiable {
    case projects = "项目"
    case editor = "编辑器"
    case chat = "对话"
    case settings = "设置"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .projects: return "folder"
        case .editor: return "doc.text"
        case .chat: return "bubble.left.and.bubble.right"
        case .settings: return "gearshape"
        }
    }
}