import AppKit
import TurboFieldfareAppCore
import TurboFieldfareMacPresentation
import SwiftUI

struct RootView: View {
    let model: AppModel
    let server: AppServerController

    var body: some View {
        Group {
            if model.requiresModelInstallation {
                ModelInstallView(model: model)
            } else {
                ServerStatusView(model: model, server: server)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .window) {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .windowBackgroundColor).mix(
                        with: TurboFieldfareMacTheme.accentColor,
                        by: 0.04),
                ],
                startPoint: .top,
                endPoint: .bottom)
        }
        .tint(TurboFieldfareMacTheme.accentColor)
        .animation(.smooth(duration: 0.3), value: model.requiresModelInstallation)
        .task(id: model.isModelInstalled) {
            if model.isModelInstalled {
                server.start(
                    modelDirectory: modelDirectory,
                    configuration: AppServerConfiguration(model: model))
            } else {
                server.stop()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.willTerminateNotification)
        ) { _ in
            server.stop()
        }
    }

    private var modelDirectory: URL {
        URL(fileURLWithPath: model.modelPathText, isDirectory: true)
    }
}
