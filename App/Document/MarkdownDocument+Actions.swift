import AppKit
import MacMDKit

/// Menu actions that act on the whole document. They reach the document through the
/// responder chain (window controller → document), so they work from any focused view.
extension MarkdownDocument {
    @objc func toggleReadMode(_ sender: Any?) { model.toggleMode() }
    @objc func toggleFocusMode(_ sender: Any?) { model.toggleFocusMode() }
    @objc func toggleTypewriterMode(_ sender: Any?) { model.toggleTypewriterMode() }
    @objc func toggleDocumentSidebar(_ sender: Any?) { model.toggleSidebar() }
    @objc func showOutline(_ sender: Any?) { model.showSidebar(.outline) }
    @objc func showFiles(_ sender: Any?) { model.showSidebar(.files) }

    @objc func exportHTML(_ sender: Any?) {
        guard let window = windowControllers.first?.window else { return }
        Exporter.exportHTML(markdown: model.text, directory: directory, suggestedName: exportName, window: window)
    }

    @objc func exportPDF(_ sender: Any?) {
        guard let window = windowControllers.first?.window else { return }
        Exporter.exportPDF(markdown: model.text, directory: directory, suggestedName: exportName, window: window)
    }

    @objc func copyAsHTML(_ sender: Any?) {
        let html = HTMLRenderer.render(model.text).body
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(html, forType: .html)
        pasteboard.setString(html, forType: .string)
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleReadMode(_:)):
            menuItem.title = model.mode == .edit ? "Read Mode" : "Edit Mode"
        case #selector(toggleDocumentSidebar(_:)):
            menuItem.title = model.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar"
        case #selector(toggleFocusMode(_:)):
            menuItem.state = model.isFocusMode ? .on : .off
            return model.mode == .edit  // both modes shape the editor only
        case #selector(toggleTypewriterMode(_:)):
            menuItem.state = model.isTypewriterMode ? .on : .off
            return model.mode == .edit
        default:
            break
        }
        return super.validateMenuItem(menuItem)
    }

    private var directory: URL? { fileURL?.deletingLastPathComponent() }
    private var exportName: String { fileURL?.deletingPathExtension().lastPathComponent ?? displayName ?? "Untitled" }
}
