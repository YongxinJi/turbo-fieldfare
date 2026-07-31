import AppKit
import TurboFieldfareAppCore
import SwiftUI

// Run as a regular foreground app even when launched as a bare SwiftPM
// executable (no .app bundle): Dock icon, click-to-activate, full main menu
// with Quit (Cmd+Q).
private final class ForegroundAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let iconURL = Bundle.module.url(
            forResource: "turbofieldfare-app-icon",
            withExtension: "png"
        ), let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
            NSApp.dockTile.display()
        }
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct TurboFieldfareMacApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: ForegroundAppDelegate
    @State private var model: AppModel
    @State private var server: AppServerController

    init() {
        _model = State(initialValue: AppModel(
            client: DecodeServiceInferenceClient(),
            settingsPersistenceEnabled: true))
        _server = State(initialValue: AppServerController())
    }

    var body: some Scene {
        Window("TurboFieldfare", id: "main") {
            RootView(model: model, server: server)
                .frame(minWidth: 900, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1040, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("Model") {
                Button("Cancel Model Installation") { model.cancelInstall() }
                    .disabled(!model.canCancelInstall)
            }
            CommandMenu("Server") {
                Button("Start Server") {
                    server.start(
                        modelDirectory: URL(
                            fileURLWithPath: model.modelPathText,
                            isDirectory: true),
                        configuration: AppServerConfiguration(model: model))
                }
                .disabled(!model.isModelInstalled || !server.canStart)
                Button("Stop Server", action: server.stop)
                    .disabled(!server.canStop)
            }
        }

        MenuBarExtra {
            ServerMenuBarView(model: model, server: server)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: server.menuBarSystemImage)
                Text(server.menuBarSummary)
            }
            .accessibilityLabel(server.menuBarAccessibilityLabel)
        }
        .menuBarExtraStyle(.menu)
    }
}
