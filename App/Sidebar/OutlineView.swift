import MacMDKit
import SwiftUI

/// The document's headings; clicking one jumps to it in the editor or reader.
struct OutlineView: View {
    let model: DocumentModel
    @Environment(\.zoom) private var zoom

    private var currentSlug: String? {
        model.outline.last { $0.line <= model.caretLine }?.slug
    }

    var body: some View {
        if model.outline.isEmpty {
            ContentUnavailableView(
                "No Headings", systemImage: "list.bullet.indent",
                description: Text("Add a `#` heading to build an outline."))
        } else {
            let minLevel = model.outline.map(\.level).min() ?? 1
            List(model.outline) { item in
                Button {
                    model.reveal(item)
                } label: {
                    Text(item.title.isEmpty ? "Untitled" : item.title)
                        .font(.system(size: 13 * zoom, weight: item.level == minLevel ? .semibold : .regular))
                        .foregroundStyle(item.slug == currentSlug && model.mode == .edit ? Color.accentColor : .primary)
                        .lineLimit(1)
                        .padding(.leading, CGFloat(item.level - minLevel) * 12 * zoom)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.title)
            }
            .listStyle(.sidebar)
        }
    }
}
