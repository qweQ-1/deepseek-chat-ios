import Foundation
import Network

/// 极简本地静态文件服务器。
///
/// 职责：把 App 内置的 DeepSeek 官方前端产物，用 `http://127.0.0.1:<port>/` 交给 WKWebView。
/// 为什么需要它：`file://` 源下 WebKit 会限制 localStorage / IndexedDB，而该前端把全部会话与附件
/// 原件都存在 IndexedDB 里，直接用 loadFileURL 会导致「历史记录一关就没」。
/// 端口固定，保证 origin 稳定 —— origin 变了 localStorage / IndexedDB 就换了一套。
final class LocalStaticServer {

    /// 固定端口；被占用时自动退回系统分配的端口
    static let preferredPort: UInt16 = 47823

    private let root: URL
    private let queue = DispatchQueue(label: "com.qweq-1.deepseekchat.local-server")
    private var listener: NWListener?

    /// 实际监听端口（就绪后才有值）
    private(set) var port: UInt16 = 0

    /// 启动失败的原因，供上层展示
    enum ServerError: LocalizedError {
        case cannotStart(String)
        case contentMissing

        var errorDescription: String? {
            switch self {
            case .cannotStart(let reason):
                return "本地服务启动失败：\(reason)"
            case .contentMissing:
                return "App 内置页面缺失（Web/index.html）"
            }
        }
    }

    init(root: URL) {
        self.root = root
    }

    /// 启动并等待就绪
    static func start(preferredPort: UInt16 = LocalStaticServer.preferredPort) throws -> LocalStaticServer {
        guard let root = Bundle.main.url(forResource: "Web", withExtension: nil),
              FileManager.default.fileExists(atPath: root.appendingPathComponent("index.html").path) else {
            throw ServerError.contentMissing
        }
        let server = LocalStaticServer(root: root)
        try server.start(preferredPort: preferredPort)
        return server
    }

    var origin: URL? {
        guard port != 0 else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/")
    }

    private func start(preferredPort: UInt16) throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        var failure: String?
        for candidate in [NWEndpoint.Port(rawValue: preferredPort) ?? .any, .any] {
            do {
                let listener = try NWListener(using: parameters, on: candidate)
                let semaphore = DispatchSemaphore(value: 0)
                var readyError: String?
                var boundPort: UInt16 = 0

                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        boundPort = listener.port?.rawValue ?? 0
                        semaphore.signal()
                    case .failed(let error):
                        readyError = error.localizedDescription
                        semaphore.signal()
                    case .cancelled:
                        semaphore.signal()
                    default:
                        break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    self?.accept(connection)
                }

                self.listener = listener
                listener.start(queue: queue)

                if semaphore.wait(timeout: .now() + 3) == .timedOut {
                    listener.cancel()
                    failure = "启动超时"
                    continue
                }
                if let readyError {
                    listener.cancel()
                    failure = readyError
                    continue
                }
                if boundPort != 0 {
                    port = boundPort
                    return
                }
                listener.cancel()
                failure = "没有分配到端口"
            } catch {
                failure = error.localizedDescription
            }
        }
        throw ServerError.cannotStart(failure ?? "未知原因")
    }

    // MARK: - 连接处理

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        readRequest(on: connection, buffer: Data())
    }

    private func readRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data {
                buffer.append(data)
            }
            if buffer.count > 128 * 1024 {
                connection.cancel()
                return
            }
            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
                self.respond(to: head, on: connection)
                return
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.readRequest(on: connection, buffer: buffer)
        }
    }

    private struct RequestHead {
        var method: String
        var path: String
        var headers: [String: String]
    }

    private func parse(_ head: String) -> RequestHead? {
        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        return RequestHead(method: String(parts[0]), path: String(parts[1]), headers: headers)
    }

    private func respond(to head: String, on connection: NWConnection) {
        guard let request = parse(head) else {
            send(status: 400, reason: "Bad Request", mime: "text/plain",
                 body: Data("Bad Request".utf8), on: connection)
            return
        }
        if request.method != "GET" && request.method != "HEAD" {
            send(status: 405, reason: "Method Not Allowed", mime: "text/plain",
                 body: Data("Method Not Allowed".utf8), on: connection)
            return
        }

        var path = request.path
        if let question = path.firstIndex(of: "?") { path = String(path[..<question]) }
        if let hash = path.firstIndex(of: "#") { path = String(path[..<hash]) }
        path = path.removingPercentEncoding ?? path
        if path.isEmpty || path == "/" { path = "/index.html" }
        if !path.hasPrefix("/") { path = "/" + path }

        let rootPath = root.standardizedFileURL.path
        let candidate = root.appendingPathComponent(String(path.dropFirst())).standardizedFileURL
        var fileURL = candidate
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory)

        if !candidate.path.hasPrefix(rootPath) || !exists || isDirectory.boolValue {
            // 单页应用：未知路径一律回落到 index.html
            fileURL = root.appendingPathComponent("index.html")
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            send(status: 404, reason: "Not Found", mime: "text/plain",
                 body: Data("Not Found".utf8), on: connection)
            return
        }

        let mime = LocalStaticServer.mimeType(for: fileURL.pathExtension)
        let range = Self.parseRange(request.headers["range"], total: data.count)

        if let range {
            let slice = data.subdata(in: range)
            var headers = [
                "Content-Type": mime,
                "Content-Length": "\(slice.count)",
                "Content-Range": "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(data.count)",
                "Accept-Ranges": "bytes",
                "Cache-Control": "no-cache",
                "Connection": "close",
            ]
            headers["Content-Length"] = "\(slice.count)"
            sendRaw(headers: headers, status: 206, reason: "Partial Content",
                    body: request.method == "HEAD" ? Data() : slice,
                    declaredLength: slice.count, on: connection)
            return
        }

        let headers = [
            "Content-Type": mime,
            "Content-Length": "\(data.count)",
            "Accept-Ranges": "bytes",
            "Cache-Control": "no-cache",
            "Connection": "close",
        ]
        sendRaw(headers: headers, status: 200, reason: "OK",
                body: request.method == "HEAD" ? Data() : data,
                declaredLength: data.count, on: connection)
    }

    private func send(status: Int, reason: String, mime: String, body: Data, on connection: NWConnection) {
        let headers = [
            "Content-Type": mime,
            "Content-Length": "\(body.count)",
            "Connection": "close",
        ]
        sendRaw(headers: headers, status: status, reason: reason, body: body,
                declaredLength: body.count, on: connection)
    }

    private func sendRaw(headers: [String: String], status: Int, reason: String,
                         body: Data, declaredLength: Int, on connection: NWConnection) {
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
            head += "\(key): \(value)\r\n"
        }
        head += "\r\n"
        var payload = Data(head.utf8)
        payload.append(body)
        connection.send(content: payload, isComplete: true,
                        completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func parseRange(_ value: String?, total: Int) -> Range<Int>? {
        guard let value, value.hasPrefix("bytes="), total > 0 else { return nil }
        let spec = value.dropFirst("bytes=".count)
        let parts = spec.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let startText = String(parts[0]).trimmingCharacters(in: .whitespaces)
        let endText = String(parts[1]).trimmingCharacters(in: .whitespaces)
        if startText.isEmpty {
            guard let suffix = Int(endText), suffix > 0 else { return nil }
            let start = max(0, total - suffix)
            return start..<total
        }
        guard let start = Int(startText), start >= 0, start < total else { return nil }
        var end = total
        if !endText.isEmpty, let parsed = Int(endText) {
            end = min(parsed + 1, total)
        }
        guard start < end else { return nil }
        return start..<end
    }

    private static func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json", "map": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "ico": return "image/x-icon"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "wasm": return "application/wasm"
        case "txt", "md": return "text/plain; charset=utf-8"
        case "license": return "text/plain; charset=utf-8"
        default: return "application/octet-stream"
        }
    }
}
