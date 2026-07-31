import AppKit
import TurboFieldfareAppCore
import TurboFieldfareMacPresentation
import SwiftUI

struct ServerStatusView: View {
    @Bindable var model: AppModel
    let server: AppServerController

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                identity
                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 18) {
                        statusCard
                        endpointCard
                        detailsCard
                        actions
                    }
                    .frame(maxWidth: .infinity)

                    configurationCard
                        .frame(width: 340)
                }
            }
            .frame(maxWidth: 980)
            .padding(.horizontal, 28)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: configuration) {
            model.saveSettings()
        }
    }

    private var identity: some View {
        VStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(.largeTitle, design: .rounded))
                .foregroundStyle(TurboFieldfareMacTheme.accentColor)
                .accessibilityHidden(true)
            Text("Local API Server")
                .font(.title.bold())
                .accessibilityHeading(.h1)
            Text("OpenAI-compatible Chat Completions, available only on this Mac.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var statusCard: some View {
        UtilityCard {
            HStack(alignment: .top, spacing: 12) {
                statusIndicator
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    Text(statusTitle)
                        .font(.title3.weight(.semibold))
                    Text(statusDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("API server status")
            .accessibilityValue("\(statusTitle). \(statusDetail)")
        }
    }

    private var endpointCard: some View {
        UtilityCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("API endpoint")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Text(AppServerController.apiBaseURL.absoluteString)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(AppServerController.apiBaseURL.absoluteString)
                    Spacer(minLength: 12)
                    Button(action: copyEndpoint) {
                        Label("Copy URL", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isAvailable)
                }
            }
        }
    }

    private var detailsCard: some View {
        UtilityCard {
            VStack(spacing: 12) {
                DetailRow(label: "Model", value: model.installDescriptor.apiModelID)
                Divider()
                DetailRow(
                    label: "Context",
                    value: "\(displayConfiguration.contextTokens / 1_024)K tokens")
                Divider()
                DetailRow(label: "Server RSS", value: rssText)
                Divider()
                DetailRow(label: "Network", value: "127.0.0.1 only")
                Divider()
                DetailRow(label: "Model files", value: model.modelPathText)
            }
        }
    }

    private var configurationCard: some View {
        UtilityCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Server configuration")
                        .font(.headline)
                    Spacer()
                    if hasPendingConfiguration {
                        Text("Restart required")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }

                LabeledContent("Context") {
                    Picker("Context", selection: $model.maxContextTokens) {
                        ForEach(AppContextLengthOption.allCases) { option in
                            Text(option.menuLabel).tag(option.tokens)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                LabeledContent("Cache slots") {
                    Picker(
                        "Cache slots",
                        selection: $model.runtimeOptions.expertCacheSlots
                    ) {
                        ForEach(
                            AppRuntimeOptions.allowedSlotCounts,
                            id: \.self
                        ) { slots in
                            Text("\(slots)").tag(slots)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Temperature") {
                        Text(
                            model.temperature,
                            format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                    }
                    Slider(value: $model.temperature, in: 0...2, step: 0.05)
                }

                Toggle("Top-K", isOn: $model.topKEnabled)
                if model.topKEnabled {
                    LabeledContent("K value") {
                        Stepper(value: $model.topK, in: 1...256) {
                            Text("\(model.topK)").monospacedDigit()
                        }
                        .fixedSize()
                    }
                }

                Toggle("Top-P", isOn: $model.topPEnabled)
                    .disabled(!model.topKEnabled)
                if model.topKEnabled && model.topPEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("P value") {
                            Text(
                                model.topP,
                                format: .number.precision(.fractionLength(2)))
                                .monospacedDigit()
                        }
                        Slider(value: $model.topP, in: 0.01...1, step: 0.01)
                    }
                }

                Divider()

                Toggle(
                    "Chunked prefill",
                    isOn: $model.runtimeOptions.prefillEnabled)
                LabeledContent("RDADVISE") {
                    Picker(
                        "RDADVISE",
                        selection: $model.runtimeOptions.rdadvisePolicy
                    ) {
                        ForEach(AppRDAdvicePolicy.allCases) { policy in
                            Text(policy.label).tag(policy)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                Divider()

                LabeledContent("API key") {
                    HStack(spacing: 8) {
                        Text(maskedAPIKey)
                            .font(.caption.monospaced())
                        Button(action: copyAPIKey) {
                            Image(systemName: "doc.on.doc")
                        }
                        .accessibilityLabel("Copy API key")
                        Button(action: rotateAPIKey) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .accessibilityLabel("Rotate API key")
                    }
                }

                Text("OpenAI endpoints require this Bearer token. API request values override sampling defaults; configuration changes apply after a server restart.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(server.state == .starting || server.state == .alreadyRunning)
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            if hasPendingConfiguration {
                Text("Configuration changed. Restart the server to apply it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                if server.canStop {
                    if hasPendingConfiguration {
                        Button("Apply & Restart") {
                            model.saveSettings()
                            server.restart(
                                modelDirectory: modelDirectory,
                                configuration: configuration)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button("Stop Server", role: .destructive) {
                        server.stop()
                    }
                    .buttonStyle(.bordered)
                } else if server.canStart {
                    Button(startButtonTitle) {
                        model.saveSettings()
                        server.start(
                            modelDirectory: modelDirectory,
                            configuration: configuration)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch server.state {
        case .starting:
            ProgressView().controlSize(.small)
        case .ready:
            statusDot(.green)
        case .alreadyRunning:
            statusDot(.orange)
        case .failed:
            statusDot(.red)
        case .stopped:
            statusDot(.gray)
        }
    }

    private var statusTitle: String {
        switch server.state {
        case .stopped: "Server stopped"
        case .starting: "Starting server"
        case .ready: "Server ready"
        case .alreadyRunning: "Server already running"
        case .failed: "Server failed"
        }
    }

    private var statusDetail: String {
        switch server.state {
        case .stopped:
            "Start the server to accept local API requests."
        case .starting:
            "Loading the model before opening port \(AppServerController.port)."
        case .ready:
            "Ready for requests at \(AppServerController.apiBaseURL.absoluteString)."
        case .alreadyRunning:
            "A server was already responding on this endpoint. This app will not stop it."
        case .failed(let message):
            message
        }
    }

    private var startButtonTitle: String {
        if case .failed = server.state { return "Try Again" }
        return "Start Server"
    }

    private var isAvailable: Bool {
        server.state == .ready || server.state == .alreadyRunning
    }

    private var configuration: AppServerConfiguration {
        AppServerConfiguration(model: model)
    }

    private var displayConfiguration: AppServerConfiguration {
        server.activeConfiguration ?? configuration
    }

    private var hasPendingConfiguration: Bool {
        guard let active = server.activeConfiguration else { return false }
        return active != configuration
    }

    private var modelDirectory: URL {
        URL(fileURLWithPath: model.modelPathText, isDirectory: true)
    }

    private func copyEndpoint() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            AppServerController.apiBaseURL.absoluteString,
            forType: .string)
    }

    private func copyAPIKey() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.apiKey, forType: .string)
    }

    private func rotateAPIKey() {
        model.rotateAPIKey()
        if server.ownsServer {
            server.restart(
                modelDirectory: modelDirectory,
                configuration: AppServerConfiguration(model: model))
        }
    }

    private var maskedAPIKey: String {
        guard model.apiKey.count >= 8 else { return "Not configured" }
        return "\(model.apiKey.prefix(4))••••\(model.apiKey.suffix(4))"
    }

    private var rssText: String {
        guard let bytes = server.metrics.rssBytes else { return "Unavailable" }
        return ByteCountFormatter.string(
            fromByteCount: Int64(clamping: bytes),
            countStyle: .memory)
    }

    private func statusDot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }
}

private struct UtilityCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(.separator.opacity(0.5), lineWidth: 0.5)
                    }
            }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .font(.callout.monospaced())
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(value)
                .textSelection(.enabled)
        }
    }
}
