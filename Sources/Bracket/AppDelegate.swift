import AppKit
import WebKit
import UniformTypeIdentifiers
import BracketCore

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, NSToolbarDelegate {
    private(set) var window: NSWindow!
    private(set) var webView: DropWebView!
    private(set) var server: LocalServer!
    private(set) var baseURL: URL?
    private(set) var currentFile: URL?
    private var pendingFile: URL?
    private var reloadButton: NSButton!
    private var popups: [NSWindow] = []
    private var smokeCheck: SmokeCheck?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildWindow()
        #if SWIFT_PACKAGE
        // SwiftPM keeps resources in a separate bundle.
        let packagedBundle = Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("Bracket_Bracket.bundle")) }
        let resourceBundle = packagedBundle ?? Bundle.module
        let roots = [resourceBundle.bundleURL, resourceBundle.resourceURL].compactMap { $0 }
        let webDirectories = roots.map { $0.appendingPathComponent("Resources/Web", isDirectory: true) }
        #else
        // Xcode copies the Web folder directly into the app's resources.
        let webDirectories = [Bundle.main.resourceURL!.appendingPathComponent("Web", isDirectory: true)]
        #endif
        guard let resources = webDirectories
            .first(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("index.html").path) }) else {
            showError("The viewer files are missing", detail: "Build Bracket again with scripts/build.sh.")
            window.makeKeyAndOrderFront(nil)
            return
        }
        server = LocalServer(webRoot: resources, iconPNG: appIconPNG())
        do {
            try server.start { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let url):
                    self.baseURL = url
                    if let pendingFile = self.pendingFile {
                        self.pendingFile = nil
                        self.openDocument(pendingFile)
                    } else {
                        self.webView.load(URLRequest(url: url))
                    }
                    if let options = SmokeCheck.Options(arguments: CommandLine.arguments) {
                        self.smokeCheck = SmokeCheck(app: self, options: options)
                        self.smokeCheck?.start()
                    } else if let file = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("-") && APIDocument.extensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }) {
                        self.openDocument(URL(fileURLWithPath: file))
                    }
                case .failure(let error):
                    self.showError("The local viewer could not start", detail: error.localizedDescription)
                }
            }
        } catch {
            showError("The local viewer could not start", detail: error.localizedDescription)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.count == 1, let url = urls.first else {
            if window != nil { showError("Open one file at a time", detail: "Drop or select one JSON or YAML definition.") }
            return
        }
        guard baseURL != nil else { pendingFile = url; return }
        openDocument(url)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "bracket")
        server?.stop()
    }

    private func appIconPNG() -> Data? {
        let image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: 256, height: 256), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }

    @objc func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Open an API definition"
        panel.prompt = "Open"
        panel.allowedContentTypes = [.json, UTType(filenameExtension: "yaml") ?? .text, UTType(filenameExtension: "yml") ?? .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = panel.url { self?.openDocument(url) }
        }
    }

    func openDocument(_ url: URL) {
        guard let baseURL else { pendingFile = url; return }
        do {
            let document = try APIDocument(url: url)
            let path = server.select(document)
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "document", value: path), URLQueryItem(name: "name", value: document.url.lastPathComponent)]
            currentFile = url
            window.title = document.url.lastPathComponent
            window.subtitle = "Bracket"
            window.representedURL = url
            reloadButton.isEnabled = true
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            webView.load(URLRequest(url: components.url!))
        } catch {
            showError("Could not open \(url.lastPathComponent)", detail: error.localizedDescription)
        }
    }

    @objc func reloadFile() {
        if let currentFile { openDocument(currentFile) }
    }

    @objc private func zoomIn() { webView.pageZoom = min(webView.pageZoom + 0.1, 2) }
    @objc private func zoomOut() { webView.pageZoom = max(webView.pageZoom - 0.1, 0.6) }
    @objc private func actualSize() { webView.pageZoom = 1 }

    private func buildWindow() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(self, name: "bracket")
        webView = DropWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsMagnification = true
        webView.registerForDraggedTypes([.fileURL])
        webView.openFile = { [weak self] url in self?.openDocument(url) }
        webView.rejectDrop = { [weak self] in
            self?.showError("Open one file at a time", detail: "Drop one JSON or YAML definition into the window.")
        }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1160, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Bracket"
        window.subtitle = "Swagger UI for local API files"
        window.minSize = NSSize(width: 640, height: 480)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("BracketMainWindow")
        let toolbar = NSToolbar(identifier: "BracketToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.center()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, .init("reload"), .init("open")] }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarAllowedItemIdentifiers(toolbar) }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        switch identifier.rawValue {
        case "open":
            let button = NSButton(title: "Open…", target: self, action: #selector(chooseFile))
            button.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            button.bezelStyle = .texturedRounded
            button.toolTip = "Open a JSON or YAML file (⌘O)"
            item.view = button
            item.label = "Open"
        case "reload":
            reloadButton = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload file")!, target: self, action: #selector(reloadFile))
            reloadButton.bezelStyle = .texturedRounded
            reloadButton.isEnabled = false
            reloadButton.toolTip = "Reload the file from disk (⌘R)"
            item.view = reloadButton
            item.label = "Reload"
        default: return nil
        }
        return item
    }

    private func buildMenu() {
        let menu = NSMenu()
        let application = NSMenu()
        application.addItem(withTitle: "About Bracket", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        application.addItem(.separator())
        application.addItem(withTitle: "Hide Bracket", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        application.addItem(.separator())
        application.addItem(withTitle: "Quit Bracket", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let applicationItem = NSMenuItem()
        applicationItem.submenu = application
        menu.addItem(applicationItem)
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Open…", action: #selector(chooseFile), keyEquivalent: "o").target = self
        file.addItem(withTitle: "Reload File", action: #selector(reloadFile), keyEquivalent: "r").target = self
        file.addItem(.separator())
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        addMenu(file, to: menu)
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        addMenu(edit, to: menu)
        let view = NSMenu(title: "View")
        for (title, action, key) in [("Zoom In", #selector(zoomIn), "+"), ("Zoom Out", #selector(zoomOut), "-"), ("Actual Size", #selector(actualSize), "0")] {
            view.addItem(withTitle: title, action: action, keyEquivalent: key).target = self
        }
        addMenu(view, to: menu)
        let windows = NSMenu(title: "Window")
        windows.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windows.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        addMenu(windows, to: menu)
        NSApp.windowsMenu = windows
        NSApp.mainMenu = menu
    }

    private func addMenu(_ submenu: NSMenu, to menu: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let source = message.frameInfo.request.url,
              source.host == baseURL?.host, source.port == baseURL?.port,
              source.path.hasPrefix(baseURL?.path ?? "invalid"),
              let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        if action == "open" { chooseFile() }
        if action == "drop" { webView.loadDroppedFiles(from: NSPasteboard(name: .drag)) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.scheme == "about" || (url.host == baseURL?.host && url.port == baseURL?.port && url.path.hasPrefix(baseURL?.path ?? "invalid")) {
            decisionHandler(.allow)
        } else {
            if navigationAction.navigationType == .linkActivated, ["http", "https", "mailto"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil, let scheme = navigationAction.request.url?.scheme, ["http", "https"].contains(scheme) else { return nil }
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.uiDelegate = self
        let popupWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 760), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        popupWindow.title = "API Authorization"
        popupWindow.contentView = popup
        popupWindow.isReleasedWhenClosed = false
        popups.append(popupWindow)
        popupWindow.center()
        popupWindow.makeKeyAndOrderFront(nil)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        popups.first(where: { $0.contentView === webView })?.close()
        popups.removeAll(where: { $0.contentView === webView })
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { showError("The viewer could not load", detail: "Press ⌘R to retry. \(error.localizedDescription)") }
    }

    func showError(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }
}
