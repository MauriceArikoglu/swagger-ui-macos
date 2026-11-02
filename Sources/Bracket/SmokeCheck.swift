import AppKit
import WebKit

/// Opt-in integration check against the actual bundled WKWebView, without API requests.
final class SmokeCheck {
    struct Options {
        let file: URL
        let output: URL

        init?(arguments: [String]) {
            guard let index = arguments.firstIndex(of: "--smoke-test"), arguments.indices.contains(index + 1),
                  let outputIndex = arguments.firstIndex(of: "--smoke-output"), arguments.indices.contains(outputIndex + 1) else { return nil }
            file = URL(fileURLWithPath: arguments[index + 1])
            output = URL(fileURLWithPath: arguments[outputIndex + 1], isDirectory: true)
        }
    }

    private unowned let app: AppDelegate
    private let options: Options
    private var checks: [String] = []
    private var fixtures: URL { options.output.appendingPathComponent("fixtures", isDirectory: true) }

    init(app: AppDelegate, options: Options) { self.app = app; self.options = options }

    func start() {
        do { try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true) }
        catch { finish(error: error.localizedDescription); return }
        app.window.setContentSize(NSSize(width: 1160, height: 760))
        waitFor("empty state uses the native app icon", condition: "window.bracket?.state.status === 'empty' && document.querySelector('.app-mark').naturalWidth === 256") { [self] in
            capture("empty.png") {
                self.app.window.setContentSize(NSSize(width: 640, height: 480))
                self.capture("empty-compact.png") {
                    self.app.window.setContentSize(NSSize(width: 1160, height: 760))
                    self.drop(self.options.file)
                    self.waitFor("YAML file drop", condition: "window.bracket?.state.status === 'ready' && window.bracket.state.operations > 0 && window.bracket.state.errors.length === 0 && document.querySelectorAll('.opblock').length > 0") {
                        self.capture("loaded.png") {
                            self.app.window.setContentSize(NSSize(width: 640, height: 650))
                            self.capture("loaded-compact.png") {
                                self.app.window.setContentSize(NSSize(width: 1160, height: 760))
                                self.checkJSON()
                            }
                        }
                    }
                }
            }
        }
    }

    private func checkJSON() {
        do {
            let url = fixtures.appendingPathComponent("definition with spaces #1.json")
            try json(title: "JSON smoke check").write(to: url, atomically: true, encoding: .utf8)
            drop(url)
            waitFor("JSON file drop and encoded filename", condition: "window.bracket?.state.title === 'JSON smoke check' && window.bracket.state.operations === 1") { [self] in
                app.webView.evaluateJavaScript("document.querySelector('.opblock-summary-control').click()") { _, _ in
                    self.waitFor("operation expands", condition: "!!document.querySelector('.opblock-body .try-out__btn')") {
                        do { try self.json(title: "Reloaded JSON").write(to: url, atomically: true, encoding: .utf8) }
                        catch { self.finish(error: error.localizedDescription); return }
                        self.app.reloadFile()
                        self.waitFor("reload reads changes from disk", condition: "window.bracket?.state.title === 'Reloaded JSON'") { self.checkLegacy() }
                    }
                }
            }
        } catch { finish(error: error.localizedDescription) }
    }

    private func checkLegacy() {
        let url = fixtures.appendingPathComponent("legacy.json")
        let source = """
        {"swagger":"2.0","info":{"title":"Legacy API","version":"1.0"},"host":"example.invalid","paths":{"/ping":{"get":{"responses":{"200":{"description":"OK"}}}}}}
        """
        do { try source.write(to: url, atomically: true, encoding: .utf8) }
        catch { finish(error: error.localizedDescription); return }
        drop(url)
        waitFor("Swagger 2.0 support", condition: "window.bracket?.state.title === 'Legacy API' && window.bracket.state.operations === 1") { self.checkInvalid() }
    }

    private func checkInvalid() {
        let url = fixtures.appendingPathComponent("invalid.yaml")
        do { try "openapi: 3.0.3\ninfo: [unterminated".write(to: url, atomically: true, encoding: .utf8) }
        catch { finish(error: error.localizedDescription); return }
        drop(url)
        waitFor("malformed YAML error", condition: "window.bracket?.state.status === 'error' && window.bracket.state.errors.length > 0 && !document.getElementById('error').hidden") {
            self.capture("error.png") {
                self.app.webView.evaluateJavaScript("performance.getEntriesByType('resource').filter(item => new URL(item.name).origin !== location.origin).map(item => item.name)") { result, error in
                    guard error == nil, let resources = result as? [String], resources.isEmpty else {
                        self.finish(error: "The viewer loaded a resource outside the bundled server")
                        return
                    }
                    self.checks.append("all viewer resources served locally")
                    self.finish(error: nil)
                }
            }
        }
    }

    private func json(title: String) -> String {
        """
        {"openapi":"3.0.3","info":{"title":"\(title)","version":"1.0"},"servers":[{"url":"https://example.invalid"}],"paths":{"/ping":{"get":{"summary":"Ping","responses":{"200":{"description":"OK"}}}}}}
        """
    }

    private func drop(_ url: URL) {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.writeObjects([url as NSURL])
        if !app.webView.loadDroppedFiles(from: pasteboard) { finish(error: "Native file drop rejected a supported file") }
        pasteboard.releaseGlobally()
    }

    private func waitFor(_ label: String, condition: String, attempts: Int = 200, then action: @escaping () -> Void) {
        app.webView.evaluateJavaScript(condition) { result, _ in
            if result as? Bool == true {
                self.checks.append(label)
                action()
            } else if attempts > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.waitFor(label, condition: condition, attempts: attempts - 1, then: action) }
            } else {
                self.app.webView.evaluateJavaScript("JSON.stringify(window.bracket?.state)") { state, _ in
                    self.finish(error: "Timed out: \(label). State: \(state ?? "unavailable")")
                }
            }
        }
    }

    private func capture(_ name: String, then action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.app.webView.takeSnapshot(with: nil) { image, error in
                guard let image, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    self.finish(error: error?.localizedDescription ?? "Could not capture the viewer")
                    return
                }
                do { try png.write(to: self.options.output.appendingPathComponent(name)); action() }
                catch { self.finish(error: error.localizedDescription) }
            }
        }
    }

    private func finish(error: String?) {
        let report: [String: Any] = ["passed": error == nil, "checks": checks, "error": error ?? NSNull()]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: options.output.appendingPathComponent("report.json"))
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
        app.server.stop()
        exit(error == nil ? 0 : 1)
    }
}
