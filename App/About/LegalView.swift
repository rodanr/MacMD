import MacMDKit
import SwiftUI

/// The legal texts shown from the About window. License and terms are the repository files, bundled as-is.
enum LegalDocument: String, CaseIterable, Identifiable {
    case license, terms, acknowledgements
    var id: String { rawValue }

    var title: String {
        switch self {
        case .license: "License"
        case .terms: "Terms & Privacy"
        case .acknowledgements: "Acknowledgements"
        }
    }

    var markdown: String {
        switch self {
        case .license: Self.bundled("LICENSE")
        case .terms: Self.bundled("TERMS.md")
        case .acknowledgements: Self.acknowledgementsText
        }
    }

    private static func bundled(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: nil),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "This text is available at \(AppInfo.repository.absoluteString)." }
        return text
    }

    private static let acknowledgementsText = """
        MacMD is built on these open-source projects. Thank you to their authors and contributors.

        - **swift-markdown** and **cmark-gfm** (Apache 2.0, BSD-2-Clause): Markdown parsing.
          [github.com/swiftlang/swift-markdown](https://github.com/swiftlang/swift-markdown)
        - **highlight.js \(WebAssets.highlightVersion)** (BSD-3-Clause): code highlighting.
          [highlightjs.org](https://highlightjs.org)
        - **KaTeX \(WebAssets.katexVersion)** (MIT): math rendering. [katex.org](https://katex.org)
        - **Mermaid \(WebAssets.mermaidVersion)** (MIT): diagrams. [mermaid.js.org](https://mermaid.js.org)

        Full license texts ship inside the app, next to each library in Contents/Resources/Web/vendor.
        """
}

struct LegalView: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(document.title).font(.title2.weight(.semibold)).padding(.bottom, 4)
                    ForEach(Array(SimpleMarkdownBlocks.parse(document.markdown).enumerated()), id: \.offset) {
                        block(for: $0.element)
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 420, height: 520)
    }

    @ViewBuilder
    private func block(for block: SimpleMarkdownBlocks.Block) -> some View {
        switch block {
        case .heading(let text):
            inline(text).font(.headline).padding(.top, 8)
        case .paragraph(let text):
            inline(text)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                inline(text)
            }
        }
    }

    private func inline(_ markdown: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return Text((try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown))
    }
}
