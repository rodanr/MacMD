import MacMDKit
import SwiftUI

/// The document's headings; clicking one jumps to it in the editor or reader.
struct OutlineView: View {
    let model: DocumentModel
    @Environment(\.zoom) private var zoom

    /// The heading of the section being read or edited: it follows the caret in Edit mode and the
    /// top of the page in Read mode.
    private var currentSlug: String? {
        let line = model.mode == .read ? (model.readerTopLine ?? 1) : model.caretLine
        return model.outline.last { $0.line <= line }?.slug
    }

    var body: some View {
        if model.outline.isEmpty {
            ContentUnavailableView(
                "No Headings", systemImage: "list.bullet.indent",
                description: Text("Add a `#` heading to build an outline."))
        } else {
            let minLevel = model.outline.map(\.level).min() ?? 1
            let current = currentSlug
            List(model.outline) { item in
                Button {
                    model.reveal(item)
                } label: {
                    HStack(spacing: 0) {
                        // Hairline guides, one per nesting level; decorative only.
                        ForEach(0..<(item.level - minLevel), id: \.self) { _ in
                            Rectangle()
                                .fill(.separator)
                                .frame(width: 1)
                                .padding(.leading, 6 * zoom)
                                .padding(.trailing, 5 * zoom)
                                .accessibilityHidden(true)
                        }
                        Text(item.title.isEmpty ? "Untitled" : item.title)
                            .font(.system(size: 13 * zoom, weight: item.level == minLevel ? .semibold : .regular))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .padding(.vertical, 3 * zoom)
                    }
                    .padding(.horizontal, 6 * zoom)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.panelRadius / 2)
                            .fill(item.slug == current ? Color.accentColor.opacity(0.14) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(item.slug == current ? .isSelected : [])
                .help(item.title)
                // No gaps between rows, so the indent guides run on unbroken.
                .listRowInsets(EdgeInsets(top: 0, leading: 8 * zoom, bottom: 0, trailing: 8 * zoom))
            }
            .listStyle(.sidebar)
        }
    }
}
