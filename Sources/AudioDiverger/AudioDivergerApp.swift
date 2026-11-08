import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AudioModel.shared.stopAll() }
    }
}

@main
struct AudioDivergerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var model = AudioModel.shared

    var body: some Scene {
        Window("AudioDiverger", id: "main") {
            RoutingView()
                .environmentObject(model)
                .frame(minWidth: 560, idealWidth: 600, minHeight: 360, idealHeight: 460)
        }
        .defaultSize(width: 600, height: 460)

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(model)
        } label: {
            Image(systemName: model.assignments.isEmpty ? "arrow.triangle.branch" : "headphones")
        }
        .menuBarExtraStyle(.window)
    }
}
