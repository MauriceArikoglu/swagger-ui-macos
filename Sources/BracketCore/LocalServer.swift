import Foundation
import Network

public struct HTTPResponse {
    public let status: Int
    public let contentType: String
    public let data: Data

    static func error(_ status: Int, _ message: String) -> HTTPResponse {
        HTTPResponse(status: status, contentType: "text/plain; charset=utf-8", data: Data(message.utf8))
    }
}

/// Serves bundled assets and the selected definition on IPv4 loopback only.
/// An unguessable route prefix isolates each process. No API proxy is installed.
public final class LocalServer {
    public let token = UUID().uuidString.lowercased()
    private let webRoot: URL
    private let iconPNG: Data?
    private let queue = DispatchQueue(label: "app.bracket.http")
    private let lock = NSLock()
    private var listener: NWListener?
    private var document: APIDocument?
    private var documentID = ""
    private var connections: [UUID: NWConnection] = [:]

    public init(webRoot: URL, iconPNG: Data? = nil) {
        self.webRoot = webRoot.standardizedFileURL.resolvingSymlinksInPath()
        self.iconPNG = iconPNG
    }

    public func start(completion: @escaping (Result<URL, Error>) -> Void) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        var completed = false
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                guard !completed, let port = listener.port else { return }
                completed = true
                let url = URL(string: "http://127.0.0.1:\(port.rawValue)/\(self.token)/")!
                DispatchQueue.main.async { completion(.success(url)) }
            case .failed(let error):
                guard !completed else { return }
                completed = true
                DispatchQueue.main.async { completion(.failure(error)) }
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
    }

    public func stop() {
        listener?.cancel()
        queue.async { [weak self] in
            self?.connections.values.forEach { $0.cancel() }
            self?.connections.removeAll()
        }
    }

    /// Returns the URL relative to the server root. Rotating the ID invalidates old document routes.
    public func select(_ document: APIDocument) -> String {
        lock.lock()
        defer { lock.unlock() }
        self.document = document
        documentID = UUID().uuidString.lowercased()
        let name = document.url.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathSegment)!
        return "documents/\(documentID)/\(name)"
    }

    public func response(method: String, target: String) -> HTTPResponse {
        guard method == "GET" || method == "HEAD" else { return .error(405, "Method not allowed") }
        guard target.hasPrefix("/"),
              let encodedPath = target.split(separator: "?", maxSplits: 1).first,
              let path = String(encodedPath).removingPercentEncoding,
              !path.contains("\0"), !path.contains("\\"),
              path.hasPrefix("/\(token)/") else { return .error(404, "Not found") }
        let relative = String(path.dropFirst(token.count + 2))
        guard !relative.split(separator: "/").contains("..") else { return .error(403, "Path is outside the document folder") }
        if relative == "app-icon.png", let iconPNG {
            return HTTPResponse(status: 200, contentType: "image/png", data: iconPNG)
        }
        lock.lock()
        let activeDocument = document
        let activeID = documentID
        lock.unlock()

        if relative.hasPrefix("documents/") {
            guard let activeDocument, relative.hasPrefix("documents/\(activeID)/") else {
                return .error(404, "No matching document is open")
            }
            let filePath = String(relative.dropFirst("documents/\(activeID)/".count))
            if filePath == activeDocument.url.lastPathComponent {
                return HTTPResponse(status: 200, contentType: mimeType(activeDocument.url), data: activeDocument.data)
            }
            let root = activeDocument.url.deletingLastPathComponent()
            let url = root.appendingPathComponent(filePath).standardizedFileURL.resolvingSymlinksInPath()
            guard url.path.hasPrefix(root.path + "/"), APIDocument.extensions.contains(url.pathExtension.lowercased()) else {
                return .error(403, "Only JSON and YAML references within the document folder are available")
            }
            guard let reference = try? APIDocument(url: url) else { return .error(404, "Reference file not found") }
            return HTTPResponse(status: 200, contentType: mimeType(url), data: reference.data)
        }

        let asset = relative.isEmpty ? "index.html" : relative
        let url = webRoot.appendingPathComponent(asset).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(webRoot.path + "/"),
              ["html", "css", "js", "svg", "png"].contains(url.pathExtension.lowercased()),
              let data = try? Data(contentsOf: url) else { return .error(404, "Asset not found") }
        return HTTPResponse(status: 200, contentType: mimeType(url), data: data)
    }

    private func mimeType(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js": return "application/javascript; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "yaml", "yml": return "application/yaml; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        default: return "application/octet-stream"
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = UUID()
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state { self?.connections.removeValue(forKey: id) }
            if case .failed = state { connection.cancel() }
        }
        connection.start(queue: queue)
        receive(connection, buffer: Data())
        // Bound incomplete clients without keeping a strong reference to closed connections.
        queue.asyncAfter(deadline: .now() + 15) { [weak connection] in connection?.cancel() }
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            guard buffer.count <= 16384 else {
                self.send(.error(431, "Request headers too large"), to: connection, headOnly: false)
                return
            }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)),
               let headers = String(data: buffer[..<end.lowerBound], encoding: .utf8),
               let line = headers.components(separatedBy: "\r\n").first {
                let parts = line.split(separator: " ")
                guard parts.count == 3 else {
                    self.send(.error(400, "Invalid HTTP request"), to: connection, headOnly: false)
                    return
                }
                let method = String(parts[0])
                self.send(self.response(method: method, target: String(parts[1])), to: connection, headOnly: method == "HEAD")
            } else if complete || error != nil {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private func send(_ response: HTTPResponse, to connection: NWConnection, headOnly: Bool) {
        let reason = [200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 431: "Request Header Fields Too Large"][response.status] ?? "Error"
        let headers = "HTTP/1.1 \(response.status) \(reason)\r\nContent-Type: \(response.contentType)\r\nContent-Length: \(response.data.count)\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n\r\n"
        var packet = Data(headers.utf8)
        if !headOnly { packet.append(response.data) }
        connection.send(content: packet, completion: .contentProcessed { _ in connection.cancel() })
    }
}

private extension CharacterSet {
    static let urlPathSegment = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))
}
