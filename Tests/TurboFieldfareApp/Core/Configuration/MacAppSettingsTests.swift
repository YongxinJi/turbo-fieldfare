import Foundation
import Testing
@testable import TurboFieldfareAppCore

@Suite struct MacAppSettingsTests {
    @Test func settingsFileLivesBesideModelDirectory() {
        let model = URL(fileURLWithPath: "/tmp/TurboFieldfare/gemma4.gturbo",
                        isDirectory: true)
        #expect(MacAppSettingsFileStore.fileURL(forModelDirectory: model).path
            == "/tmp/TurboFieldfare/mac-app-settings.json")
    }

    @Test func missingFileCreatesReadableDefaults() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = root.appendingPathComponent("gemma4.gturbo", isDirectory: true)

        let settings = MacAppSettingsFileStore.loadOrCreate(forModelDirectory: model)
        let fileURL = MacAppSettingsFileStore.fileURL(forModelDirectory: model)

        #expect(settings.apiKey.count == 64)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        let decoded = try JSONDecoder().decode(
            MacAppSettings.self,
            from: Data(contentsOf: fileURL))
        #expect(decoded == settings)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func malformedFileIsReplacedWithDefaults() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = root.appendingPathComponent("gemma4.gturbo", isDirectory: true)
        let fileURL = MacAppSettingsFileStore.fileURL(forModelDirectory: model)
        try Data("not json".utf8).write(to: fileURL)

        let settings = MacAppSettingsFileStore.loadOrCreate(forModelDirectory: model)

        #expect(settings.apiKey.count == 64)
        let decoded = try JSONDecoder().decode(
            MacAppSettings.self,
            from: Data(contentsOf: fileURL))
        #expect(decoded == settings)
    }

    @Test func invalidValuesAreReplacedWithDefaults() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = root.appendingPathComponent("gemma4.gturbo", isDirectory: true)
        let invalid = MacAppSettings(contextTokens: 123)
        let fileURL = MacAppSettingsFileStore.fileURL(forModelDirectory: model)
        try JSONEncoder().encode(invalid).write(to: fileURL)

        let settings = MacAppSettingsFileStore.loadOrCreate(forModelDirectory: model)

        #expect(settings.apiKey.count == 64)
    }

    @MainActor
    @Test func appModelLoadsAndSavesPersistedSettings() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let modelDirectory = root.appendingPathComponent("gemma4.gturbo", isDirectory: true)
        try FileManager.default.createDirectory(
            at: modelDirectory,
            withIntermediateDirectories: true)
        let initial = MacAppSettings(
            contextTokens: 8_192,
            expertCacheSlots: 24,
            temperature: 0.4,
            topKEnabled: false,
            topK: 32,
            topPEnabled: false,
            topP: 0.8,
            prefillEnabled: false,
            rdadvisePolicy: .bounded,
            apiKey: String(repeating: "a", count: 64))
        try MacAppSettingsFileStore.save(initial, forModelDirectory: modelDirectory)

        let model = AppModel(
            modelDirectory: modelDirectory,
            settingsPersistenceEnabled: true)
        #expect(model.maxContextTokens == 8_192)
        #expect(model.runtimeOptions.expertCacheSlots == 24)
        #expect(model.temperature == 0.4)
        #expect(!model.topKEnabled)
        #expect(model.topK == 32)
        #expect(!model.topPEnabled)
        #expect(model.topP == 0.8)
        #expect(!model.runtimeOptions.prefillEnabled)
        #expect(model.runtimeOptions.rdadvisePolicy == .bounded)
        #expect(model.apiKey == initial.apiKey)

        model.temperature = 0.6
        model.runtimeOptions.expertCacheSlots = 32
        model.runtimeOptions.prefillEnabled = true
        model.runtimeOptions.rdadvisePolicy = .adaptive
        let beforeGenerate = MacAppSettingsFileStore.loadOrCreate(
            forModelDirectory: modelDirectory)
        #expect(beforeGenerate == initial)

        model.loadState = .ready(modelDirectory: modelDirectory, loadSeconds: 0)
        model.promptText = "Save these settings"
        model.run()
        let saved = MacAppSettingsFileStore.loadOrCreate(
            forModelDirectory: modelDirectory)
        #expect(saved.temperature == 0.6)
        #expect(saved.expertCacheSlots == 32)
        #expect(saved.prefillEnabled)
        #expect(saved.rdadvisePolicy == .adaptive)

        let previousKey = model.apiKey
        model.rotateAPIKey()
        let rotated = MacAppSettingsFileStore.loadOrCreate(
            forModelDirectory: modelDirectory)
        #expect(rotated.apiKey.count == 64)
        #expect(rotated.apiKey != previousKey)
        model.cancel()
    }

    @Test func legacySettingsDefaultRDADVISEToOff() throws {
        let data = Data(#"""
        {
          "version": 1,
          "contextTokens": 4096,
          "expertCacheSlots": 16,
          "temperature": 0.2,
          "topKEnabled": true,
          "topK": 64,
          "topPEnabled": true,
          "topP": 0.95,
          "prefillEnabled": true
        }
        """#.utf8)

        let settings = try JSONDecoder().decode(MacAppSettings.self, from: data)

        #expect(settings.rdadvisePolicy == .off)
        #expect(settings.apiKey.isEmpty)
        #expect(settings.isValid())
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacAppSettingsTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true)
        return root
    }
}
