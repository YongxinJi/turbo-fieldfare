import AppKit
import TurboFieldfareAppCore
import SwiftUI

struct ServerMenuBarView: View {
    let model: AppModel
    let server: AppServerController

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(server.menuBarStatusTitle)
        Text("Server RSS: \(server.rssText)")
        Text("Last decode: \(server.tokenRateText)")

        Divider()

        Button("Open TurboFieldfare") {
            openWindow(id: "main")
            NSApp.activate()
        }
        Button("Copy API URL") {
            copy(AppServerController.apiBaseURL.absoluteString)
        }
        Button("Copy API Key") {
            copy(model.apiKey)
        }
        .disabled(model.apiKey.isEmpty)

        Divider()

        if server.canStop {
            Button("Stop Server", role: .destructive) {
                server.stop()
            }
        } else if server.canStart {
            Button("Start Server") {
                model.saveSettings()
                server.start(
                    modelDirectory: URL(
                        fileURLWithPath: model.modelPathText,
                        isDirectory: true),
                    configuration: AppServerConfiguration(model: model))
            }
            .disabled(!model.isModelInstalled)
        }

        Divider()

        Button("Quit TurboFieldfare") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

extension AppServerController {
    var menuBarSystemImage: String {
        switch state {
        case .stopped:
            "server.rack"
        case .starting:
            "arrow.triangle.2.circlepath"
        case .ready:
            "bolt.horizontal.circle.fill"
        case .alreadyRunning:
            "exclamationmark.triangle.fill"
        case .failed:
            "xmark.octagon.fill"
        }
    }

    var menuBarSummary: String {
        guard state == .ready || state == .alreadyRunning else {
            return menuBarStatusTitle
        }
        return "\(rssText) · \(tokenRateText)"
    }

    var menuBarAccessibilityLabel: String {
        "\(menuBarStatusTitle), Server RSS \(rssText), last decode \(tokenRateText)"
    }

    var menuBarStatusTitle: String {
        switch state {
        case .stopped:
            "Server stopped"
        case .starting:
            "Server starting"
        case .ready:
            "Server ready"
        case .alreadyRunning:
            "External server"
        case .failed:
            "Server failed"
        }
    }

    var rssText: String {
        guard let bytes = metrics.rssBytes else { return "RSS —" }
        return ByteCountFormatter.string(
            fromByteCount: Int64(clamping: bytes),
            countStyle: .memory)
    }

    var tokenRateText: String {
        guard let rate = metrics.tokensPerSecond,
              rate.isFinite,
              rate >= 0 else {
            return "— tok/s"
        }
        return "\(rate.formatted(.number.precision(.fractionLength(1)))) tok/s"
    }
}
