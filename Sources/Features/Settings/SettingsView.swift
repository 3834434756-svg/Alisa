import SwiftUI

// MARK: - Settings View

enum SettingsTab: String, CaseIterable {
    case api = "API 配置"
    case parameters = "AI 参数"
    case roles = "角色管理"
    case backup = "备份与恢复"
    case about = "关于"

    var systemImage: String {
        switch self {
        case .api: return "antenna.radiowaves.left.and.right"
        case .parameters: return "slider.horizontal.3"
        case .roles: return "person.circle"
        case .backup: return "externaldrive"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var configManager: ConfigManager
    @EnvironmentObject var roleManager: RoleManager
    @EnvironmentObject var parameterManager: ParameterManager
    @State private var selectedTab: SettingsTab = .api

    var body: some View {
        NavigationStack {
            if UIDevice.current.userInterfaceIdiom == .pad {
                SettingsSplitView(selectedTab: $selectedTab)
            } else {
                SettingsList()
            }
        }
    }

    @ViewBuilder
    private func SettingsList() -> some View {
        List {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                NavigationLink {
                    settingsContent(for: tab)
                } label: {
                    Label(tab.rawValue, systemImage: tab.systemImage)
                }
            }
        }
        .navigationTitle("设置")
    }

    @ViewBuilder
    private func settingsContent(for tab: SettingsTab) -> some View {
        switch tab {
        case .api: APIConfigView()
        case .parameters: AIParametersView()
        case .roles: RoleManagementView()
        case .backup: BackupView()
        case .about: AboutView()
        }
    }
}

struct SettingsSplitView: View {
    @Binding var selectedTab: SettingsTab

    var body: some View {
        HSplitView {
            List {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.rawValue, systemImage: tab.systemImage)
                            .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200, idealWidth: 250)

            settingsDetail(for: selectedTab)
        }
        .navigationTitle("设置")
    }

    @ViewBuilder
    private func settingsDetail(for tab: SettingsTab) -> some View {
        switch tab {
        case .api: APIConfigView()
        case .parameters: AIParametersView()
        case .roles: RoleManagementView()
        case .backup: BackupView()
        case .about: AboutView()
        }
    }
}

// MARK: - API Config View

struct APIConfigView: View {
    @EnvironmentObject var configManager: ConfigManager
    @State private var showingAddConfig = false
    @State private var editingConfig: APIConfig?
    @State private var testResult: (UUID, Bool)?

    var body: some View {
        Form {
            Section("当前配置") {
                if let active = configManager.activeConfig {
                    ActiveConfigCard(config: active)
                } else {
                    Text("未配置 API 连接")
                        .foregroundStyle(.secondary)
                }
            }

            Section("配置列表") {
                ForEach(configManager.configs) { config in
                    ConfigRow(
                        config: config,
                        isActive: config.id == configManager.activeConfig?.id,
                        testResult: testResult?.0 == config.id ? testResult?.1 : nil,
                        onActivate: { Task { try? await configManager.setActive(config.id) } },
                        onTest: {
                            Task {
                                testResult = (config.id, await configManager.testConnection(config))
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { testResult = nil }
                            }
                        },
                        onEdit: { editingConfig = config },
                        onDelete: { Task { try? await configManager.deleteConfig(id: config.id) } }
                    )
                }

                Button { showingAddConfig = true } label: {
                    Label("添加配置", systemImage: "plus")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("API 配置")
        .sheet(isPresented: $showingAddConfig) {
            APIConfigSheet(config: nil)
        }
        .sheet(item: $editingConfig) { config in
            APIConfigSheet(config: config)
        }
    }
}

struct ActiveConfigCard: View {
    let config: APIConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text(config.name).font(.headline)
            }
            Text(config.baseURL).font(.caption).foregroundStyle(.secondary)
            Text("模型: \(config.model)").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct ConfigRow: View {
    let config: APIConfig
    let isActive: Bool
    let testResult: Bool?
    let onActivate: () -> Void
    let onTest: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(config.name).font(.headline)
                    if isActive {
                        Text("当前")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                Text(config.baseURL).font(.caption).foregroundStyle(.secondary)
                Text(config.model).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let result = testResult {
                Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result ? .green : .red)
            }
            Menu {
                if !isActive {
                    Button("激活", systemImage: "checkmark") { onActivate() }
                }
                Button("测试连接", systemImage: "bolt") { onTest() }
                Button("编辑", systemImage: "pencil") { onEdit() }
                Divider()
                Button("删除", systemImage: "trash", role: .destructive) { onDelete() }
            } label: {
                Image(systemName: "ellipsis").font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - API Config Sheet

struct APIConfigSheet: View {
    let config: APIConfig?
    @EnvironmentObject var configManager: ConfigManager
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var model = ""
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("配置名称", text: $name)
                    TextField("API Base URL", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API Key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("模型名称", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Text("支持兼容 OpenAI API 格式的任意大模型服务")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(config == nil ? "添加配置" : "编辑配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveConfig() }
                        .disabled(name.isEmpty || baseURL.isEmpty || (config == nil && apiKey.isEmpty) || model.isEmpty)
                }
            }
            .onAppear {
                if let config = config {
                    name = config.name
                    baseURL = config.baseURL
                    model = config.model
                }
            }
            .alert("保存失败", isPresented: $showingError) {
                Button("确定") {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func saveConfig() {
        Task {
            do {
                if let config = config {
                    var updated = config
                    updated.name = name
                    updated.baseURL = baseURL
                    updated.model = model
                    if !apiKey.isEmpty {
                        try await KeychainService.shared.saveAPIKey(apiKey, for: config.id)
                    }
                    try await configManager.updateConfig(updated)
                } else {
                    try await configManager.addConfig(name: name, baseURL: baseURL, apiKey: apiKey, model: model)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}

// MARK: - AI Parameters View

struct AIParametersView: View {
    @EnvironmentObject var parameterManager: ParameterManager
    @State private var selectedPreset: ParameterPreset?

    var body: some View {
        Form {
            Section("参数预设") {
                ForEach(parameterManager.presets) { preset in
                    PresetRow(preset: preset, isSelected: parameterManager.parameters == preset.parameters) {
                        parameterManager.applyPreset(preset)
                    }
                }
            }

            Section("思考时长") {
                Picker("思考时长", selection: Binding(
                    get: { parameterManager.parameters.thinkingDuration },
                    set: { parameterManager.parameters.thinkingDuration = $0 }
                )) {
                    ForEach(ThinkingDuration.allCases, id: \.self) { duration in
                        Text(duration.displayName).tag(duration)
                    }
                }
                .pickerStyle(.segmented)

                Text("\(thinkingDurationDescription(for: parameterManager.parameters.thinkingDuration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("思考强度") {
                VStack(spacing: 8) {
                    Slider(value: Binding(
                        get: { Double(parameterManager.parameters.thinkingIntensity) },
                        set: { parameterManager.parameters.thinkingIntensity = Int($0) }
                    ), in: 1...100, step: 1)

                    HStack {
                        Text("精简").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(parameterManager.parameters.thinkingIntensity)")
                            .font(.headline.monospacedDigit())
                        Spacer()
                        Text("深度").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("推理模式") {
                Picker("推理模式", selection: Binding(
                    get: { parameterManager.parameters.reasoningMode },
                    set: { parameterManager.parameters.reasoningMode = $0 }
                )) {
                    ForEach(ReasoningMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("高级参数") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Max Tokens: \(parameterManager.parameters.maxTokens)")
                        Spacer()
                    }
                    Slider(
                        value: Binding(
                            get: { Double(parameterManager.parameters.maxTokens) },
                            set: { parameterManager.parameters.maxTokens = Int($0) }
                        ), in: 1024...32768, step: 1024)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Temperature: \(parameterManager.parameters.temperature, specifier: "%.2f")")
                        Spacer()
                    }
                    Slider(
                        value: Binding(
                            get: { parameterManager.parameters.temperature },
                            set: { parameterManager.parameters.temperature = $0 }
                        ), in: 0...2, step: 0.05)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Top P: \(parameterManager.parameters.topP, specifier: "%.2f")")
                        Spacer()
                    }
                    Slider(
                        value: Binding(
                            get: { parameterManager.parameters.topP },
                            set: { parameterManager.parameters.topP = $0 }
                        ), in: 0...1, step: 0.05)
                }
            }

            .formStyle(.grouped)
            .navigationTitle("AI 参数")
        }
    }

    private func thinkingDurationDescription(for duration: ThinkingDuration) -> String {
        switch duration {
        case .fast: return "快速响应模式，适合简单代码生成和补全"
        case .balanced: return "平衡模式，适合大多数编程任务"
        case .deep: return "深度思考模式，适合复杂架构设计和问题分析"
        }
    }
}

struct PresetRow: View {
    let preset: ParameterPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.name).font(.headline)
                    Text(preset.description).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Role Management View

struct RoleManagementView: View {
    @EnvironmentObject var roleManager: RoleManager
    @State private var showingAddRole = false
    @State private var showingImportExport = false
    @State private var importData: Data?

    var body: some View {
        Form {
            Section("内置角色") {
                ForEach(roleManager.builtInRoles) { role in
                    RoleDetailRow(role: role)
                }
            }

            Section("自定义角色") {
                ForEach(roleManager.customRoles) { role in
                    RoleDetailRow(role: role)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        Task { try? await roleManager.deleteRole(id: roleManager.customRoles[index].id) }
                    }
                }

                Button {
                    showingAddRole = true
                } label: {
                    Label("添加角色", systemImage: "plus")
                }
            }

            Section {
                Button("导入角色 (JSON)") {
                    showingImportExport = true
                }
                Button("导出角色") {
                    Task {
                        let data = try? await roleManager.exportRoles()
                        if let data = data {
                            let url = FileManager.default.temporaryDirectory.appendingPathComponent("alisa-roles-export.json")
                            try? data.write(to: url)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("角色管理")
        .sheet(isPresented: $showingAddRole) {
            RoleEditSheet(role: nil)
        }
        .fileImporter(isPresented: $showingImportExport, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let urls):
                let urlArray: [URL] = (urls as? [URL]) ?? [(urls as! URL)]
                if let url = urlArray.first {
                    Task {
                        let data = try? Data(contentsOf: url)
                        if let data = data {
                            try? await roleManager.importRoles(from: data)
                        }
                    }
                }
            case .failure:
                break
            }
        }
    }
}

struct RoleDetailRow: View {
    let role: Role

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(role.name).font(.headline)
                if role.isBuiltIn {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }
            Text(role.specialties.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(role.systemPrompt.prefix(100) + "...")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Role Edit Sheet

struct RoleEditSheet: View {
    let role: Role?
    @EnvironmentObject var roleManager: RoleManager
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var systemPrompt = ""
    @State private var specialtiesText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("角色信息") {
                    TextField("角色名称", text: $name)
                    TextField("专长标签 (逗号分隔)", text: $specialtiesText)
                }

                Section("系统提示词") {
                    TextEditor(text: $systemPrompt)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(role == nil ? "新建角色" : "编辑角色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveRole() }
                        .disabled(name.isEmpty || systemPrompt.isEmpty)
                }
            }
            .onAppear {
                if let role = role {
                    name = role.name
                    systemPrompt = role.systemPrompt
                    specialtiesText = role.specialties.joined(separator: ", ")
                }
            }
        }
    }

    private func saveRole() {
        let specialties = specialtiesText.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let newRole = Role(
            id: role?.id ?? UUID(),
            name: name,
            systemPrompt: systemPrompt,
            specialties: specialties
        )
        Task {
            try? await roleManager.saveRole(newRole)
            dismiss()
        }
    }
}

// MARK: - Backup View

struct BackupView: View {
    @State private var isCreatingBackup = false
    @State private var isRestoringBackup = false
    @State private var showPasswordPrompt = false
    @State private var password = ""

    var body: some View {
        Form {
            Section("创建备份") {
                Text("备份将包含项目文件、会话历史和配置数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    showPasswordPrompt = true
                } label: {
                    if isCreatingBackup {
                        ProgressView("备份中...")
                    } else {
                        Label("创建备份", systemImage: "externaldrive.badge.plus")
                    }
                }
                .disabled(isCreatingBackup || isRestoringBackup)
            }

            Section("恢复备份") {
                Text("从备份文件恢复数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    // File picker for backup
                } label: {
                    if isRestoringBackup {
                        ProgressView("恢复中...", value: backupProgress, total: 1.0)
                    } else {
                        Label("选择备份文件", systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(isCreatingBackup || isRestoringBackup)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("备份与恢复")
        .alert("设置密码", isPresented: $showPasswordPrompt) {
            SecureField("密码", text: $password)
            Button("取消", role: .cancel) { password = "" }
            Button("开始备份") {
                Task {
                    isCreatingBackup = true
                    _ = try? await BackupManager.shared.createBackup(
                        password: password.isEmpty ? nil : password
                    )
                    isCreatingBackup = false
                    password = ""
                }
            }
        } message: {
            Text("可选：设置密码加密备份文件")
        }
    }
}

// MARK: - About View

struct AboutView: View {
    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 60))
                            .foregroundStyle(.blue.gradient)
                        Text("Alisa")
                            .font(.largeTitle.bold())
                        Text("版本 1.0.0")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 20)
            }

            Section("功能") {
                FeatureRow(icon: "terminal", title: "AI 代码编辑器", description: "语法高亮、智能补全、多标签分屏")
                FeatureRow(icon: "bubble.left.and.bubble.right", title: "AI 协作编程", description: "流式对话、代码块应用、工具调用")
                FeatureRow(icon: "folder", title: "本地项目管理", description: "文件树、ZIP 导入导出、iCloud 同步")
                FeatureRow(icon: "safari", title: "实时预览", description: "HTML/CSS/JS 热重载、简易 DevTools")
            }

            Section("技术栈") {
                LabeledContent("语言", value: "Swift 6")
                LabeledContent("UI 框架", value: "SwiftUI + UIKit")
                LabeledContent("数据库", value: "JSON 文件存储")
                LabeledContent("最低系统", value: "iOS 17.0")
            }

            Section("开源许可") {
                Text("Alisa 使用 MIT 许可证")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("关于")
    }
}
