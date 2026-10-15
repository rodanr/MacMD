import AppKit
import SwiftUI

/// The About window: identity, links, and the license, terms and acknowledgements.
struct AboutView: View {
    @State private var legal: LegalDocument?

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
            Text(AppInfo.name)
                .font(.system(size: 30, weight: .semibold, design: .serif))
                .padding(.top, 6)
            Text("Version \(AppInfo.version) (\(AppInfo.build))")
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 2)
            Text("A quiet, native Markdown editor and reader for the Mac.")
                .multilineTextAlignment(.center)
                .padding(.top, 14)

            HStack(spacing: 10) {
                Button("Website") { NSWorkspace.shared.open(AppInfo.repository) }
                Button("Report an Issue") { NSWorkspace.shared.open(AppInfo.issues) }
                Button("Check for Updates…") { UpdateChecker.checkForUpdates() }
            }
            .buttonStyle(.glass)
            .padding(.top, 20)

            Divider().padding(.vertical, 20)

            Text("Made by \(AppInfo.author)")
                .font(.callout)
            Text(AppInfo.copyright)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            HStack(spacing: 16) {
                ForEach(LegalDocument.allCases) { document in
                    Button(document.title) { legal = document }
                        .accessibilityIdentifier("legal-\(document.rawValue)")
                }
            }
            .buttonStyle(.link)
            .font(.caption)
            .padding(.top, 10)
        }
        .padding(.horizontal, 36)
        .padding(.top, 34)
        .padding(.bottom, 26)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(item: $legal) { LegalView(document: $0) }
    }
}

/// Hosts `AboutView` in a single reusable window.
@MainActor
final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()

    private init() {
        let window = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.title = "About \(AppInfo.name)"
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
