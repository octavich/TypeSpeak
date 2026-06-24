import SwiftUI

@main
struct NarratorApp: App {
    @StateObject private var router = SpeechRouter()

    var body: some Scene {
        MenuBarExtra("Narrator", systemImage: "mic.fill") {
            ContentView()
                .environmentObject(router)
        }
        .menuBarExtraStyle(.window)
    }
}

struct ContentView: View {
    @EnvironmentObject var router: SpeechRouter
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Narrator → микрофон")
                .font(.headline)

            // Output device (route into BlackHole).
            Picker("Выход", selection: Binding(
                get: { router.selectedDeviceID },
                set: { router.selectedDeviceID = $0 })) {
                ForEach(router.devices) { d in
                    Text(d.name).tag(Optional(d.id))
                }
            }
            if router.devices.allSatisfy({ !$0.name.localizedCaseInsensitiveContains("BlackHole") }) {
                Text("⚠️ BlackHole не найден. Установи: brew install --cask blackhole-2ch")
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

            TextEditor(text: $text)
                .frame(height: 90)
                .font(.body)
                .focused($focused)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.3)))

            HStack {
                Button(router.isSpeaking ? "Говорю…" : "Озвучить") {
                    router.speak(text)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(router.isSpeaking)

                Button("Стоп") { router.stop() }
                    .disabled(!router.isSpeaking)

                Spacer()
                Button("↻") { router.reloadDevices(); router.reloadVoices() }
            }

            if !router.status.isEmpty {
                Text(router.status).font(.caption).foregroundStyle(.secondary)
            }

            Divider()
            Button("Выход") { NSApplication.shared.terminate(nil) }
        }
        .padding(14)
        .frame(width: 340)
        .onAppear { focused = true }
    }

    private func qualityTag(_ q: AVSpeechSynthesisVoiceQuality) -> String {
        switch q {
        case .premium: return "★★"
        case .enhanced: return "★"
        default: return ""
        }
    }
}

import AVFoundation
