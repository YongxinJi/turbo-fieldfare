import Darwin
import Foundation
import Observation

public enum AppServerState: Equatable, Sendable {
    case stopped
    case starting
    case ready
    case alreadyRunning
    case failed(String)
}

public struct AppServerMetrics: Equatable, Sendable {
    public let rssBytes: UInt64?
    public let tokensPerSecond: Double?

    public init(rssBytes: UInt64? = nil, tokensPerSecond: Double? = nil) {
        self.rssBytes = rssBytes
        self.tokensPerSecond = tokensPerSecond
    }
}

public struct AppServerConfiguration: Equatable, Sendable {
    public let contextTokens: Int
    public let temperature: Double
    public let topK: Int?
    public let topP: Double?
    public let expertCacheSlots: Int
    public let prefillEnabled: Bool
    public let prefillChunkTokens: Int
    public let rdadvisePolicy: AppRDAdvicePolicy
    public let apiKey: String

    @MainActor
    public init(model: AppModel) {
        contextTokens = model.maxContextTokens
        temperature = model.temperature
        topK = model.topKEnabled ? model.topK : nil
        topP = model.topKEnabled && model.topPEnabled ? model.topP : nil
        expertCacheSlots = model.runtimeOptions.expertCacheSlots
        prefillEnabled = model.runtimeOptions.prefillEnabled
        prefillChunkTokens = model.runtimeOptions.prefillChunkTokens
        rdadvisePolicy = model.runtimeOptions.rdadvisePolicy
        apiKey = model.apiKey
    }

    public init(
        contextTokens: Int,
        temperature: Double,
        topK: Int?,
        topP: Double?,
        expertCacheSlots: Int,
        prefillEnabled: Bool,
        prefillChunkTokens: Int,
        rdadvisePolicy: AppRDAdvicePolicy,
        apiKey: String = ""
    ) {
        self.contextTokens = contextTokens
        self.temperature = temperature
        self.topK = topK
        self.topP = topP
        self.expertCacheSlots = expertCacheSlots
        self.prefillEnabled = prefillEnabled
        self.prefillChunkTokens = prefillChunkTokens
        self.rdadvisePolicy = rdadvisePolicy
        self.apiKey = apiKey
    }
}

final class AppServerProcessHandle: @unchecked Sendable {
    private let isRunningValue: @Sendable () -> Bool
    private let terminateAction: @Sendable () -> Void

    init(
        isRunning: @escaping @Sendable () -> Bool,
        terminate: @escaping @Sendable () -> Void
    ) {
        self.isRunningValue = isRunning
        self.terminateAction = terminate
    }

    var isRunning: Bool { isRunningValue() }

    func terminate() {
        terminateAction()
    }
}

private final class FoundationServerProcess: @unchecked Sendable {
    let process = Process()
    let errorPipe = Pipe()
}

@MainActor
@Observable
public final class AppServerController {
    typealias HealthCheck = @Sendable (URL) async -> Bool
    typealias MetricsFetch = @Sendable (URL) async -> AppServerMetrics?
    typealias ProcessLauncher = @MainActor @Sendable (
        URL,
        [String],
        [String: String],
        @escaping @Sendable (Int32, String?) -> Void
    ) throws -> AppServerProcessHandle

    public static let port = 8080
    public static let maxContext = 16_384
    public static let apiBaseURL = URL(string: "http://127.0.0.1:8080/v1")!
    public static let healthURL = URL(string: "http://127.0.0.1:8080/health")!
    static let parentProcessIDEnvironmentKey = "TURBOFIELDFARE_APP_PARENT_PID"
    static let apiKeyEnvironmentKey = "TURBOFIELDFARE_API_KEY"

    public private(set) var state: AppServerState = .stopped
    public private(set) var activeConfiguration: AppServerConfiguration?
    public private(set) var metrics = AppServerMetrics()

    @ObservationIgnored private let serverURL: URL
    @ObservationIgnored private let healthCheck: HealthCheck
    @ObservationIgnored private let metricsFetch: MetricsFetch
    @ObservationIgnored private let launchProcess: ProcessLauncher
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private let maximumHealthChecks: Int
    @ObservationIgnored private var ownedProcess: AppServerProcessHandle?
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var telemetryTask: Task<Void, Never>?
    @ObservationIgnored private var launchGeneration: UInt64 = 0

    public convenience init(serverURL: URL? = nil) {
        self.init(
            serverURL: serverURL ?? Self.defaultServerURL(),
            healthCheck: Self.performHealthCheck,
            metricsFetch: Self.performMetricsFetch,
            launchProcess: Self.launchFoundationProcess,
            pollInterval: .milliseconds(250),
            maximumHealthChecks: 1_200)
    }

    init(
        serverURL: URL,
        healthCheck: @escaping HealthCheck,
        metricsFetch: @escaping MetricsFetch = { _ in nil },
        launchProcess: @escaping ProcessLauncher,
        pollInterval: Duration,
        maximumHealthChecks: Int
    ) {
        self.serverURL = serverURL
        self.healthCheck = healthCheck
        self.metricsFetch = metricsFetch
        self.launchProcess = launchProcess
        self.pollInterval = pollInterval
        self.maximumHealthChecks = maximumHealthChecks
    }

    public var ownsServer: Bool { ownedProcess != nil }

    public var canStart: Bool {
        switch state {
        case .stopped, .failed:
            true
        case .starting, .ready, .alreadyRunning:
            false
        }
    }

    public var canStop: Bool { ownedProcess != nil }

    public func start(
        modelDirectory: URL,
        configuration: AppServerConfiguration
    ) {
        guard canStart else { return }
        launchGeneration &+= 1
        let generation = launchGeneration
        state = .starting
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            guard let self else { return }
            if await healthCheck(Self.healthURL) {
                guard generation == launchGeneration else { return }
                state = .alreadyRunning
                monitorTask = nil
                beginTelemetryPolling(generation: generation)
                return
            }
            guard !Task.isCancelled, generation == launchGeneration else { return }

            do {
                let process = try launchProcess(
                    serverURL,
                    Self.arguments(
                        modelDirectory: modelDirectory,
                        configuration: configuration),
                    Self.childEnvironment(apiKey: configuration.apiKey)
                ) { [weak self] status, detail in
                    Task { @MainActor in
                        self?.processDidTerminate(
                            generation: generation,
                            status: status,
                            detail: detail)
                    }
                }
                guard generation == launchGeneration else {
                    process.terminate()
                    return
                }
                ownedProcess = process
                activeConfiguration = configuration
            } catch {
                guard generation == launchGeneration else { return }
                state = .failed("Could not start the API server: \(error)")
                monitorTask = nil
                return
            }

            for _ in 0..<maximumHealthChecks {
                guard !Task.isCancelled, generation == launchGeneration else { return }
                guard ownedProcess?.isRunning == true else { return }
                if await healthCheck(Self.healthURL) {
                    guard generation == launchGeneration else { return }
                    state = .ready
                    monitorTask = nil
                    beginTelemetryPolling(generation: generation)
                    return
                }
                do {
                    try await Task.sleep(for: pollInterval)
                } catch {
                    return
                }
            }

            guard generation == launchGeneration else { return }
            ownedProcess?.terminate()
            ownedProcess = nil
            activeConfiguration = nil
            state = .failed("The API server did not become ready within five minutes.")
            monitorTask = nil
        }
    }

    public func stop() {
        launchGeneration &+= 1
        monitorTask?.cancel()
        monitorTask = nil
        telemetryTask?.cancel()
        telemetryTask = nil
        metrics = AppServerMetrics()
        let process = ownedProcess
        ownedProcess = nil
        activeConfiguration = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        state = .stopped
    }

    public func restart(
        modelDirectory: URL,
        configuration: AppServerConfiguration
    ) {
        guard ownedProcess != nil else {
            start(modelDirectory: modelDirectory, configuration: configuration)
            return
        }
        stop()
        let generation = launchGeneration
        state = .starting
        monitorTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<40 {
                guard generation == launchGeneration else { return }
                if !(await healthCheck(Self.healthURL)) {
                    state = .stopped
                    monitorTask = nil
                    start(
                        modelDirectory: modelDirectory,
                        configuration: configuration)
                    return
                }
                do {
                    try await Task.sleep(for: pollInterval)
                } catch {
                    return
                }
            }
            guard generation == launchGeneration else { return }
            state = .failed("The previous API server did not stop in time.")
            monitorTask = nil
        }
    }

    static func arguments(
        modelDirectory: URL,
        configuration: AppServerConfiguration
    ) -> [String] {
        [
            "--model", modelDirectory.standardizedFileURL.path,
            "--port", String(port),
            "--max-context", String(configuration.contextTokens),
            "--default-temperature", String(configuration.temperature),
            "--default-top-k", String(configuration.topK ?? 0),
            "--default-top-p", String(configuration.topP ?? 0),
            "--expert-cache-slots", String(configuration.expertCacheSlots),
            "--prefill", configuration.prefillEnabled ? "on" : "off",
            "--prefill-chunk-tokens", String(configuration.prefillChunkTokens),
            "--rdadvise", configuration.rdadvisePolicy.rawValue,
        ]
    }

    static func childEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment,
        parentProcessID: pid_t = getpid(),
        apiKey: String = ""
    ) -> [String: String] {
        var environment = base
        environment[parentProcessIDEnvironmentKey] = String(parentProcessID)
        if !apiKey.isEmpty {
            environment[apiKeyEnvironmentKey] = apiKey
        } else {
            environment.removeValue(forKey: apiKeyEnvironmentKey)
        }
        return environment
    }

    private func processDidTerminate(
        generation: UInt64,
        status: Int32,
        detail: String?
    ) {
        guard generation == launchGeneration else { return }
        ownedProcess = nil
        activeConfiguration = nil
        monitorTask?.cancel()
        monitorTask = nil
        telemetryTask?.cancel()
        telemetryTask = nil
        metrics = AppServerMetrics()
        if status == 0 {
            state = .stopped
            return
        }
        let message = detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        state = .failed(
            message.flatMap { $0.isEmpty ? nil : $0 }
                ?? "The API server exited with status \(status).")
    }

    private static func defaultServerURL() -> URL {
        Bundle.main.executableURL!
            .deletingLastPathComponent()
            .appendingPathComponent("TurboFieldfareServer")
    }

    private static func performHealthCheck(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  response.statusCode == 200,
                  let payload = try JSONSerialization.jsonObject(with: data)
                    as? [String: Any] else {
                return false
            }
            return payload["status"] as? String == "ok"
        } catch {
            return false
        }
    }

    private static func performMetricsFetch(_ url: URL) async -> AppServerMetrics? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  response.statusCode == 200 else {
                return nil
            }
            let payload = try JSONDecoder().decode(ServerHealthPayload.self, from: data)
            guard payload.status == "ok" else { return nil }
            return AppServerMetrics(
                rssBytes: payload.rssBytes,
                tokensPerSecond: payload.tokensPerSecond)
        } catch {
            return nil
        }
    }

    private func beginTelemetryPolling(generation: UInt64) {
        telemetryTask?.cancel()
        telemetryTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, generation == launchGeneration {
                if let snapshot = await metricsFetch(Self.healthURL) {
                    guard generation == launchGeneration else { return }
                    metrics = snapshot
                }
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
            }
        }
    }

    private static func launchFoundationProcess(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        onTermination: @escaping @Sendable (Int32, String?) -> Void
    ) throws -> AppServerProcessHandle {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw CocoaError(
                .fileNoSuchFile,
                userInfo: [NSFilePathErrorKey: executableURL.path])
        }

        let resources = FoundationServerProcess()
        resources.process.executableURL = executableURL
        resources.process.arguments = arguments
        resources.process.environment = environment
        resources.process.standardOutput = FileHandle.nullDevice
        resources.process.standardError = resources.errorPipe
        resources.process.terminationHandler = { process in
            let data = try? resources.errorPipe.fileHandleForReading.readToEnd()
            let detail = data.flatMap { String(data: $0, encoding: .utf8) }
            process.terminationHandler = nil
            onTermination(process.terminationStatus, detail)
        }
        try resources.process.run()

        return AppServerProcessHandle(
            isRunning: { resources.process.isRunning },
            terminate: { resources.process.terminate() })
    }
}

private struct ServerHealthPayload: Decodable {
    let status: String
    let rssBytes: UInt64?
    let tokensPerSecond: Double?

    enum CodingKeys: String, CodingKey {
        case status
        case rssBytes = "rss_bytes"
        case tokensPerSecond = "tokens_per_second"
    }
}
