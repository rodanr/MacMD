import AppKit
import MacMDKit
import Observation

/// User preferences, persisted in `UserDefaults` and observable from SwiftUI and AppKit.
@MainActor @Observable
final class AppSettings {
    static let shared = AppSettings()

    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    enum LineWidth: String, CaseIterable, Identifiable {
        case narrow, medium, wide, full
        var id: String { rawValue }
        var title: String { rawValue.capitalized }

        /// Characters per line (`nil` = fill the window). Measured in characters, like CSS `ch`, so the
        /// editor and Read mode agree and the column grows with zoom.
        var characters: Int? {
            switch self {
            case .narrow: 56
            case .medium: 68
            case .wide: 84
            case .full: nil
            }
        }

        /// The reader's `--measure`.
        var cssMeasure: String { characters.map { "\($0)ch" } ?? "none" }
    }

    var themeID: Theme.ID { didSet { store(themeID.rawValue, for: .theme) } }
    var appearance: Appearance { didSet { store(appearance.rawValue, for: .appearance); applyAppearance() } }
    /// Scales everything in the window: editor, Read mode, sidebar and status bar (see `Zoom`).
    var zoom: Double { didSet { store(zoom, for: .zoom) } }
    var lineWidth: LineWidth { didSet { store(lineWidth.rawValue, for: .lineWidth) } }
    var focusModeByDefault: Bool { didSet { store(focusModeByDefault, for: .focusMode) } }
    var typewriterModeByDefault: Bool { didSet { store(typewriterModeByDefault, for: .typewriterMode) } }
    var spellChecking: Bool { didSet { store(spellChecking, for: .spellChecking) } }
    var openInReadMode: Bool { didSet { store(openInReadMode, for: .openInReadMode) } }
    var vimMode: Bool { didSet { store(vimMode, for: .vimMode) } }
    /// The sidebar as last left, so new windows and tabs open the same way.
    var sidebarVisible: Bool { didSet { store(sidebarVisible, for: .sidebarVisible) } }
    var sidebarTab: String { didSet { store(sidebarTab, for: .sidebarTab) } }

    var theme: Theme { Theme(id: themeID, fontSize: Self.baseFontSize * zoom) }

    /// The editor's body size at 100% zoom.
    static let baseFontSize: Double = 16

    private let defaults: UserDefaults

    private enum Key: String {
        case theme, appearance, zoom, lineWidth, focusMode, typewriterMode, spellChecking, openInReadMode
        case vimMode, sidebarVisible, sidebarTab
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        themeID = defaults.string(forKey: Key.theme.rawValue).flatMap(Theme.ID.init) ?? .paper
        appearance = defaults.string(forKey: Key.appearance.rawValue).flatMap(Appearance.init) ?? .system
        zoom = Zoom.sanitized(defaults.object(forKey: Key.zoom.rawValue) as? Double ?? Zoom.actualSize)
        lineWidth = defaults.string(forKey: Key.lineWidth.rawValue).flatMap(LineWidth.init) ?? .medium
        focusModeByDefault = defaults.bool(forKey: Key.focusMode.rawValue)
        typewriterModeByDefault = defaults.bool(forKey: Key.typewriterMode.rawValue)
        spellChecking = defaults.object(forKey: Key.spellChecking.rawValue) as? Bool ?? true
        openInReadMode = defaults.bool(forKey: Key.openInReadMode.rawValue)
        vimMode = defaults.bool(forKey: Key.vimMode.rawValue)
        sidebarVisible = defaults.bool(forKey: Key.sidebarVisible.rawValue)
        sidebarTab = defaults.string(forKey: Key.sidebarTab.rawValue) ?? "outline"
    }

    func applyAppearance() {
        NSApp?.appearance =
            switch appearance {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
    }

    func zoomIn() { zoom = Zoom.zoomedIn(from: zoom) }
    func zoomOut() { zoom = Zoom.zoomedOut(from: zoom) }
    func resetZoom() { zoom = Zoom.actualSize }

    private func store(_ value: Any, for key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }
}
