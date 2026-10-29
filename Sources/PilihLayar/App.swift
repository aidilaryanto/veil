import SwiftUI

@main
struct PilihLayarApp: App {
    @StateObject private var model = PilihLayarModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(width: 430)
                .onAppear {
                    model.refreshSources()
                    model.applyAlwaysOnTop()
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("PilihLayar") {
                Button("Panik (Sembunyikan Output)") {
                    model.togglePanic()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Mulai / Berhenti Berbagi") {
                    model.toggleSharing()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
}
