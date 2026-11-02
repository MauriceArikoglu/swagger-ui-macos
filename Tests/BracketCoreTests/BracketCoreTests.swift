import XCTest
import Foundation
@testable import BracketCore

final class BracketCoreTests: XCTestCase {
    private var root: URL!
    private var web: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("bracket-test-\(UUID().uuidString)", isDirectory: true)
        web = root.appendingPathComponent("web", isDirectory: true)
        try FileManager.default.createDirectory(at: web, withIntermediateDirectories: true)
        try "<!doctype html><title>Test viewer</title>".write(to: web.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func write(_ name: String, text: String = "openapi: 3.0.3\ninfo: {title: Test, version: 1.0}\npaths: {}") throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testJSONAndYAMLExtensionsIncludingUppercase() throws {
        for name in ["spec.json", "spec.yaml", "spec.yml", "spec.YAML", "spec.JSON"] {
            XCTAssertFalse(try APIDocument(url: write(name)).data.isEmpty)
        }
    }

    func testRejectsUnsupportedEmptyAndNonUTF8Files() throws {
        XCTAssertThrowsError(try APIDocument(url: write("spec.txt")))
        XCTAssertThrowsError(try APIDocument(url: write("empty.yaml", text: " \n\t")))
        let invalid = root.appendingPathComponent("invalid.json")
        try Data([0xff, 0xfe]).write(to: invalid)
        XCTAssertThrowsError(try APIDocument(url: invalid))
        let directory = root.appendingPathComponent("folder.yaml")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        XCTAssertThrowsError(try APIDocument(url: directory))
    }

    func testRejectsOversizedFilesBeforeReading() throws {
        let url = try write("large.json", text: "")
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(APIDocument.maximumSize + 1))
        try handle.close()
        XCTAssertThrowsError(try APIDocument(url: url)) { error in
            XCTAssertEqual(error as? DocumentError, .tooLarge)
        }
    }

    func testOnlyServesAssetsUnderProcessToken() throws {
        let server = LocalServer(webRoot: web)
        XCTAssertEqual(server.response(method: "GET", target: "/").status, 404)
        XCTAssertEqual(server.response(method: "GET", target: "/wrong/index.html").status, 404)
        XCTAssertEqual(server.response(method: "GET", target: "/\(server.token)/").status, 200)
        XCTAssertEqual(server.response(method: "POST", target: "/\(server.token)/").status, 405)
        XCTAssertEqual(server.response(method: "GET", target: "/\(server.token)/../spec.yaml").status, 403)
        XCTAssertEqual(server.response(method: "GET", target: "/\(server.token)/%2e%2e/spec.yaml").status, 403)
        XCTAssertEqual(server.response(method: "GET", target: "/\(server.token)/%00").status, 404)
    }

    func testSelectedDocumentSnapshotAndEncodedFilename() throws {
        let server = LocalServer(webRoot: web)
        let url = try write("API #1 ? 100%.YAML")
        let document = try APIDocument(url: url)
        let route = server.select(document)
        XCTAssertTrue(route.contains("%23"))
        let target = "/\(server.token)/\(route)"
        XCTAssertEqual(server.response(method: "GET", target: target).data, document.data)
        try "changed".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(server.response(method: "GET", target: target).data, document.data)
        let newRoute = server.select(try APIDocument(url: url))
        XCTAssertEqual(server.response(method: "GET", target: target).status, 404)
        XCTAssertEqual(String(data: server.response(method: "GET", target: "/\(server.token)/\(newRoute)").data, encoding: .utf8), "changed")
    }

    func testLocalReferencesAreLimitedToDocumentFolder() throws {
        let server = LocalServer(webRoot: web)
        let url = try write("api/spec.yaml")
        let route = server.select(try APIDocument(url: url))
        let base = String(route.prefix(upTo: route.lastIndex(of: "/")!))
        let reference = try write("api/schemas/thing.json", text: "{\"type\":\"object\"}")
        XCTAssertEqual(server.response(method: "GET", target: "/\(server.token)/\(base)/schemas/thing.json").data, try Data(contentsOf: reference))
        _ = try write("api/private.txt", text: "Not an API file")
        XCTAssertEqual(server.response(method: "GET", target: "/\(server.token)/\(base)/private.txt").status, 403)
        XCTAssertEqual(server.response(method: "GET", target: "/\(server.token)/\(base)/%2e%2e/outside.json").status, 403)
        let secret = try write("outside.json", text: "{\"secret\":true}")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("api/link.json"), withDestinationURL: secret)
        XCTAssertEqual(server.response(method: "GET", target: "/\(server.token)/\(base)/link.json").status, 403)
    }

    func testLiveHTTPGetAndHead() throws {
        let server = LocalServer(webRoot: web)
        defer { server.stop() }
        let started = expectation(description: "loopback listener starts")
        var baseURL: URL?
        try server.start { result in
            if case .success(let url) = result { baseURL = url } else { XCTFail("Listener failed: \(result)") }
            started.fulfill()
        }
        wait(for: [started], timeout: 5)
        let url = try XCTUnwrap(baseURL)
        XCTAssertEqual(url.host, "127.0.0.1")
        let get = expectation(description: "GET returns bundle bytes")
        URLSession.shared.dataTask(with: url) { data, response, error in
            XCTAssertNil(error)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            XCTAssertTrue(String(data: data ?? Data(), encoding: .utf8)?.contains("Test viewer") == true)
            XCTAssertEqual((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Cache-Control"), "no-store")
            get.fulfill()
        }.resume()
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        let head = expectation(description: "HEAD has no body")
        URLSession.shared.dataTask(with: request) { data, response, error in
            XCTAssertNil(error)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            XCTAssertEqual(data?.count, 0)
            head.fulfill()
        }.resume()
        wait(for: [get, head], timeout: 5)
    }
}
