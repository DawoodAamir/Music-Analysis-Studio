import AVFoundation
import Foundation
import MusicUnderstanding

public enum AnalysisError: Error, LocalizedError {
  case invalidAudio, tooLarge, invalidReport
  public var errorDescription: String? {
    switch self {
    case .invalidAudio: "Choose an unprotected audio file between 2 seconds and 20 minutes."
    case .tooLarge: "Use an audio file up to 100 MB."
    case .invalidReport: "A saved report is invalid. Existing files were preserved."
    }
  }
}
public struct MetricPoint: Codable, Sendable, Equatable {
  public let seconds: Double
  public let value: Double
}
public struct TimelineRange: Codable, Sendable, Equatable, Identifiable {
  public var id: Double { start }
  public let start: Double
  public let end: Double
  public let label: String
}
public struct MusicReport: Codable, Sendable, Identifiable {
  public var version = 1
  public let id: UUID
  public let title: String
  public let audioExtension: String
  public let created: Date
  public let duration: Double
  public let bpm: Double?
  public let integratedLoudness: Double?
  public let beats: [Double]
  public let sections: [TimelineRange]
  public let keys: [TimelineRange]
  public let loudness: [MetricPoint]
  public let pace: [MetricPoint]
  public let instruments: [String: [MetricPoint]]
  public func validate() throws {
    guard version == 1, !audioExtension.isEmpty, audioExtension.count <= 10,
      audioExtension.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) }),
      duration.isFinite, (2...1200).contains(duration),
      title.count <= 200, beats.count < 100_000,
      beats.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= duration }),
      bpm.map({ $0.isFinite && $0 > 0 }) ?? true,
      integratedLoudness.map(\.isFinite) ?? true
    else { throw AnalysisError.invalidReport }
    for values in [loudness, pace] + Array(instruments.values) {
      guard values.count < 100_000,
        values.allSatisfy({
          $0.seconds.isFinite && $0.seconds >= 0 && $0.seconds <= duration && $0.value.isFinite
        })
      else { throw AnalysisError.invalidReport }
    }
    guard
      (sections + keys).allSatisfy({
        $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end >= $0.start
          && $0.end <= duration
      })
    else { throw AnalysisError.invalidReport }
  }
}
public enum MusicFormatting {
  public static func clock(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "—" }
    let total = Int(min(seconds, 86_400))
    return String(format: "%d:%02d", total / 60, total % 60)
  }
  public static func pitch(_ value: String) -> String {
    value.replacingOccurrences(of: "Flat", with: "♭").replacingOccurrences(of: "Sharp", with: "♯")
      .prefix(1).uppercased()
      + value.replacingOccurrences(of: "Flat", with: "♭")
      .replacingOccurrences(of: "Sharp", with: "♯").dropFirst()
  }
}
public actor MusicLibrary {
  public nonisolated let root: URL
  public init(root: URL) { self.root = root }
  public nonisolated func audioURL(_ report: MusicReport) -> URL {
    root.appendingPathComponent(report.id.uuidString + "." + report.audioExtension)
  }
  public func reports() throws -> [MusicReport] {
    guard FileManager.default.fileExists(atPath: root.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "json" }.map { url in
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) < 20_000_000 else {
          throw AnalysisError.invalidReport
        }
        let report = try JSONDecoder().decode(MusicReport.self, from: Data(contentsOf: url))
        try report.validate()
        return report
      }.sorted { $0.created > $1.created }
  }
  public func importAndAnalyze(
    _ url: URL,
    types: Set<AnalysisType> = [.rhythm, .key, .structure, .loudness, .pace, .instrumentActivity]
  ) async throws -> MusicReport {
    let id = UUID()
    let ext = url.pathExtension.lowercased()
    guard !ext.isEmpty, ext.count <= 10,
      ext.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) })
    else { throw AnalysisError.invalidAudio }
    let destination = root.appendingPathComponent(id.uuidString + "." + ext)
    do {
      try copySelected(url, to: destination)
      let asset = AVURLAsset(
        url: destination, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
      let duration = try await asset.load(.duration).seconds
      guard duration.isFinite, (2...1200).contains(duration),
        try await !asset.load(.hasProtectedContent),
        try await !asset.loadTracks(withMediaType: .audio).isEmpty
      else { throw AnalysisError.invalidAudio }
      try Task.checkCancellation()
      let session = try await MusicUnderstandingSession(asset: asset)
      let result = try await withTaskCancellationHandler {
        try await session.analyze(for: types)
      } onCancel: {
        Task { await session.cancel() }
      }
      try Task.checkCancellation()
      func seconds(_ times: [CMTime]) -> [Double] {
        times.map(\.seconds).filter { $0.isFinite && $0 >= 0 && $0 <= duration }
      }
      func points(_ values: [MusicUnderstandingSession.TimedValue<Float>]) -> [MetricPoint] {
        values.compactMap { point in
          let t = point.time.seconds
          guard t.isFinite, t >= 0, t <= duration, point.value.isFinite else { return nil }
          return MetricPoint(seconds: t, value: Double(point.value))
        }
      }
      let sections = (result.structure?.sections ?? []).enumerated().compactMap {
        index, range -> TimelineRange? in
        let start = range.start.seconds
        let end = min(duration, range.end.seconds)
        guard start.isFinite, end.isFinite, start >= 0, end >= start else { return nil }
        return TimelineRange(start: start, end: end, label: "Section \(index + 1)")
      }
      let keys = (result.key?.ranges ?? []).compactMap { range -> TimelineRange? in
        let start = range.range.start.seconds
        let end = min(duration, range.range.end.seconds)
        guard start.isFinite, end.isFinite, start >= 0, end >= start else { return nil }
        return TimelineRange(
          start: start, end: end,
          label: MusicFormatting.pitch(range.value.tonic.rawValue) + " " + range.value.mode.rawValue
        )
      }
      let pace = (result.pace?.ranges ?? []).compactMap { range -> MetricPoint? in
        let t = range.range.start.seconds
        guard t.isFinite, t >= 0, t <= duration, range.value.isFinite else { return nil }
        return MetricPoint(seconds: t, value: range.value)
      }
      var instruments: [String: [MetricPoint]] = [:]
      for (instrument, values) in result.instrumentActivity?.activity ?? [:] {
        instruments[instrument.rawValue] = points(values)
      }
      let bpm = result.rhythm?.beatsPerMinute.flatMap { $0.isFinite && $0 > 0 ? Double($0) : nil }
      let level = result.loudness?.integrated.value
      let report = MusicReport(
        id: id, title: String(url.deletingPathExtension().lastPathComponent.prefix(200)),
        audioExtension: ext, created: Date(), duration: duration,
        bpm: bpm, integratedLoudness: level.flatMap { $0.isFinite ? Double($0) : nil },
        beats: seconds(result.rhythm?.beats ?? []), sections: sections, keys: keys,
        loudness: points(result.loudness?.momentary ?? []), pace: pace, instruments: instruments)
      try report.validate()
      try JSONEncoder().encode(report).write(
        to: root.appendingPathComponent(id.uuidString + ".json"), options: .atomic)
      return report
    } catch {
      try? FileManager.default.removeItem(at: destination)
      throw error
    }
  }
  private func copySelected(_ url: URL, to destination: URL) throws {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 100_000_000 else {
      throw AnalysisError.tooLarge
    }
    let data = try Data(contentsOf: url)
    guard data.count <= 100_000_000 else { throw AnalysisError.tooLarge }
    try Task.checkCancellation()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try data.write(to: destination, options: .atomic)
  }
}
