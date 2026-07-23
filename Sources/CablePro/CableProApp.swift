import SwiftUI
import CableProUI

// CablePro — menu bar app.
// A beautiful SwiftUI popover over the MIT data layer. All diagnostics come
// from real IOKit data via SnapshotModel; the "pro"-style presentation is ours.

@main
struct CableProApp: App {
    @StateObject private var model = SnapshotModel()

    var body: some Scene {
        MenuBarExtra {
            ContentView(model: model)
        } label: {
            // Live label: cable icon + wattage while charging.
            HStack(spacing: 3) {
                Image(systemName: "cable.connector.horizontal")
                if !model.menuBarText.isEmpty {
                    Text(model.menuBarText)
                }
            }
            .onAppear { model.start() }
        }
        .menuBarExtraStyle(.window)

        // The full app window: dashboard with charts + per-cable statistics.
        Window("PortSight Dashboard", id: "dashboard") {
            DashboardView(model: model)
        }
        .windowResizability(.contentMinSize)

        // Dedicated, detachable live power monitor.
        Window("Power Monitor", id: "power-monitor") {
            PowerMonitorWindowView(model: model)
        }
        .windowResizability(.contentMinSize)
    }
}
