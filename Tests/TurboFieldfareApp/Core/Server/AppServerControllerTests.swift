import Foundation
import Synchronization
import Testing
@testable import TurboFieldfareAppCore

@Suite("App server controller")
struct AppServerControllerTests {
    @MainActor
    @Test func launchesBundledServerAndBecomesReady() async throws {
        let health = HealthSequence([false, true])
        let process = TestServerProcess()
        let launcher = TestServerLauncher(process: process)
        let controller = makeController(health: health, launcher: launcher)
        let model = URL(fileURLWithPath: "/tmp/model.gturbo", isDirectory: true)

        controller.start(modelDirectory: model, configuration: configuration)
        try await waitUntil { controller.state == .ready }

        let launch = try #require(launcher.launch)
        #expect(launch.executable.path == "/tmp/TurboFieldfareServer")
        #expect(launch.arguments == [
            "--model", "/tmp/model.gturbo",
            "--port", "8080",
            "--max-context", "8192",
            "--default-temperature", "0.4",
            "--default-top-k", "32",
            "--default-top-p", "0.8",
            "--expert-cache-slots", "24",
            "--prefill", "off",
            "--prefill-chunk-tokens", "64",
            "--rdadvise", "adaptive",
        ])
        #expect(!launch.arguments.contains(configuration.apiKey))
        #expect(
            launch.environment[AppServerController.apiKeyEnvironmentKey]
                == configuration.apiKey)
        #expect(controller.ownsServer)
        #expect(controller.canStop)
        #expect(controller.activeConfiguration == configuration)
        try await waitUntil {
            controller.metrics
                == AppServerMetrics(rssBytes: 7_000_000_000, tokensPerSecond: 9.5)
        }
    }

    @MainActor
    @Test func existingHealthyServerIsNeverAdoptedOrStopped() async throws {
        let health = HealthSequence([true])
        let process = TestServerProcess()
        let launcher = TestServerLauncher(process: process)
        let controller = makeController(health: health, launcher: launcher)

        controller.start(
            modelDirectory: URL(fileURLWithPath: "/tmp/model.gturbo"),
            configuration: configuration)
        try await waitUntil { controller.state == .alreadyRunning }
        controller.stop()

        #expect(launcher.launch == nil)
        #expect(process.terminationCount == 0)
        #expect(controller.state == .stopped)
    }

    @MainActor
    @Test func stopTerminatesOnlyTheOwnedProcess() async throws {
        let health = HealthSequence([false, true])
        let process = TestServerProcess()
        let launcher = TestServerLauncher(process: process)
        let controller = makeController(health: health, launcher: launcher)

        controller.start(
            modelDirectory: URL(fileURLWithPath: "/tmp/model.gturbo"),
            configuration: configuration)
        try await waitUntil { controller.state == .ready }
        controller.stop()

        #expect(process.terminationCount == 1)
        #expect(controller.state == .stopped)
        #expect(!controller.ownsServer)
        #expect(controller.activeConfiguration == nil)
    }

    @MainActor
    @Test func failedOwnedProcessSurfacesItsError() async throws {
        let health = HealthSequence([false, false, false])
        let process = TestServerProcess()
        let launcher = TestServerLauncher(process: process)
        let controller = makeController(health: health, launcher: launcher)

        controller.start(
            modelDirectory: URL(fileURLWithPath: "/tmp/model.gturbo"),
            configuration: configuration)
        try await waitUntil { launcher.launch != nil }
        launcher.finish(status: 1, detail: "error: model could not load")
        try await waitUntil {
            controller.state == .failed("error: model could not load")
        }

        #expect(!controller.ownsServer)
        #expect(controller.canStart)
    }

    @MainActor
    @Test func restartWaitsForOldServerAndAppliesNewConfiguration() async throws {
        let health = HealthSequence([false, true, false, false, true])
        let process = TestServerProcess()
        let launcher = TestServerLauncher(process: process)
        let controller = makeController(health: health, launcher: launcher)
        let updated = AppServerConfiguration(
            contextTokens: 32_768,
            temperature: 0,
            topK: nil,
            topP: nil,
            expertCacheSlots: 32,
            prefillEnabled: true,
            prefillChunkTokens: 128,
            rdadvisePolicy: .bounded)

        controller.start(
            modelDirectory: URL(fileURLWithPath: "/tmp/model.gturbo"),
            configuration: configuration)
        try await waitUntil { controller.state == .ready }
        controller.restart(
            modelDirectory: URL(fileURLWithPath: "/tmp/model.gturbo"),
            configuration: updated)
        try await waitUntil {
            controller.state == .ready
                && controller.activeConfiguration == updated
        }

        #expect(process.terminationCount == 1)
        #expect(launcher.launchCount == 2)
        #expect(launcher.launch?.arguments.contains("32768") == true)
    }

    @MainActor
    @Test func childEnvironmentLinksServerToAppProcess() {
        let environment = AppServerController.childEnvironment(
            base: ["EXISTING": "value"],
            parentProcessID: 12_345,
            apiKey: "secret-key")

        #expect(environment["EXISTING"] == "value")
        #expect(
            environment[AppServerController.parentProcessIDEnvironmentKey]
                == "12345")
        #expect(
            environment[AppServerController.apiKeyEnvironmentKey]
                == "secret-key")
    }

    @MainActor
    private func makeController(
        health: HealthSequence,
        launcher: TestServerLauncher
    ) -> AppServerController {
        AppServerController(
            serverURL: URL(fileURLWithPath: "/tmp/TurboFieldfareServer"),
            healthCheck: { url in await health.check(url) },
            metricsFetch: { _ in
                AppServerMetrics(
                    rssBytes: 7_000_000_000,
                    tokensPerSecond: 9.5)
            },
            launchProcess: { executable, arguments, environment, onTermination in
                launcher.start(
                    executable: executable,
                    arguments: arguments,
                    environment: environment,
                    onTermination: onTermination)
            },
            pollInterval: .milliseconds(1),
            maximumHealthChecks: 20)
    }

    @MainActor
    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("timed out waiting for server state")
    }

    private var configuration: AppServerConfiguration {
        AppServerConfiguration(
            contextTokens: 8_192,
            temperature: 0.4,
            topK: 32,
            topP: 0.8,
            expertCacheSlots: 24,
            prefillEnabled: false,
            prefillChunkTokens: 64,
            rdadvisePolicy: .adaptive,
            apiKey: "0123456789abcdef0123456789abcdef")
    }
}

private actor HealthSequence {
    private var values: [Bool]

    init(_ values: [Bool]) {
        self.values = values
    }

    func check(_ url: URL) -> Bool {
        _ = url
        guard values.count > 1 else { return values.first ?? false }
        return values.removeFirst()
    }
}

private final class TestServerProcess: @unchecked Sendable {
    private struct State: Sendable {
        var isRunning = true
        var terminationCount = 0
    }

    private let state = Mutex(State())

    var terminationCount: Int {
        state.withLock { $0.terminationCount }
    }

    var handle: AppServerProcessHandle {
        AppServerProcessHandle(
            isRunning: { self.isRunning },
            terminate: { self.terminate() })
    }

    private var isRunning: Bool {
        state.withLock { $0.isRunning }
    }

    private func terminate() {
        state.withLock {
            $0.isRunning = false
            $0.terminationCount += 1
        }
    }

    func markFinished() {
        state.withLock { $0.isRunning = false }
    }

    func markRunning() {
        state.withLock { $0.isRunning = true }
    }
}

private final class TestServerLauncher: @unchecked Sendable {
    struct Launch: Sendable {
        let executable: URL
        let arguments: [String]
        let environment: [String: String]
    }

    private struct State: Sendable {
        var launch: Launch?
        var launchCount = 0
        var termination: (@Sendable (Int32, String?) -> Void)?
    }

    private let process: TestServerProcess
    private let state = Mutex(State())

    init(process: TestServerProcess) {
        self.process = process
    }

    var launch: Launch? {
        state.withLock { $0.launch }
    }

    var launchCount: Int {
        state.withLock { $0.launchCount }
    }

    func start(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        onTermination: @escaping @Sendable (Int32, String?) -> Void
    ) -> AppServerProcessHandle {
        process.markRunning()
        state.withLock {
            $0.launch = Launch(
                executable: executable,
                arguments: arguments,
                environment: environment)
            $0.launchCount += 1
            $0.termination = onTermination
        }
        return process.handle
    }

    func finish(status: Int32, detail: String?) {
        process.markFinished()
        let termination = state.withLock { $0.termination }
        termination?(status, detail)
    }
}
