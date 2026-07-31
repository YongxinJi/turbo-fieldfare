import Darwin
import Dispatch
import Foundation
import TurboFieldfareServerCore

private let appParentProcessIDEnvironmentKey = "TURBOFIELDFARE_APP_PARENT_PID"

private func makeAppParentProcessMonitor() -> (any DispatchSourceProcess)? {
    guard let value = ProcessInfo.processInfo.environment[
        appParentProcessIDEnvironmentKey
    ],
    let parentProcessID = pid_t(value),
    parentProcessID > 1 else {
        return nil
    }

    let source = DispatchSource.makeProcessSource(
        identifier: parentProcessID,
        eventMask: .exit,
        queue: .global(qos: .utility))
    source.setEventHandler {
        Darwin._exit(0)
    }
    source.resume()
    return source
}

let arguments: ServerArguments
do {
    arguments = try ServerArguments.parse(Array(CommandLine.arguments.dropFirst()))
} catch ServerArgumentError.help {
    print(ServerArguments.usage)
    exit(0)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n\n\(ServerArguments.usage)\n".utf8))
    exit(2)
}

do {
    let signals = ServerTerminationSignals()
    let appParentProcessMonitor = makeAppParentProcessMonitor()
    defer { appParentProcessMonitor?.cancel() }
    let modelURL = URL(fileURLWithPath: arguments.model).standardizedFileURL
    let backend = try await ServerModelSession.load(
        modelDirectory: modelURL,
        maxContext: arguments.maxContext,
        promptCacheMode: arguments.promptCacheMode,
        runtimeConfiguration: arguments.runtimeConfiguration)
    let modelID = arguments.modelIDOverride ?? backend.defaultModelID
    let server = TurboFieldfareHTTPServer(
        modelID: modelID,
        queueLimit: arguments.queueLimit,
        backend: backend,
        chatDialect: backend.chatDialect,
        samplingDefaults: arguments.samplingDefaults,
        apiKey: ProcessInfo.processInfo.environment["TURBOFIELDFARE_API_KEY"])
    _ = try await server.start(port: arguments.port)
    print("TurboFieldfareServer ready at http://127.0.0.1:\(arguments.port) model=\(modelID) context=\(arguments.maxContext) prompt_cache=\(arguments.promptCacheMode.rawValue)")

    _ = await signals.wait()
    try await server.shutdown()
    await signals.cancel()
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
