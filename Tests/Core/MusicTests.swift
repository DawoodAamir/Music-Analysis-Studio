import Foundation
import MusicUnderstanding
import Testing

@testable import MusicCore

@Test func timeAndPitchFormattingHandlesInvalidInputs() {
  #expect(MusicFormatting.clock(.nan) == "—")
  #expect(MusicFormatting.clock(-1) == "—")
  #expect(MusicFormatting.clock(65) == "1:05")
  #expect(MusicFormatting.pitch("dFlat") == "D♭")
}
@Test func realAnalysisPersistsAndPreservesAudio() async throws {
  let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Fixtures/StudioPulse.wav")
  let library = MusicLibrary(root: root)
  let report = try await library.importAndAnalyze(fixture)
  #expect(abs(report.duration - 16) < 0.1)
  #expect(report.integratedLoudness != nil)
  #expect(!report.loudness.isEmpty)
  let loaded = try await MusicLibrary(root: root).reports()
  #expect(loaded.first?.id == report.id)
  #expect(try Data(contentsOf: library.audioURL(report)) == Data(contentsOf: fixture))
}
@Test func invalidAudioLeavesNoStagedFiles() async throws {
  let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
  try Data("invalid audio".utf8).write(to: file)
  defer {
    try? FileManager.default.removeItem(at: root)
    try? FileManager.default.removeItem(at: file)
  }
  let library = MusicLibrary(root: root)
  await #expect(throws: (any Error).self) { _ = try await library.importAndAnalyze(file) }
  #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
}
