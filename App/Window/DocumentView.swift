import MacMDKit
import SwiftUI

/// The content of a document window: sidebar, editor or reader, and status bar.
struct DocumentView: View {
    @Bindable var model: DocumentModel
    @State private var settings = AppSettings.shared

    var body: some View {
        NavigationSplitView(columnVisibility: $model.sidebarVisibility) {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 190, ideal: 230 * settings.zoom, max: 340 * settings.zoom)
        } detail: {
            detail
                .overlay(alignment: .bottom) { HUDView().padding(.bottom, 24) }
                .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar(model: model, settings: settings) }
                .background(Color(nsColor: settings.theme.background))
        }
        .toolbar(removing: .sidebarToggle)  // replaced by our own, which also has a shortcut and help text
        .toolbar { toolbar }
        .environment(\.zoom, settings.zoom)
    }

    private var detail: some View {
        ZStack {
            // The editor stays alive in Read mode so undo history and selection survive.
            EditorView(
                model: model, theme: settings.theme,
                lineWidth: settings.lineWidth.characters.map { CGFloat($0) * settings.theme.characterWidth },
                spellChecking: settings.spellChecking, isFocusMode: model.isFocusMode,
                isTypewriterMode: model.isTypewriterMode, isVimEnabled: settings.vimMode
            )
            .opacity(model.mode == .edit ? 1 : 0)
            .allowsHitTesting(model.mode == .edit)
            .accessibilityHidden(model.mode != .edit)

            // Once created, the reader stays in the hierarchy so its web view is never re-parented.
            if model.mode == .read || model.reader != nil {
                ReaderView(
                    controller: model.makeReaderIfNeeded(), theme: settings.themeID, revision: model.revision,
                    zoom: settings.zoom, measure: settings.lineWidth.cssMeasure, fileURL: model.fileURL,
                    isVisible: model.mode == .read
                )
                .opacity(model.mode == .read ? 1 : 0)
                .allowsHitTesting(model.mode == .read)
                .accessibilityHidden(model.mode != .read)
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.mode)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                withAnimation { model.toggleSidebar() }
            } label: {
                Label(model.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar", systemImage: "sidebar.left")
            }
            .help("Show or hide the outline and files (⌃⌘S)")
            .accessibilityIdentifier("sidebarToggle")
        }
        ToolbarItem(placement: .primaryAction) {
            Picker("Mode", selection: Binding(get: { model.mode }, set: { if $0 != model.mode { model.toggleMode() } }))
            {
                // Explicit labels: otherwise VoiceOver reads the icons' names ("Bookmark").
                Label("Edit", systemImage: "pencil").accessibilityLabel("Edit").tag(DocumentModel.Mode.edit)
                Label("Read", systemImage: "book").accessibilityLabel("Read").tag(DocumentModel.Mode.read)
            }
            .pickerStyle(.segmented)
            .help("Switch between editing and reading (⌘E)")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Section("Zoom: \(Zoom.describe(settings.zoom))") {
                    Button("Zoom In") { NSApp.sendAction(#selector(AppDelegate.zoomIn(_:)), to: nil, from: nil) }
                    Button("Zoom Out") { NSApp.sendAction(#selector(AppDelegate.zoomOut(_:)), to: nil, from: nil) }
                    Button("Actual Size") { NSApp.sendAction(#selector(AppDelegate.resetZoom(_:)), to: nil, from: nil) }
                }
                Divider()
                Toggle(
                    "Focus Mode (F8)", isOn: Binding(get: { model.isFocusMode }, set: { _ in model.toggleFocusMode() })
                )
                .disabled(model.mode == .read)
                Toggle(
                    "Typewriter Mode (F9)",
                    isOn: Binding(get: { model.isTypewriterMode }, set: { _ in model.toggleTypewriterMode() })
                )
                .disabled(model.mode == .read)
                Divider()
                Picker("Theme", selection: $settings.themeID) {
                    ForEach(Theme.ID.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Line Width", selection: $settings.lineWidth) {
                    ForEach(AppSettings.LineWidth.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                Label("View Options", systemImage: "textformat.size")
            }
            .help("Zoom, focus and typewriter modes, theme and line width")
            .accessibilityIdentifier("viewOptions")
        }
    }
}

private struct StatusBar: View {
    let model: DocumentModel
    let settings: AppSettings

    var body: some View {
        HStack(spacing: 14) {
            if model.mode == .edit, let vimStatus = model.vimStatus {
                Text(vimStatus)
                    .font(.system(size: 11 * settings.zoom, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .accessibilityIdentifier("vimStatus")
            }
            Text("\(model.stats.words.formatted()) words")
            Text("\(max(model.stats.readingMinutes, 1)) min read")
            if model.isLargeDocument {
                Label("Large file — live styling paused", systemImage: "bolt.horizontal")
            }
            Spacer()
            if model.mode == .edit {
                // Active modes are always visible, and a click turns them off.
                if model.isFocusMode {
                    ModeChip(title: "Focus", systemImage: "scope", action: model.toggleFocusMode)
                }
                if model.isTypewriterMode {
                    ModeChip(title: "Typewriter", systemImage: "text.aligncenter", action: model.toggleTypewriterMode)
                }
                Text("Ln \(model.caretLine), Col \(model.caretColumn)")
                    .monospacedDigit()
            }
            Menu {
                Button("Zoom In  ⌘+") { NSApp.sendAction(#selector(AppDelegate.zoomIn(_:)), to: nil, from: nil) }
                Button("Zoom Out  ⌘−") { NSApp.sendAction(#selector(AppDelegate.zoomOut(_:)), to: nil, from: nil) }
                Button("Actual Size  ⌘0") {
                    NSApp.sendAction(#selector(AppDelegate.resetZoom(_:)), to: nil, from: nil)
                }
            } label: {
                Text(Zoom.percent(settings.zoom)).monospacedDigit()
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()
            .help("Zoom: \(Zoom.describe(settings.zoom))")
            .accessibilityIdentifier("zoom")
        }
        .font(.system(size: 11 * settings.zoom))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(.bar)
    }
}

/// A small status-bar label for an active mode; clicking it turns the mode off.
private struct ModeChip: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .padding(.horizontal, 7)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .help("\(title) mode is on. Click to turn it off.")
    }
}

extension EnvironmentValues {
    /// The window zoom (1 = 100%), for views that size their own fonts.
    @Entry var zoom: Double = 1
}
