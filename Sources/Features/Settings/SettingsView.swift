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
                    Button("保存") {
                        saveConfig()
                    }
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
                Picker("思考时长", selection: $parameterManager.parameters.thinkingDuration) {
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
                Picker("推理模式", selection: $parameterManager.parameters.reasoningMode) {
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
                    Slider(value: Binding(
                        get: { Double(parameterManager.parameters.maxTokens) },
                        set: { parameterManager.parameters.maxTokens = Int($0) }
                    ), in: 1024...32768, step: 1024)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Temperature: \(parameterManager.parameters.temperature, specifier: "%.2f")")
                        Spacer()
                    }
                    Slider(value: $parameterManager.parameters.temperature, in: 0...2, step: 0.05)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Top P: \(parameterManager.parameters.topP, specifier: "%.2f")")
                        Spacer()
                    }
                    Slider(value: $parameterManager.parameters.topP, in: 0...1, step: 0.05)
                }
            }

            Section("预估") {
                let estimate = parameterManager.estimateTokens()
                LabeledContent("预估 Token", value: "\(estimate.estimatedTokens)")
                LabeledContent("预估时间", value: "\(estimate.estimatedTime, specifier: "%.1f") 秒")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("AI 参数")
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
                            // Share sheet would be presented here
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
            if case .success(let urls) = result, let url = urls.first {
                Task {
                    let data = try? Data(contentsOf: url)
                    if let data = data {
                        try? await roleManager.importRoles(from: data)
                    }
                }
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
                    Button("保存") {
                        saveRole()
                    }
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
        var role = Role(
            id: role?.id ?? UUID(),
            name: name,
            systemPrompt: systemPrompt,
            specialties: specialties
        )
        Task {
            try? await roleManager.saveRole(role)
            dismiss()
        }
    }
}

// MARK: - Backup View

struct BackupView: View {
    @State private var isCreatingBackup = false
    @State private var isRestoringBackup = false
    @State private var backupProgress: Double = 0
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
                        ProgressView("备份中...", value: backupProgress, total: 1.0)
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
                        password: password.isEmpty ? nil : password,
                        progress: { progress in
                            Task { @MainActor in
                                backupProgress = progress
                            }
                        }
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
                LabeledContent("数据库", value: "GRDB (SQLite)")
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

// MARK: - Extensions

extension CodeBlock {
    static func extract(from text: String) -> [CodeBlock] {
        var blocks: [CodeBlock] = []
        let pattern = "```(\\w+)?\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        for match in matches {
            let language = match.range(at: 1).location != NSNotFound
                ? String(text[Range(match.range(at: 1), in: text)!])
                : "text"
            let code = String(text[Range(match.range(at: 2), in: text)!])
            blocks.append(CodeBlock(language: language, code: code))
        }
        return blocks
    }
}

