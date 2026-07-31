import Foundation
import TurboFieldfare

public struct ServerArguments: Equatable, Sendable {
    public let model: String
    public let port: Int
    /// Explicit --model-id value; nil defers to the loaded model's family
    /// default (gemma-4-26b-a4b-it or qwen3.6-35b-a3b).
    public let modelIDOverride: String?
    public var modelID: String { modelIDOverride ?? "gemma-4-26b-a4b-it" }
    public let maxContext: Int
    public let queueLimit: Int
    public let promptCacheMode: ServerPromptCacheMode
    public let samplingDefaults: ServerSamplingDefaults
    public let expertCacheSlots: Int
    public let prefillEnabled: Bool
    public let prefillChunkTokens: Int
    public let rdadvisePolicy: RDAdvicePolicyMode

    public var runtimeConfiguration: RuntimeConfiguration {
        RuntimeConfiguration(
            expertCacheSlots: expertCacheSlots,
            rdadvisePolicy: rdadvisePolicy,
            prefillEnabled: prefillEnabled,
            prefillChunkTokens: prefillChunkTokens,
            forceLogitsHead: true)
    }

    public static let usage = """
    usage: TurboFieldfareServer --model <completed .gturbo directory> [options]

      --model <dir>          Required model directory.
      --port <1...65535>     Loopback port (default 8080).
      --model-id <id>        API model identifier (default derived from the
                             installed model: gemma-4-26b-a4b-it or
                             qwen3.6-35b-a3b).
      --max-context <tokens> 4096, 8192, 16384, 32768, or 65536 (default 16384).
      --queue-limit <count>  Maximum queued requests (default 4).
      --prompt-cache-mode <off|single-prefix>
                             Prompt KV reuse mode (default single-prefix).
      --default-temperature <0...2>
                             Temperature when a request omits it (default 0.2).
      --default-top-k <0...256>
                             Top-K when omitted; 0 disables it (default 64).
      --default-top-p <0...1>
                             Top-P when omitted; 0 disables it (default 0.95).
      --expert-cache-slots <8|16|24|32>
                             Routed-expert cache slots (default 16).
      --prefill <on|off>     Chunked prefill (default on).
      --prefill-chunk-tokens <32|64|128>
                             Prefill chunk size (default 128).
      --rdadvise <off|default|bounded|adaptive>
                             Routed-expert read advice (default off).
      --help                 Show this help.
    """

    public static func parse(_ input: [String]) throws -> ServerArguments {
        var model: String?
        var port = 8080
        var modelIDOverride: String?
        var maxContext = 16_384
        var queueLimit = 4
        var promptCacheMode: ServerPromptCacheMode = .singlePrefix
        var temperature: Float = 0.2
        var topK: Int? = 64
        var topP: Float? = 0.95
        var expertCacheSlots = 16
        var prefillEnabled = true
        var prefillChunkTokens = 128
        var rdadvisePolicy: RDAdvicePolicyMode = .off
        var index = 0
        while index < input.count {
            let flag = input[index]
            if flag == "--help" || flag == "-h" { throw ServerArgumentError.help }
            guard index + 1 < input.count else {
                throw ServerArgumentError.invalid("\(flag) requires a value")
            }
            let value = input[index + 1]
            index += 2
            switch flag {
            case "--model":
                model = value
            case "--port":
                guard let parsed = Int(value), (1...65_535).contains(parsed) else {
                    throw ServerArgumentError.invalid("--port must be between 1 and 65535")
                }
                port = parsed
            case "--model-id":
                guard !value.isEmpty else {
                    throw ServerArgumentError.invalid("--model-id must not be empty")
                }
                modelIDOverride = value
            case "--max-context":
                guard let parsed = Int(value),
                      [4_096, 8_192, 16_384, 32_768, 65_536].contains(parsed) else {
                    throw ServerArgumentError.invalid("--max-context is not supported")
                }
                maxContext = parsed
            case "--queue-limit":
                guard let parsed = Int(value), parsed > 0 else {
                    throw ServerArgumentError.invalid("--queue-limit must be positive")
                }
                queueLimit = parsed
            case "--prompt-cache-mode":
                guard let parsed = ServerPromptCacheMode(rawValue: value) else {
                    throw ServerArgumentError.invalid(
                        "--prompt-cache-mode must be off or single-prefix")
                }
                promptCacheMode = parsed
            case "--default-temperature":
                guard let parsed = Float(value), parsed.isFinite,
                      (0...2).contains(parsed) else {
                    throw ServerArgumentError.invalid(
                        "--default-temperature must be between 0 and 2")
                }
                temperature = parsed
            case "--default-top-k":
                guard let parsed = Int(value), (0...256).contains(parsed) else {
                    throw ServerArgumentError.invalid(
                        "--default-top-k must be between 0 and 256")
                }
                topK = parsed == 0 ? nil : parsed
            case "--default-top-p":
                guard let parsed = Float(value), parsed.isFinite,
                      (0...1).contains(parsed) else {
                    throw ServerArgumentError.invalid(
                        "--default-top-p must be between 0 and 1")
                }
                topP = parsed == 0 ? nil : parsed
            case "--expert-cache-slots":
                guard let parsed = Int(value),
                      RuntimeConfiguration.allowedExpertCacheSlots.contains(parsed) else {
                    throw ServerArgumentError.invalid(
                        "--expert-cache-slots is not supported")
                }
                expertCacheSlots = parsed
            case "--prefill":
                guard value == "on" || value == "off" else {
                    throw ServerArgumentError.invalid(
                        "--prefill must be on or off")
                }
                prefillEnabled = value == "on"
            case "--prefill-chunk-tokens":
                guard let parsed = Int(value),
                      RuntimeConfiguration.allowedPrefillChunkTokens.contains(parsed) else {
                    throw ServerArgumentError.invalid(
                        "--prefill-chunk-tokens is not supported")
                }
                prefillChunkTokens = parsed
            case "--rdadvise":
                guard let parsed = RDAdvicePolicyMode(rawValue: value) else {
                    throw ServerArgumentError.invalid(
                        "--rdadvise is not supported")
                }
                rdadvisePolicy = parsed
            default:
                throw ServerArgumentError.invalid("unknown flag: \(flag)")
            }
        }
        guard let model else { throw ServerArgumentError.invalid("--model is required") }
        if temperature > 0, topK == nil, let topP, topP < 1 {
            throw ServerArgumentError.invalid(
                "--default-top-p below 1 requires --default-top-k")
        }
        return ServerArguments(model: model,
                               port: port,
                               modelIDOverride: modelIDOverride,
                               maxContext: maxContext,
                               queueLimit: queueLimit,
                               promptCacheMode: promptCacheMode,
                               samplingDefaults: ServerSamplingDefaults(
                                temperature: temperature,
                                topK: topK,
                                topP: topP),
                               expertCacheSlots: expertCacheSlots,
                               prefillEnabled: prefillEnabled,
                               prefillChunkTokens: prefillChunkTokens,
                               rdadvisePolicy: rdadvisePolicy)
    }
}

public enum ServerArgumentError: Error, Equatable, CustomStringConvertible {
    case help
    case invalid(String)

    public var description: String {
        switch self {
        case .help: "help"
        case .invalid(let message): message
        }
    }
}
