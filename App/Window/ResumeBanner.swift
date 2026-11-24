import MacMDKit
import SwiftUI

/// Offers to jump back to where the file was last read. An overlay, so it never moves the text or the
/// reading position it is about.
struct ResumeBanner: View {
    var model: DocumentModel
    @Environment(\.zoom) private var zoom
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let offer = model.resumeOffer {
                HStack(spacing: 12) {
                    Text(message(for: offer))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Button("Continue") { model.continueReading() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityIdentifier("resumeContinue")
                    Button {
                        model.dismissResumeOffer()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Dismiss")
                    .accessibilityIdentifier("resumeDismiss")
                    .keyboardShortcut(.cancelAction)
                }
                .font(.system(size: 13 * zoom, weight: .medium))
                .padding(.leading, 16)
                .padding(.trailing, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, 24)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("resumeBanner")
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.resumeOffer)
    }

    private func message(for offer: ReadingPosition.Target) -> String {
        if let title = offer.headingTitle, !title.isEmpty {
            return "Continue where you left off: \(title)"
        }
        return "Continue where you left off: line \(offer.line)"
    }
}
