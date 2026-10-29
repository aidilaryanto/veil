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
        // The control window is NOT resizable: it follows its
        // content (fixed width 680), but can still be dragged
        // from its empty areas (see configureFramelessWindow:
        // isMovableByWindowBackground).
        .windowResizability(.contentSize)
        // The title bar is hidden from the start; ContentView then
        // makes the content cover the whole window, with a
        // transparent title bar and hidden traffic-light buttons
        // (see configureFramelessWindow), so there is no black
        // macOS bar.
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
