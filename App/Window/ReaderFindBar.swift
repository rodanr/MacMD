import SwiftUI

/// Search for Read mode: a small floating bar over the page, so it never moves the text.
struct ReaderFindBar: View {
    @Bindable var model: DocumentModel
    @Environment(\.zoom) private var zoom
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Find", text: $model.findQuery)
                .textFieldStyle(.plain)
                .frame(width: 180 * zoom)
                .focused($isFocused)
                .onSubmit { model.findInReader() }
                .onChange(of: model.findQuery) { model.findInReader() }
                .accessibilityIdentifier("readerFindField")
            if model.findHasNoMatch {
                Text("No matches").foregroundStyle(.secondary).lineLimit(1)
            }
            Button {
                model.findInReader(backwards: true)
            } label: {
                Image(systemName: "chevron.up")
            }
            .accessibilityLabel("Previous Match")
            Button {
                model.findInReader()
            } label: {
                Image(systemName: "chevron.down")
            }
            .accessibilityLabel("Next Match")
            Button {
                model.hideFindBar()
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Close Find")
            .accessibilityIdentifier("readerFindClose")
        }
        .buttonStyle(.plain)
        .font(.system(size: 13 * zoom))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .onExitCommand { model.hideFindBar() }
        .onAppear { isFocused = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("readerFindBar")
    }
}
