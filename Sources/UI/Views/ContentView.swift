import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var projectManager: ProjectManager

    var body: some View {
        Group {
            if appState.isFirstLaunch {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        .alert("初始化错误", isPresented: .constant(appState.initializationError != nil)) {
            Button("重试") {
                Task { await initializeApp() }
            }
            Button("退出", role: .destructive) {
                exit(1)
            }
        } message: {
            Text(appState.initializationError?.localizedDescription ?? "未知错误")
        }
    }

    private func initializeApp() async {
        appState.initializationError = nil
        do {
            try? await DatabaseManager.shared.initializeBuiltInRoles()
            await ConfigManager.shared.load()
            await RoleManager.shared.load()
            await projectManager.load()
        } catch {
            appState.initializationError = error
        }
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var projectManager: ProjectManager

    var body: some View {
        TabView(selection: $appState.currentTab) {
            ProjectsView()
                .tabItem {
                    Label(Tab.projects.rawValue, systemImage: Tab.projects.systemImage)
                }
                .tag(Tab.projects)

            EditorView()
                .tabItem {
                    Label(Tab.editor.rawValue, systemImage: Tab.editor.systemImage)
                }
                .tag(Tab.editor)

            ChatView()
                .tabItem {
                    Label(Tab.chat.rawValue, systemImage: Tab.chat.systemImage)
                }
                .tag(Tab.chat)

            SettingsView()
                .tabItem {
                    Label(Tab.settings.rawValue, systemImage: Tab.settings.systemImage)
                }
                .tag(Tab.settings)
        }
        .sheet(isPresented: $appState.showingNewProject) {
            NewProjectSheet()
        }
        .sheet(isPresented: $appState.showingImportProject) {
            ImportProjectSheet()
        }
        .sheet(isPresented: $appState.showingSettings) {
            SettingsView()
        }
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var configManager: ConfigManager
    @State private var step = 0
    @State private var apiName = ""
    @State private var apiBaseURL = ""
    @State private var apiKey = ""
    @State private var apiModel = ""
    @State private var selectedRole: Role?

    private let steps = ["欢迎", "API 配置", "角色选择", "完成"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress indicator
                HStack {
                    ForEach(0..<steps.count, id: \.self) { index in
                        Circle()
                            .fill(index <= step ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 10, height: 10)
                        if index < steps.count - 1 {
                            Rectangle()
                                .fill(index < step ? Color.accentColor : Color.secondary.opacity(0.3))
                                .frame(height: 2)
                        }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.top, 40)

                TabView(selection: $step) {
                    WelcomeStepView()
                        .tag(0)

                    APIConfigStepView(
                        name: $apiName,
                        baseURL: $apiBaseURL,
                        apiKey: $apiKey,
                        model: $apiModel
                    )
                    .tag(1)

                    RoleSelectionStepView(selectedRole: $selectedRole)
                        .tag(2)

                    CompletionStepView()
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: step)

                // Navigation buttons
                HStack {
                    if step > 0 {
                        Button("上一步") {
                            withAnimation { step -= 1 }
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()

                    if step < steps.count - 1 {
                        Button("下一步") {
                            if validateCurrentStep() {
                                withAnimation { step += 1 }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!validateCurrentStep())
                    } else {
                        Button("开始使用") {
                            completeOnboarding()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
            .navigationTitle("欢迎使用 Alisa")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func validateCurrentStep() -> Bool {
        switch step {
        case 0: return true
        case 1: return !apiName.isEmpty && !apiBaseURL.isEmpty && !apiKey.isEmpty && !apiModel.isEmpty
        case 2: return selectedRole != nil
        case 3: return true
        default: return false
        }
    }

    private func completeOnboarding() {
        Task {
            do {
                try await configManager.addConfig(
                    name: apiName,
                    baseURL: apiBaseURL,
                    apiKey: apiKey,
                    model: apiModel
                )
                appState.completeOnboarding()
            } catch {
                print("Onboarding failed: \(error)")
            }
        }
    }
}

// MARK: - Onboarding Steps

struct WelcomeStepView: View {
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 80))
                .foregroundStyle(.blue.gradient)

            VStack(spacing: 12) {
                Text("Alisa")
                    .font(.largeTitle.bold())
                Text("你的移动端 AI 编程助手")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "terminal", title: "原生代码编辑器", description: "语法高亮、智能补全、多标签分屏")
                FeatureRow(icon: "bubble.left.and.bubble.right", title: "AI 协作编程", description: "流式对话、代码块应用、工具调用")
                FeatureRow(icon: "folder", title: "本地项目管理", description: "文件树、ZIP 导入导出、iCloud 同步")
                FeatureRow(icon: "safari", title: "实时预览", description: "HTML/CSS/JS 热重载、简易 DevTools")
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding()
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(description).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

struct APIConfigStepView: View {
    @Binding var name: String
    @Binding var baseURL: String
    @Binding var apiKey: String
    @Binding var model: String

    var body: some View {
        Form {
            Section("API 配置") {
                TextField("配置名称 (如: DeepSeek, OpenAI)", text: $name)
                TextField("API Base URL", text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("API Key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("模型名称 (如: deepseek-chat, gpt-4)", text: $model)
            }

            Section {
                Text("支持兼容 OpenAI API 格式的任意大模型服务")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct RoleSelectionStepView: View {
    @EnvironmentObject var roleManager: RoleManager
    @Binding var selectedRole: Role?

    var body: some View {
        List(roleManager.allRoles(), selection: $selectedRole) { role in
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(role.name).font(.headline)
                    Text(role.specialties.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if role.isBuiltIn {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                }
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("选择默认角色")
        .onAppear {
            selectedRole = roleManager.builtInRoles.first
        }
    }
}

struct CompletionStepView: View {
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green.gradient)

            Text("准备就绪")
                .font(.largeTitle.bold())

            Text("Alisa 已配置完成，点击\"开始使用\"进入主界面")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
        .padding()
    }
}