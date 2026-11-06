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
                }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Veil") {
                Button("Panic (Hide Output)") {
                    model.togglePanic()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }
    }
}
