import MacMDKit
import SwiftUI

struct SettingsView: View {
    @State private var settings = AppSettings.shared

    /// Typed values are kept within the allowed range.
    private var fontSize: Binding<Double> {
        Binding(get: { settings.fontSize }, set: { settings.fontSize = FontSize.sanitized($0) })
    }

    var body: some View {
        Form {
            Section {
                Picker("Open documents in", selection: $settings.openInReadMode) {
                    Text("Edit Mode").tag(false)
                    Text("Read Mode").tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("openModePicker")
                Toggle("Start new windows in Focus mode", isOn: $settings.focusModeByDefault)
                Toggle("Start new windows in Typewriter mode", isOn: $settings.typewriterModeByDefault)
            } header: {
                Text("General")
            } footer: {
                Text("Press ⌘E to switch between editing and reading at any time.")
                    .foregroundStyle(.secondary)
            }
            Section("Appearance") {
                Picker("Theme", selection: $settings.themeID) {
                    ForEach(Theme.ID.allCases) { theme in
                        VStack(alignment: .leading) {
                            Text(theme.displayName)
                            Text(theme.summary).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(theme)
                    }
                }
                .pickerStyle(.radioGroup)
                Picker("Color scheme", selection: $settings.appearance) {
                    ForEach(AppSettings.Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                LabeledContent("Font size") {
                    HStack(spacing: 6) {
                        TextField("Font size", value: fontSize, format: .number)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 44)
                            .accessibilityIdentifier("fontSizeField")
                        Text("pt").foregroundStyle(.secondary)
                        Stepper("Font size", value: fontSize, in: FontSize.range, step: 1)
                            .labelsHidden()
                            .accessibilityIdentifier("fontSizeStepper")
                        Button("Reset") { settings.resetFontSize() }
                            .disabled(settings.fontSize == FontSize.standard)
                    }
                }
                LabeledContent("Zoom") {
                    HStack {
                        Picker("Zoom", selection: $settings.zoom) {
                            ForEach(Zoom.levels, id: \.self) { Text(Zoom.percent($0)).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Button("Reset") { settings.resetZoom() }
                            .disabled(settings.zoom == Zoom.actualSize)
                    }
                }
                Picker("Line width", selection: $settings.lineWidth) {
                    ForEach(AppSettings.LineWidth.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Size")
            } footer: {
                Text(
                    "Font size sets the text in the editor and Read mode (⌥⌘+ / ⌥⌘−). Zoom scales the whole window, "
                        + "sidebar and status bar included (⌘+ / ⌘−; ⌘0 returns to 100%)."
                )
                .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Check spelling while typing", isOn: $settings.spellChecking)
                Toggle("Vim mode", isOn: $settings.vimMode)
                    .accessibilityIdentifier("vimModeToggle")
            } header: {
                Text("Editing")
            } footer: {
                Text("Vim mode adds motions, operators and text objects. Press Esc for normal mode and i to insert.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
