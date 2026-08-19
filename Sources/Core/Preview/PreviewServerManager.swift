import Foundation
import GCDWebServer

// MARK: - Preview Server Manager

@MainActor
final class PreviewServerManager: ObservableObject {
    static let shared = PreviewServerManager()

    @Published private(set) var isRunning = false
    @Published private(set) var serverURL: URL?
    @Published private(set) var currentProjectID: UUID?
    @Published private(set) var error: String?

    private var webServer: GCDWebServer?
    private let portRange = 8080...8099

    private init() {}

    func start(for projectID: UUID, projectPath: String) async throws {
        stop()

        for port in portRange {
            do {
                try await startServer(on: port, projectPath: projectPath)
                self.currentProjectID = projectID
                self.isRunning = true
                self.serverURL = URL(string: "http://localhost:\(port)")
                self.error = nil
                return
            } catch {
                continue
            }
        }

        throw PreviewError.allPortsInUse
    }

    private func startServer(on port: Int, projectPath: String) async throws {
        webServer = GCDWebServer()

        // Add hot reload script injection for HTML files
        webServer?.addHandler(forMethod: "GET", path: "/", request: GCDWebServerRequest.self) { [weak self] request, completion in
            self?.handleRootRequest(request, projectPath: projectPath, completion: completion)
        }

        // Serve static files
        webServer?.addGETHandler(
            forBasePath: "/",
            directoryPath: projectPath,
            indexFilename: "index.html",
            cacheAge: 0,
            allowRangeRequests: true
        )

        // WebSocket endpoint for hot reload
        webServer?.addHandler(forMethod: "GET", path: "/__hotreload", request: GCDWebServerRequest.self) { request, completion in
            self.handleWebSocket(request, completion: completion)
        }

        let options: [String: Any] = [
            GCDWebServerOption_Port: port,
            GCDWebServerOption_BindToLocalhost: true,
            GCDWebServerOption_AutomaticallySuspendInBackground: false,
            GCDWebServerOption_ConnectedStateCoalescingInterval: 0.1
        ]

        try webServer?.start(options: options)
    }

    private func handleRootRequest(_ request: GCDWebServerRequest, projectPath: String, completion: @escaping (GCDWebServerResponse?) -> Void) {
        let indexPath = (projectPath as NSString).appendingPathComponent("index.html")
        if FileManager.default.fileExists(atPath: indexPath) {
            do {
                var html = try String(contentsOfFile: indexPath, encoding: .utf8)
                html = injectHotReloadScript(into: html)
                let response = GCDWebServerDataResponse(htmlString: html, contentType: "text/html")
                completion(response)
            } catch {
                completion(GCDWebServerErrorResponse(statusCode: 500))
            }
        } else {
            completion(GCDWebServerErrorResponse(statusCode: 404))
        }
    }

    private func injectHotReloadScript(into html: String) -> String {
        let script = """
        <script>
        (function() {
            var ws = new WebSocket('ws://localhost:8080/__hotreload');
            ws.onmessage = function(event) {
                if (event.data === 'reload') {
                    window.location.reload();
                }
            };
            ws.onclose = function() {
                setTimeout(function() { window.location.reload(); }, 1000);
            };
        })();
        </script>
        """
        if html.contains("</body>") {
            return html.replacingOccurrences(of: "</body>", with: "\(script)</body>")
        } else {
            return html + script
        }
    }

    private func handleWebSocket(_ request: GCDWebServerRequest, completion: @escaping (GCDWebServerResponse?) -> Void) {
        // Simplified: GCDWebServer doesn't have built-in WebSocket support
        // In production, use a proper WebSocket library like Starscream
        let response = GCDWebServerDataResponse(text: "WebSocket endpoint - use proper WebSocket library")
        completion(response)
    }

    func stop() {
        webServer?.stop()
        webServer = nil
        isRunning = false
        serverURL = nil
        currentProjectID = nil
        error = nil
    }

    func reload() {
        // Trigger hot reload for connected clients
        // In production, broadcast to WebSocket connections
    }
}

enum PreviewError: LocalizedError {
    case allPortsInUse
    case serverStartFailed(String)
    case projectNotFound

    var errorDescription: String? {
        switch self {
        case .allPortsInUse: return "所有预览端口均被占用 (8080-8099)"
        case .serverStartFailed(let msg): return "预览服务器启动失败: \(msg)"
        case .projectNotFound: return "项目不存在"
        }
    }
}