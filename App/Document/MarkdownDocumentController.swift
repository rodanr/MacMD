import AppKit

/// The app's document controller: new documents start in the folder you're working in, and the Open panel
/// can create a file where it's looking.
final class MarkdownDocumentController: NSDocumentController {
    private var newFileButton: OpenPanelNewFileButton?

    /// ⌘N from a document: the new one browses the same folder, and Save suggests it.
    override func makeUntitledDocument(ofType typeName: String) throws -> NSDocument {
        let document = try super.makeUntitledDocument(ofType: typeName)
        if let source = currentDocument as? MarkdownDocument, let document = document as? MarkdownDocument {
            document.model.browsedFolder = source.model.browsedFolder ?? source.fileURL?.deletingLastPathComponent()
        }
        return document
    }

    override func beginOpenPanel(
        _ openPanel: NSOpenPanel, forTypes inTypes: [String]?, completionHandler: @escaping (Int) -> Void
    ) {
        let button = OpenPanelNewFileButton(panel: openPanel)
        newFileButton = button
        openPanel.accessoryView = button.view
        openPanel.isAccessoryViewDisclosed = true
        super.beginOpenPanel(openPanel, forTypes: inTypes) { [weak self] result in
            MainActor.assumeIsolated { self?.newFileButton = nil }
            completionHandler(result)
        }
    }
}

/// "New File Here…" under the Open panel: creates a Markdown file in the folder the panel shows and opens it.
@MainActor
private final class OpenPanelNewFileButton: NSObject {
    private weak var panel: NSOpenPanel?
    let view: NSView

    init(panel: NSOpenPanel) {
        self.panel = panel
        let button = NSButton(title: "New File Here…", target: nil, action: nil)
        let container = NSView()
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])
        view = container
        super.init()
        button.target = self
        button.action = #selector(createFile)
    }

    @objc private func createFile() {
        guard let panel, let folder = panel.directoryURL, let url = NewFile.askAndCreate(in: folder) else { return }
        panel.cancel(nil)
        // Opened once the panel has gone.
        Task { LinkRouter.openFile(url, browsing: folder) }
    }
}
