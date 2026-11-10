import AppKit
import SwiftUI
@main
struct VeilApp: App {
    @StateObject private var model = VeilModel()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(width: 540)
                .onAppear {
                    model.refreshSources()
                    model.applyAlwaysOnTop()
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        await UpdateChecker.shared.check(manual: false)
                    }
                }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Veil") {
                Button("Check for Updates…") {
                    Task { await UpdateChecker.shared.check(manual: true) }
                }
                Divider()
                Button("Panic (Hide Output)") {
                    model.togglePanic()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
            CommandMenu("Presets") {
                ForEach(Array(model.hotkeyPresets.enumerated()), id: \.element.id) { index, preset in
                    Button("Apply \(preset.name)") {
                        model.applyPreset(preset)
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }
        }
    }
}
