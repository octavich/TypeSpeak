import SwiftUI
import AppKit
import AVFoundation
import Carbon.HIToolbox

@main
struct TypeSpeakApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // Tray = settings. Quick input lives in the floating Spotlight panel.
        MenuBarExtra("TypeSpeak", systemImage: "mic.fill") {
            SettingsView()
                .environmentObject(delegate.router)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - App delegate (owns hotkey + Spotlight panel)

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let router = SpeechRouter()
    private var panel: SpotlightPanel?
    private var toggleHotKey: HotKey?
    private var repeatHotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Tray-only app, no Dock icon.
        NSApp.setActivationPolicy(.accessory)

        // ⌥Space — toggle the Spotlight input.
        toggleHotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) { [weak self] in
            Task { @MainActor in self?.togglePanel() }
        }
        // ⌥R — repeat the last phrase, no typing.
        repeatHotKey = HotKey(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(optionKey)) { [weak self] in
            Task { @MainActor in self?.router.repeatLast() }
        }
    }

    func togglePanel() {
        if let panel, panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        let panel = panel ?? makePanel()
        self.panel = panel
        center(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> SpotlightPanel {
        let view = SpotlightView(onClose: { [weak self] in self?.hidePanel() })
            .environmentObject(router)
        let hosting = NSHostingView(rootView: view)
        let panel = SpotlightPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    private func center(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let f = panel.frame
        let sf = screen.visibleFrame
        let x = sf.midX - f.width / 2
        let y = sf.midY + sf.height * 0.18   // a bit above center, Spotlight-like
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - Settings (tray window)

struct SettingsView: View {
    @EnvironmentObject var router: SpeechRouter

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TypeSpeak")
                .font(.headline)
            Text("⌥Space — ввод · Enter — озвучить · ⌥R — повтор")
                .font(.caption).foregroundStyle(.secondary)

            // Output device (route into BlackHole).
            Picker("Выход", selection: Binding(
                get: { router.selectedDeviceID },
                set: { router.selectedDeviceID = $0 })) {
                ForEach(router.devices) { d in
                    Text(d.name).tag(Optional(d.id))
                }
            }
            if router.devices.allSatisfy({ !$0.name.localizedCaseInsensitiveContains("BlackHole") }) {
                Text("⚠️ BlackHole не найден. brew install --cask blackhole-2ch")
                    .font(.caption).foregroundStyle(.orange)
            }

            // Monitor: hear yourself in headphones.
            Toggle("Слышать в наушниках", isOn: $router.monitorEnabled)
            if router.monitorEnabled {
                Picker("Наушники", selection: Binding(
                    get: { router.monitorDeviceID },
                    set: { router.monitorDeviceID = $0 })) {
                    ForEach(router.devices) { d in
                        Text(d.name).tag(Optional(d.id))
                    }
                }
            }

            // Voice.
            Picker("Голос", selection: Binding(
                get: { router.selectedVoiceID },
                set: { router.selectedVoiceID = $0 })) {
                ForEach(router.voices, id: \.identifier) { v in
                    Text("\(v.name) (\(v.language)) \(qualityTag(v.quality))")
                        .tag(Optional(v.identifier))
                }
            }

            HStack {
                Text("Скорость")
                Slider(value: $router.rate,
                       in: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate)
            }

            HStack {
                Button("Стоп") { router.stop() }
                    .disabled(!router.isSpeaking)
                Spacer()
                Button("↻ Устройства") { router.reloadDevices(); router.reloadVoices() }
            }

            if !router.status.isEmpty {
                Text(router.status).font(.caption).foregroundStyle(.secondary)
            }

            Divider()
            Button("Выход") { NSApplication.shared.terminate(nil) }
        }
        .padding(14)
        .frame(width: 340)
    }

    private func qualityTag(_ q: AVSpeechSynthesisVoiceQuality) -> String {
        switch q {
        case .premium: return "★★"
        case .enhanced: return "★"
        default: return ""
        }
    }
}
