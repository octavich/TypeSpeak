import SwiftUI
import AppKit

/// Borderless floating panel that can take keyboard focus while the app stays an accessory.
final class SpotlightPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The Spotlight-style quick input: type, press Enter, it speaks. Esc hides.
struct SpotlightView: View {
    @EnvironmentObject var router: SpeechRouter
    let onClose: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.secondary)
                    .font(.title2)
                TextField("Напиши — Enter озвучит…", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22))
                    .focused($focused)
                    .onSubmit { send() }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .frame(width: 560)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
        .onExitCommand { onClose() }            // Esc
        .onAppear {
            // Defer one runloop tick so the panel is key before we grab focus.
            DispatchQueue.main.async { focused = true }
        }
    }

    private func send() {
        let t = text
        guard !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            onClose(); return
        }
        router.speak(t)
        text = ""
        onClose()
    }
}
