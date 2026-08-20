import SwiftUI

// MARK: - Editor View

struct EditorView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @State private var fileTree: FileNode?
    @State private var openFiles: [OpenFile] = []
    @State private var selectedFileID: UUID?
    @State private var showingFileTree = true
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if projectManager.currentProject == nil {
                    NoProjectSelectedView()
                } else {
                    HSplitView {
                        if showingFileTree {
                            FileTreeView(
                                fileTree: $fileTree,
                                selectedFileID: $selectedFileID,
                                searchText: $searchText,
                                onFileSelect: { node in
                                    if !node.isDirectory, let project = projectManager.currentProject {
                                        Task {
                                            do {
                                                let content = try await projectManager.readFile(path: node.path)
                                                let existing = openFiles.firstIndex(where: { $0.path == node.path })
                                                if let index = existing {
                                                    selectedFileID = openFiles[index].id
                                                } else {
                                                    let file = OpenFile(
                                                        path: node.path,
                                                        name: node.name,
                                                        content: content
                                                    )
                                                    openFiles.append(file)
                                                    selectedFileID = file.id
                                                    if openFiles.count > 10 {
                                                        openFiles.removeFirst()
                                                    }
                                                }
                                            } catch {
                                                print("Failed to read file: \(error)")
                                            }
                                        }
                                    }
                                }
                            )
                            .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
                        }

                        VStack(spacing: 0) {
                            TabBarView(
                                openFiles: $openFiles,
                                selectedFileID: $selectedFileID,
                                onClose: { id in
                                    openFiles.removeAll { $0.id == id }
                                    if selectedFileID == id {
                                        selectedFileID = openFiles.last?.id
                                    }
                                }
                            )

                            if let fileID = selectedFileID,
                               let file = openFiles.first(where: { $0.id == fileID }) {
                                CodeEditorWrapper(
                                    file: file,
                                    onContentChange: { newContent in
                                        if let index = openFiles.firstIndex(where: { $0.id == fileID }) {
                                            openFiles[index].content = newContent
                                            openFiles[index].isModified = true
                                        }
                                    },
                                    onSave: { file in
                                        Task {
                                            try? await projectManager.writeFile(path: file.path, content: file.content)
                                            if let index = openFiles.firstIndex(where: { $0.id == fileID }) {
                                                openFiles[index].isModified = false
                                            }
                                        }
                                    }
                                )
                            } else {
                                EmptyEditorView()
                            }
                        }
                    }
                }
            }
            .navigationTitle(projectManager.currentProject?.name ?? "编辑器")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation { showingFileTree.toggle() }
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("保存") {
                        saveCurrentFile()
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(selectedFileID == nil)
                }
            }
            .task {
                fileTree = try? await projectManager.getFileTree()
            }
            .onChange(of: projectManager.currentProject) { _, _ in
                Task {
                    fileTree = try? await projectManager.getFileTree()
                    openFiles.removeAll()
                    selectedFileID = nil
                }
            }
        }
    }

    private func saveCurrentFile() {
        guard let fileID = selectedFileID,
              let file = openFiles.first(where: { $0.id == fileID }) else { return }
        Task {
            try? await projectManager.writeFile(path: file.path, content: file.content)
            if let index = openFiles.firstIndex(where: { $0.id == fileID }) {
                openFiles[index].isModified = false
            }
        }
    }
}

// MARK: - No Project

struct NoProjectSelectedView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("选择或创建一个项目开始编码")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - File Tree

struct FileTreeView: View {
    @Binding var fileTree: FileNode?
    @Binding var selectedFileID: UUID?
    @Binding var searchText: String
    let onFileSelect: (FileNode) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text("文件")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            SearchBar(text: $searchText, placeholder: "搜索文件...")
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

            if let tree = fileTree {
                List {
                    FileTreeRow(node: tree, searchText: searchText, onSelect: onFileSelect)
                }
                .listStyle(.plain)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.regularMaterial)
    }
}

struct FileTreeRow: View {
    let node: FileNode
    let searchText: String
    let onSelect: (FileNode) -> Void
    @State private var isExpanded = true

    private var matchesSearch: Bool {
        searchText.isEmpty || node.name.localizedCaseInsensitiveContains(searchText)
    }

    var body: some View {
        if matchesSearch || hasMatchingChild(node, searchText: searchText) {
            if node.isDirectory {
                DisclosureGroup(isExpanded: $isExpanded) {
                    if let children = node.children {
                        ForEach(children) { child in
                            FileTreeRow(node: child, searchText: searchText, onSelect: onSelect)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(.blue)
                            .font(.caption)
                        Text(node.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .padding(.leading, 8)
            } else {
                Button {
                    onSelect(node)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: fileIcon(for: node.name))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(node.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
                .padding(.vertical, 2)
            }
        }
    }

    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py": return "python"
        case "js", "ts", "jsx", "tsx": return "doc.append"
        case "html": return "globe"
        case "css": return "paintbrush"
        case "json": return "curlybraces"
        case "md": return "doc.text"
        case "yaml", "yml": return "gearshape"
        default: return "doc"
        }
    }

    private func hasMatchingChild(_ node: FileNode, searchText: String) -> Bool {
        guard !searchText.isEmpty else { return true }
        if let children = node.children {
            if children.contains(where: { $0.name.localizedCaseInsensitiveContains(searchText) }) {
                return true
            }
            return children.contains { hasMatchingChild($0, searchText: searchText) }
        }
        return false
    }
}

// MARK: - Tab Bar

struct TabBarView: View {
    @Binding var openFiles: [OpenFile]
    @Binding var selectedFileID: UUID?
    let onClose: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(openFiles) { file in
                    Button {
                        selectedFileID = file.id
                    } label: {
                        HStack(spacing: 6) {
                            Text(file.name)
                                .font(.subheadline)
                                .lineLimit(1)
                            if file.isModified {
                                Circle()
                                    .fill(.secondary)
                                    .frame(width: 6, height: 6)
                            }
                            Button {
                                onClose(file.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 2)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selectedFileID == file.id ? Color.accentColor.opacity(0.1) : .clear)
                        .overlay(alignment: .bottom) {
                            if selectedFileID == file.id {
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(height: 2)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Divider().frame(height: 20)
                }
            }
        }
        .frame(height: 40)
        .background(.regularMaterial)
    }
}

// MARK: - Code Editor Wrapper

struct CodeEditorWrapper: View {
    @State var file: OpenFile
    let onContentChange: (String) -> Void
    let onSave: (OpenFile) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(file.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(file.isModified ? "未保存" : "已保存")
                    .font(.caption)
                    .foregroundStyle(file.isModified ? .orange : .green)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.regularMaterial)

            TextEditor(text: $file.content)
                .font(.system(size: 14, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(.background)
                .onChange(of: file.content) { _, newValue in
                    onContentChange(newValue)
                }
        }
    }
}

struct EmptyEditorView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("从文件树中选择一个文件开始编辑")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Models

struct OpenFile: Identifiable {
    let id = UUID()
    let path: String
    let name: String
    var content: String
    var isModified = false
}

// MARK: - Search Bar

struct SearchBar: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField(placeholder, text: $text)
                .font(.caption)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - HSplitView (simple horizontal split)

struct HSplitView<Left: View, Right: View>: View {
    @State private var splitRatio: CGFloat = 0.3
    let left: Left
    let right: Right

    init(@ViewBuilder content: () -> TupleView<(Left, Right)>) {
        let views = content()
        self.left = views.value.0
        self.right = views.value.1
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                left
                    .frame(width: max(0, geometry.size.width * splitRatio))

                Rectangle()
                    .fill(.separator)
                    .frame(width: 1)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newRatio = (geometry.size.width * splitRatio + value.translation.width) / geometry.size.width
                                splitRatio = max(0.15, min(0.6, newRatio))
                            }
                    )

                right
                    .frame(width: max(0, geometry.size.width * (1 - splitRatio) - 1))
            }
        }
    }
}