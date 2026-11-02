import AppKit
import WebKit
import BracketCore

final class DropWebView: WKWebView {
    var openFile: ((URL) -> Void)?
    var rejectDrop: (() -> Void)?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasFileURLs(sender) else { return super.draggingEntered(sender) }
        showDropTarget(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        hasFileURLs(sender) ? .copy : super.draggingUpdated(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        showDropTarget(false)
        super.draggingExited(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hasFileURLs(sender) || super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard hasFileURLs(sender) else { return super.performDragOperation(sender) }
        showDropTarget(false)
        return loadDroppedFiles(from: sender.draggingPasteboard)
    }

    @discardableResult
    func loadDroppedFiles(from pasteboard: NSPasteboard) -> Bool {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard urls.count == 1, let url = urls.first else { rejectDrop?(); return false }
        openFile?(url)
        return true
    }

    private func hasFileURLs(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    private func showDropTarget(_ visible: Bool) {
        evaluateJavaScript("window.bracket?.showDropTarget(\(visible))", completionHandler: nil)
    }
}
