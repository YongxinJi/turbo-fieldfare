import Foundation
import Testing
@testable import TurboFieldfareRepackCore

@Suite struct HuggingFaceEndpointTests {
    @Test func defaultsToOfficialEndpoint() throws {
        #expect(try HuggingFaceEndpoint.resolve(environment: [:])
            == URL(string: "https://huggingface.co")!)
    }

    @Test func acceptsHTTPSMirrorOrigin() throws {
        #expect(try HuggingFaceEndpoint.resolve(environment: [
            "HF_ENDPOINT": "https://hf-mirror.com/",
        ]) == URL(string: "https://hf-mirror.com")!)
    }

    @Test(arguments: [
        "http://hf-mirror.com",
        "https://user:secret@hf-mirror.com",
        "https://hf-mirror.com/prefix",
        "https://hf-mirror.com?query=value",
        "https://hf-mirror.com#fragment",
    ])
    func rejectsUnsafeEndpoint(_ value: String) {
        #expect(throws: RepackError.self) {
            try HuggingFaceEndpoint.resolve(environment: ["HF_ENDPOINT": value])
        }
    }

    @Test func tokenIsRestrictedToOfficialHost() {
        let environment = ["HF_TOKEN": "secret"]
        #expect(HuggingFaceEndpoint.token(
            for: URL(string: "https://huggingface.co")!,
            environment: environment) == "secret")
        #expect(HuggingFaceEndpoint.token(
            for: URL(string: "https://hf-mirror.com")!,
            environment: environment) == nil)
    }
}
