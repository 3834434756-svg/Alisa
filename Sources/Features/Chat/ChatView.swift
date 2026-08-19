import SwiftUI

// MARK: - Chat View

struct ChatView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @EnvironmentObject var configManager: ConfigManager
    @EnvironmentObject var roleManager: RoleManager
    @StateObject private var viewModel = ChatViewModel()
    @State private var showingSessionList = true
    @State private var showingRolePicker = false

    var body: some View {
        NavigationStack {
            HSplitView {
                if showingSessionList {
                    SessionListView(viewModel: viewModel)
                        .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
                }

                VStack(spacing: 0) {
                    // Chat header
                    ChatHeaderView(
                        viewModel: viewModel,
                        showingRolePicker: $showingRolePicker
                    )

                    // Messages
                    MessageListView(viewModel: viewModel)

                    // Input area
                    ChatInputView(viewModel: viewModel)
                }
            }
            .navigationTitle(viewModel.currentSession?.title ?? "对话")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation { showingSessionList.toggle() }
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("新建会话") {
                        viewModel.createNewSession()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if viewModel.isStreaming {
                        Button("停止", role: .destructive) {
                            viewModel.stopStreaming()
                        }
                    }
                }
            }
            .sheet(isPresented: $showingRolePicker) {
                RolePickerView(viewModel: viewModel)
            }
            .onAppear {
                if viewModel.currentSession == nil {
                    viewModel.createNewSession()
                }
            }
        }
    }
}

// MARK: - Session List

struct SessionListView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var sessions: [Session] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                Text("会话历史")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.createNewSession()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            List(selection: $viewModel.selectedSessionID) {
                ForEach(sessions) { session in
                    SessionRow(session: session)
                        .tag(session.id)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        viewModel.deleteSession(sessions[index].id)
                    }
                }
            }
            .listStyle(.plain)
            .task {
                sessions = (try? await SessionRepository(db: DatabaseManager.shared).getAll()) ?? []
            }
        }
        .background(.regularMaterial)
    }
}

struct SessionRow: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title)
                .font(.subheadline.bold())
                .lineLimit(1)
            Text("\(session.messageCount) 条消息 · \(session.totalTokens) tokens")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Chat Header

struct ChatHeaderView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var showingRolePicker: Bool
    @EnvironmentObject var roleManager: RoleManager

    var body: some View {
        HStack {
            if let role = roleManager.getRole(id: viewModel.currentRoleID) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(role.name)
                        .font(.subheadline.bold())
                    Text(role.specialties.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                showingRolePicker = true
            } label: {
                Image(systemName: "person.circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }
}

// MARK: - Message List

struct MessageListView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.messages.isEmpty {
                        WelcomeMessage()
                    }

                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    if viewModel.isStreaming {
                        StreamingIndicator()
                            .id("streaming")
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.isStreaming) { _, streaming in
                if streaming {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
        }
    }
}

struct WelcomeMessage: View {
    @EnvironmentObject var roleManager: RoleManager

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundStyle(.blue.gradient)

            Text("你好，我是 Alisa")
                .font(.title2.bold())

            Text("你的 AI 编程助手。我可以帮你写代码、重构、调试、解答技术问题。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(spacing: 8) {
                SuggestionChip(text: "创建一个新的 SwiftUI 项目") {
                    // TODO: Send message
                }
                SuggestionChip(text: "解释 SOLID 原则") {
                    // TODO: Send message
                }
                SuggestionChip(text: "优化这段代码的性能") {
                    // TODO: Send message
                }
            }
        }
        .padding(.vertical, 40)
    }
}

struct SuggestionChip: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.blue.opacity(0.1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                // Role label
                Text(message.role == .user ? "我" : message.role.rawValue.capitalized)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                // Content
                if message.role == .assistant {
                    MarkdownView(text: message.content)
                } else {
                    Text(message.content)
                        .font(.body)
                }

                // Code blocks
                if let codeBlocks = message.codeBlocks {
                    ForEach(codeBlocks) { block in
                        CodeBlockView(block: block)
                    }
                }

                // Timestamp
                Text(message.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(message.role == .user ? Color.accentColor.opacity(0.1) : Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if message.role != .user {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Code Block View

struct CodeBlockView: View {
    let block: CodeBlock
    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(block.language)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 12) {
                    if let filePath = block.filePath {
                        Text(filePath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        UIPasteboard.general.string = block.code
                        isCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            isCopied = false
                        }
                    } label: {
                        Label(isCopied ? "已复制" : "复制", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)

                    Button("应用到文件", systemImage: "square.and.arrow.down") {
                        applyCode()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(block.code)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .textSelection(.enabled)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
    }

    private func applyCode() {
        Task {
            guard let project = ProjectManager.shared.currentProject else { return }
            let path = block.filePath ?? "generated/\(block.language.lowercased())-\(UUID().uuidString.prefix(8)).txt"
            try? await FileSystemService.shared.writeFile(project: project, path: path, content: block.code)
        }
    }
}

// MARK: - Streaming Indicator

struct StreamingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .scaleEffect(isAnimating ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { isAnimating = true }
        .onDisappear { isAnimating = false }
    }
}

// MARK: - Chat Input

struct ChatInputView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var message = ""

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 8) {
                Button {
                    // Attach file
                } label: {
                    Image(systemName: "paperclip")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                TextField("输入消息，或 @ 引用文件...", text: $message, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(1...8)
                    .onSubmit {
                        sendMessage()
                    }

                Button {
                    // Voice input
                } label: {
                    Image(systemName: "mic")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(message.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(message.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isStreaming)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.regularMaterial)
    }

    private func sendMessage() {
        let text = message.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        message = ""
        viewModel.sendMessage(text)
    }
}

// MARK: - Role Picker

struct RolePickerView: View {
    @ObservedObject var viewModel: ChatViewModel
    @EnvironmentObject var roleManager: RoleManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("内置角色") {
                    ForEach(roleManager.builtInRoles) { role in
                        RoleRow(role: role, isSelected: viewModel.currentRoleID == role.id) {
                            viewModel.switchRole(role.id)
                            dismiss()
                        }
                    }
                }

                Section("自定义角色") {
                    ForEach(roleManager.customRoles) { role in
                        RoleRow(role: role, isSelected: viewModel.currentRoleID == role.id) {
                            viewModel.switchRole(role.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("选择角色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

struct RoleRow: View {
    let role: Role
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(role.name).font(.headline)
                    Text(role.specialties.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

// MARK: - Markdown View (Simplified)

struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let blocks = parseMarkdown(text)
            ForEach(blocks.indices, id: \.self) { index in
                MarkdownBlockView(block: blocks[index])
            }
        }
    }

    private func parseMarkdown(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: .newlines)
        var i = 0

        while i < lines.count {
            let line = lines[i]

            if line.hasPrefix("```") {
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.code(language: language, code: codeLines.joined(separator: "\n")))
                i += 1
            } else if line.hasPrefix("## ") {
                blocks.append(.heading2(String(line.dropFirst(3))))
                i += 1
            } else if line.hasPrefix("# ") {
                blocks.append(.heading1(String(line.dropFirst(2))))
                i += 1
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                var items: [String] = [String(line.dropFirst(2))]
                i += 1
                while i < lines.count && (lines[i].hasPrefix("- ") || lines[i].hasPrefix("* ")) {
                    items.append(String(lines[i].dropFirst(2)))
                    i += 1
                }
                blocks.append(.list(items))
            } else if line.isEmpty {
                i += 1
            } else {
                blocks.append(.text(line))
                i += 1
            }
        }

        return blocks
    }
}

enum MarkdownBlock {
    case heading1(String)
    case heading2(String)
    case text(String)
    case code(language: String, code: String)
    case list([String])
}

struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading1(let text):
            Text(text)
                .font(.title.bold())
        case .heading2(let text):
            Text(text)
                .font(.title2.bold())
        case .text(let text):
            Text(renderInline(text))
                .font(.body)
        case .code(let language, let code):
            CodeBlockView(block: CodeBlock(language: language, code: code))
        case .list(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                        Text(renderInline(items[index]))
                    }
                    .font(.body)
                }
            }
        }
    }

    private func renderInline(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        for (range, _) in attributed.runs {
            // Bold: **text**
            if let boldRange = findMarkdown(text, pattern: "\\*\\*(.+?)\\*\\*") {
                attributed[boldRange].inlinePresentationIntent = .stronglyEmphasized
            }
            // Inline code: `text`
            if let codeRange = findMarkdown(text, pattern: "`(.+?)`") {
                attributed[codeRange].inlinePresentationIntent = .code
            }
        }
        return attributed
    }

    private func findMarkdown(_ text: String, pattern: String) -> Range<AttributedString.Index>? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return AttributedString.Index(range.lowerBound, within: AttributedString(text)).map { start in
            let end = AttributedString.Index(range.upperBound, within: AttributedString(text))!
            return start..<end
        } ?? nil
    }
}

// MARK: - Chat ViewModel

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var currentSession: Session?
    @Published var currentRoleID: UUID = UUID()
    @Published var selectedSessionID: UUID?
    @Published var isStreaming = false

    private var streamingTask: Task<Void, Never>?
    private let sessionRepo = SessionRepository(db: DatabaseManager.shared)
    private let messageRepo = MessageRepository(db: DatabaseManager.shared)
    private let aiClient = AIClient.shared

    func createNewSession() {
        Task {
            let session = try? await sessionRepo.create(projectID: nil, roleID: currentRoleID)
            currentSession = session
            selectedSessionID = session?.id
            messages = []
        }
    }

    func switchRole(_ roleID: UUID) {
        currentRoleID = roleID
        createNewSession()
    }

    func sendMessage(_ text: String) {
        guard let session = currentSession else { return }

        let userMessage = Message(sessionID: session.id, role: .user, content: text, status: .completed)
        messages.append(userMessage)
        Task {
            try? await sessionRepo.appendMessage(userMessage, to: session.id)
        }

        isStreaming = true
        var accumulatedContent = ""
        let assistantMessage = Message(sessionID: session.id, role: .assistant, content: "", status: .streaming)
        messages.append(assistantMessage)

        streamingTask = Task {
            do {
                let context = AIContext(
                    messages: messages.prefix(messages.count - 1).map {
                        ChatMessage(role: $0.role.rawValue, content: $0.content)
                    },
                    referencedFiles: [],
                    selectedCode: nil,
                    currentFile: nil,
                    project: ProjectManager.shared.currentProject
                )

                if let config = ConfigManager.shared.activeConfig {
                    aiClient.configure(config: config, parameters: ParameterManager.shared.parameters)
                }

                await aiClient.sendMessage(
                    text,
                    context: context,
                    parameters: ParameterManager.shared.parameters,
                    onToken: { token in
                        accumulatedContent += token
                        if let index = self.messages.lastIndex(where: { $0.status == .streaming }) {
                            self.messages[index].content = accumulatedContent
                        }
                    },
                    onToolCall: { toolCall in
                        // Handle tool calls
                    },
                    onComplete: { result in
                        Task { @MainActor in
                            self.isStreaming = false
                            switch result {
                            case .success(let response):
                                if let index = self.messages.lastIndex(where: { $0.status == .streaming }) {
                                    self.messages[index].status = .completed
                                    self.messages[index].content = response.content
                                    let codeBlocks = CodeBlock.extract(from: response.content)
                                    if !codeBlocks.isEmpty {
                                        self.messages[index].codeBlocks = codeBlocks
                                    }
                                    self.messages[index].tokenCount = response.usage.totalTokens
                                }
                            case .failure(let error):
                                if let index = self.messages.lastIndex(where: { $0.status == .streaming }) {
                                    self.messages[index].status = .failed
                                    self.messages[index].content = "错误: \(error.localizedDescription)"
                                }
                            }
                        }
                    }
                )
            }
        }
    }

    func stopStreaming() {
        streamingTask?.cancel()
        isStreaming = false
        if let index = messages.lastIndex(where: { $0.status == .streaming }) {
            messages[index].status = .completed
        }
    }

    func deleteSession(_ id: UUID) {
        Task {
            try? await sessionRepo.delete(id: id)
            if selectedSessionID == id {
                createNewSession()
            }
        }
    }

    func loadSession(_ id: UUID) {
        Task {
            currentSession = try? await sessionRepo.get(id: id)
            selectedSessionID = id
            messages = try? await messageRepo.getAll(sessionID: id) ?? []
        }
    }
}