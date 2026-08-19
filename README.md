# Alisa

iOS AI 编程客户端 - 移动端 AI 代码编辑器

## 功能

- **AI 协作编程**：流式对话、代码块应用、工具调用（读取/写入/编辑文件）
- **代码编辑器**：语法高亮、多标签页、分屏模式、搜索替换
- **本地项目管理**：文件树、ZIP 导入导出、iCloud 同步
- **API 配置管理**：自定义 API 接口、密钥 Keychain 加密存储、多配置切换
- **AI 参数调节**：思考时长/强度滑块、推理模式、预设模板
- **角色预设系统**：内置 Alisa 工程师角色、自定义角色导入导出
- **HTML 本地预览**：热重载、简易 DevTools
- **备份恢复**：AES-256 加密备份、选择性恢复
- **Face ID 保护**：API 密钥和项目数据安全

## 技术栈

- **语言**: Swift 6
- **UI**: SwiftUI + UIKit (TextKit 2)
- **数据库**: GRDB (SQLite WAL)
- **密钥存储**: iOS Keychain
- **依赖管理**: Swift Package Manager
- **最低系统**: iOS 17.0 (iPhone/iPad)

## 依赖

- [GRDB.swift](https://github.com/groue/GRDB.swift) - SQLite 数据库
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) - ZIP 压缩
- [GCDWebServer](https://github.com/swisspol/GCDWebServer) - 本地预览服务器
- [Highlightr](https://github.com/raspu/Highlightr) - 语法高亮

## 快速开始

### 前提条件

- macOS 14+ (Sonoma)
- Xcode 16+
- iOS 17.0+ 真机或模拟器

### 安装

```bash
# 1. 安装 XcodeGen（用于生成 .xcodeproj）
brew install xcodegen

# 2. 生成 Xcode 项目
cd Alisa
make xcodegen

# 3. 安装依赖
make deps

# 4. 打开项目
open Alisa.xcodeproj
```

### 构建与运行

```bash
# Debug 构建
make build

# 运行测试
make test

# 打包（未签名）
make build-unsigned
```

## 项目结构

```
Alisa/
├── Sources/
│   ├── App/           # App 入口
│   │   └── AlisaApp.swift
│   ├── Core/          # 核心业务逻辑
│   │   ├── Data/      # 数据模型、DatabaseManager、Keychain、Repositories
│   │   ├── AI/        # AI 客户端、HTTPClient、StreamParser、ToolExecutor
│   │   ├── Config/    # ConfigManager、RoleManager、ParameterManager、ProjectManager
│   │   ├── Preview/   # PreviewServerManager
│   │   └── Backup/    # BackupManager
│   ├── UI/            # UI 组件
│   │   ├── Views/     # ContentView、OnboardingView
│   │   └── Components/ # 可复用组件
│   └── Features/      # 功能模块
│       ├── Projects/  # 项目列表、新建/导入
│       ├── Editor/    # 代码编辑器、文件树、标签页
│       ├── Chat/      # AI 对话、消息气泡、流式输出
│       └── Settings/  # API 配置、AI 参数、角色管理、备份
├── Tests/
│   ├── Unit/          # 单元测试
│   ├── Integration/   # 集成测试
│   └── UI/            # UI 测试
├── project.yml        # XcodeGen 配置
├── Info.plist
├── Makefile
└── Package.swift      # SPM 依赖
```

## 架构

分层架构，从下到上：

1. **数据层**: GRDB SQLite + Keychain + 文件系统沙盒
2. **业务逻辑层**: Manager 类（ConfigManager/AIClient/ProjectManager 等）
3. **UI 层**: SwiftUI 视图 + 状态管理 (ObservableObject)
4. **网络层**: URLSession HTTP/流式客户端 + GCDWebServer 本地预览

## 配置

首次启动时，通过引导流程配置：

1. API 地址（兼容 OpenAI 格式的任意服务）
2. API Key（Keychain 加密存储）
3. 模型名称
4. 选择默认角色

## 许可证

MIT