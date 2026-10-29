import SwiftUI
@main
struct VeilApp: App {
    @StateObject private var model = VeilModel()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(width: 680)
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
                Button("Start / Stop Sharing") {
                    model.toggleSharing()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
}
