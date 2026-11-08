import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { Snapshot.runIfRequested() }
    }

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
        // Background utility: lives in the menu bar (LSUIElement, no Dock icon).
        MenuBarExtra {
            RoutingView(style: .popover)
                .environmentObject(model)
                .frame(width: 400)
        } label: {
            Image(systemName: model.assignments.isEmpty && model.muted.isEmpty
                  ? "arrow.triangle.branch" : "headphones")
                .accessibilityLabel("AudioDiverger")
        }
        .menuBarExtraStyle(.window)

        // Optional larger window, opened from the popover.
        Window("AudioDiverger", id: "main") {
            RoutingView(style: .window)
                .environmentObject(model)
                .frame(minWidth: 440, idealWidth: 480, minHeight: 360, idealHeight: 540)
        }
        .defaultSize(width: 480, height: 540)
    }
}
