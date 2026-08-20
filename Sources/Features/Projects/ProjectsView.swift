import SwiftUI
import UniformTypeIdentifiers

// MARK: - Projects View

struct ProjectsView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @EnvironmentObject var appState: AppState
    @State private var showingDeleteAlert = false
    @State private var projectToDelete: Project?

    var body: some View {
        NavigationStack {
            Group {
                if projectManager.projects.isEmpty {
                    EmptyProjectsView()
                } else {
                    ProjectsGridView()
                }
            }
            .navigationTitle("项目")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("新建项目", systemImage: "plus") {
                            appState.showingNewProject = true
                        }
                        Button("导入项目", systemImage: "square.and.arrow.down") {
                            appState.showingImportProject = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("删除项目", isPresented: $showingDeleteAlert, presenting: projectToDelete) { project in
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    Task { try? await projectManager.deleteProject(project) }
                }
            } message: { project in
                Text("确定要删除项目 \"\(project.name)\" 吗？此操作不可恢复。")
            }
        }
    }
}

struct EmptyProjectsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("暂无项目")
                    .font(.title2.bold())
                Text("创建你的第一个编程项目，开始与 Alisa 协作")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button("新建项目") {
                appState.showingNewProject = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ProjectsGridView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @State private var projectToDelete: Project?

    let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(projectManager.projects) { project in
                    ProjectCard(project: project)
                        .contextMenu {
                            Button("打开", systemImage: "folder") {
                                Task { try? await projectManager.openProject(project) }
                            }
                            Button("重命名", systemImage: "pencil") {
                                // TODO: Rename sheet
                            }
                            Button("导出", systemImage: "square.and.arrow.up") {
                                // TODO: Export sheet
                            }
                            Divider()
                            Button("删除", systemImage: "trash", role: .destructive) {
                                projectToDelete = project
                            }
                        }
                        .onTapGesture {
                            Task { try? await projectManager.openProject(project) }
                        }
                }
            }
            .padding()
        }
        .refreshable {
            await projectManager.load()
        }
    }
}

struct ProjectCard: View {
    let project: Project
    @EnvironmentObject var projectManager: ProjectManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: templateIcon(for: project.template))
                    .font(.title2)
                    .foregroundStyle(.blue)
                Spacer()
                Text(project.template?.displayName ?? "自定义")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.1))
                    .clipShape(Capsule())
            }

            Text(project.name)
                .font(.headline)
                .lineLimit(1)

            Text(project.lastOpenedAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let currentProject = projectManager.currentProject,
               currentProject.id == project.id {
                Label("当前打开", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func templateIcon(for template: ProjectTemplate?) -> String {
        switch template {
        case .swiftPackage: return "swift"
        case .htmlSite: return "globe"
        case .pythonScript: return "python"
        default: return "folder"
        }
    }
}

// MARK: - New Project Sheet

struct NewProjectSheet: View {
    @EnvironmentObject var projectManager: ProjectManager
    @EnvironmentObject var appState: AppState
    @State private var name = ""
    @State private var selectedTemplate: ProjectTemplate = .empty
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("项目信息") {
                    TextField("项目名称", text: $name)
                }

                Section("模板") {
                    ForEach(ProjectTemplate.allCases, id: \.self) { template in
                        TemplateRow(template: template, isSelected: selectedTemplate == template) {
                            selectedTemplate = template
                        }
                    }
                }
            }
            .navigationTitle("新建项目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { appState.showingNewProject = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        Task {
                            do {
                                try await projectManager.createProject(name: name, template: selectedTemplate)
                                appState.showingNewProject = false
                            } catch {
                                errorMessage = error.localizedDescription
                                showingError = true
                            }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("创建失败", isPresented: $showingError) {
                Button("确定") {}
            } message: {
                Text(errorMessage)
            }
        }
    }
}

struct TemplateRow: View {
    let template: ProjectTemplate
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: templateIcon(for: template))
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(template.displayName).font(.headline)
                    Text(templateDescription(for: template))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func templateIcon(for template: ProjectTemplate) -> String {
        switch template {
        case .empty: return "doc"
        case .swiftPackage: return "swift"
        case .htmlSite: return "globe"
        case .pythonScript: return "python"
        }
    }

    private func templateDescription(for template: ProjectTemplate) -> String {
        switch template {
        case .empty: return "空白项目，从零开始"
        case .swiftPackage: return "Swift Package 标准结构"
        case .htmlSite: return "静态网站 (HTML/CSS/JS)"
        case .pythonScript: return "Python 脚本项目"
        }
    }
}

// MARK: - Import Project Sheet

struct ImportProjectSheet: View {
    @EnvironmentObject var projectManager: ProjectManager
    @EnvironmentObject var appState: AppState
    @State private var projectName = ""
    @State private var showingPicker = false
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("项目名称") {
                    TextField("输入项目名称", text: $projectName)
                }

                Section {
                    Button("选择 ZIP 文件") {
                        showingPicker = true
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("导入项目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { appState.showingImportProject = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        // File picker would trigger this
                    }
                    .disabled(projectName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
.fileImporter(
                isPresented: $showingPicker,
                allowedContentTypes: [.zip]
            ) { result in
                switch result {
                case .success(let urls):
                    let urlArray: [URL] = (urls as? [URL]) ?? [(urls as! URL)]
                    guard let url = urlArray.first else { return }
                    Task {
                        do {
                            _ = try await projectManager.importProject(from: url, name: projectName)
                            appState.showingImportProject = false
                        } catch {
                            errorMessage = error.localizedDescription
                            showingError = true
                        }
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
            .alert("导入失败", isPresented: $showingError) {
                Button("确定") {}
            } message: {
                Text(errorMessage)
            }
        }
    }
}