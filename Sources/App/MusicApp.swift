import AVFoundation
import Charts
import SwiftUI
import UniformTypeIdentifiers

@main struct MusicApp: App {
  var body: some Scene { WindowGroup { MusicView() }.defaultSize(width: 1100, height: 760) }
}
struct ReportDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.json] }
  let data: Data
  init(_ report: MusicReport) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    data = try encoder.encode(report)
  }
  init(configuration: ReadConfiguration) throws {
    data = configuration.file.regularFileContents ?? Data()
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}
@MainActor @Observable final class MusicModel {
  let library: MusicLibrary
  var reports: [MusicReport] = []
  var selected: MusicReport?
  var busy = false
  var error: String?
  var position = 0.0
  var playing = false
  private var player: AVAudioPlayer?
  private var timer: Task<Void, Never>?
  private var analysis: Task<Void, Never>?
  private var generation = UUID()
  init() {
    let name =
      ProcessInfo.processInfo.environment["MUSIC_TEST_STORE"].map { "MusicTests-" + $0 }
      ?? "Music Analysis Studio"
    library = MusicLibrary(root: URL.applicationSupportDirectory.appendingPathComponent(name))
  }
  func load() async {
    do { reports = try await library.reports() } catch { self.error = error.localizedDescription }
  }
  func select(_ report: MusicReport) {
    pause()
    selected = report
    position = 0
    do {
      player = try AVAudioPlayer(contentsOf: library.audioURL(report))
      player?.prepareToPlay()
    } catch {
      player = nil
      self.error = error.localizedDescription
    }
  }
  func analyze(_ url: URL) {
    cancel()
    busy = true
    let id = generation
    analysis = Task {
      do {
        let report = try await library.importAndAnalyze(url)
        guard id == generation, !Task.isCancelled else { return }
        reports = try await library.reports()
        select(report)
        busy = false
      } catch {
        if id == generation && !Task.isCancelled {
          self.error = error.localizedDescription
          busy = false
        }
      }
    }
  }
  func cancel() {
    analysis?.cancel()
    generation = UUID()
    busy = false
  }
  func pause() {
    player?.pause()
    playing = false
    timer?.cancel()
    timer = nil
  }
  func play() {
    guard let player else { return }
    if player.currentTime >= player.duration - 0.05 { player.currentTime = 0 }
    guard player.play() else {
      error = "Playback couldn't start."
      return
    }
    playing = true
    timer?.cancel()
    timer = Task {
      while !Task.isCancelled {
        position = player.currentTime
        if !player.isPlaying {
          playing = false
          break
        }
        try? await Task.sleep(for: .milliseconds(100))
      }
    }
  }
  func seek(_ seconds: Double) {
    guard let player, seconds.isFinite else { return }
    player.currentTime = min(player.duration, max(0, seconds))
    position = player.currentTime
  }
}
struct MusicView: View {
  @State private var model = MusicModel()
  @State private var selection: UUID?
  @State private var importing = false
  @State private var exporting = false
  @State private var export: ReportDocument?
  var body: some View {
    NavigationSplitView {
      List {
        ForEach(model.reports) { report in
          Button {
            model.select(report)
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(report.title).font(.headline)
              Text(MusicFormatting.clock(report.duration)).font(.caption).foregroundStyle(
                .secondary)
            }
          }.accessibilityIdentifier("music-report-" + report.id.uuidString)
        }
      }.navigationTitle("Music Analysis").navigationSplitViewColumnWidth(min: 210, ideal: 250)
        .toolbar {
          Button("Import audio", systemImage: "waveform.badge.plus") { importing = true }.disabled(
            model.busy)
        }
    } detail: {
      VStack(spacing: 0) {
        if model.busy {
          HStack {
            ProgressView()
            Text("Analyzing on this device…")
            Spacer()
            Button("Cancel analysis") { model.cancel() }
          }.padding()
          Divider()
        }
        if let report = model.selected {
          ScrollView {
            VStack(alignment: .leading, spacing: 24) {
              Text(report.title).font(.largeTitle.bold())
              HStack(spacing: 30) {
                metric("Tempo", report.bpm.map { String(format: "%.1f BPM", $0) } ?? "Not detected")
                metric(
                  "Integrated loudness",
                  report.integratedLoudness.map { String(format: "%.1f LUFS", $0) } ?? "Unavailable"
                )
                metric("Duration", MusicFormatting.clock(report.duration))
              }
              GroupBox("Loudness over time") {
                plot(report.loudness, title: "LUFS", duration: report.duration)
              }
              GroupBox("Beats") {
                Chart {
                  ForEach(Array(report.beats.enumerated()), id: \.offset) { _, beat in
                    RuleMark(x: .value("Seconds", beat)).foregroundStyle(.secondary.opacity(0.5))
                  }
                  RuleMark(x: .value("Playhead", model.position)).foregroundStyle(Color.accentColor)
                }.chartXScale(domain: 0...report.duration).chartYAxis(.hidden).frame(height: 65)
                  .accessibilityLabel("\(report.beats.count) detected beats")
              }
              GroupBox("Song sections") {
                if report.sections.isEmpty {
                  Text("No sections detected.").foregroundStyle(.secondary)
                } else {
                  ForEach(report.sections) { range in
                    Button {
                      model.seek(range.start)
                    } label: {
                      HStack {
                        Text(range.label)
                        Spacer()
                        Text(
                          MusicFormatting.clock(range.start) + " – "
                            + MusicFormatting.clock(range.end)
                        ).monospacedDigit()
                      }
                    }.buttonStyle(.plain).padding(.vertical, 4)
                  }
                }
              }
              GroupBox("Musical key") {
                if report.keys.isEmpty {
                  Text("No key detected.").foregroundStyle(.secondary)
                } else {
                  ForEach(report.keys) { range in
                    HStack {
                      Text(range.label)
                      Spacer()
                      Text(MusicFormatting.clock(range.start)).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                  }
                }
              }
              GroupBox("Perceived pace") {
                plot(report.pace, title: "Events per minute", duration: report.duration)
              }
              ForEach(report.instruments.keys.sorted(), id: \.self) { instrument in
                GroupBox(instrument.capitalized + " activity") {
                  plot(
                    report.instruments[instrument] ?? [], title: "Activity",
                    duration: report.duration)
                }
              }
              Text(
                "Model estimates are reference points. Section names describe order, not inferred verse or chorus labels."
              )
              .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
          }
          Divider()
          HStack {
            Button(
              model.playing ? "Pause" : "Play",
              systemImage: model.playing ? "pause.fill" : "play.fill"
            ) {
              if model.playing { model.pause() } else { model.play() }
            }
            Slider(
              value: Binding(get: { model.position }, set: { model.seek($0) }),
              in: 0...report.duration
            ).accessibilityLabel("Playback position")
            Text(MusicFormatting.clock(model.position)).monospacedDigit()
          }.padding()
        } else {
          ContentUnavailableView(
            "Hear the structure", systemImage: "waveform",
            description: Text(
              "Import a local audio file to inspect beats, key changes, sections, and loudness. Audio stays on this device."
            ))
        }
      }.navigationTitle(model.selected?.title ?? "Music Analysis Studio")
        .toolbar {
          if let report = model.selected {
            Button("Export report", systemImage: "square.and.arrow.up") {
              do {
                export = try ReportDocument(report)
                exporting = true
              } catch { model.error = error.localizedDescription }
            }
          }
        }
    }.task { await model.load() }
      .onChange(of: selection) { _, id in
        guard id != model.selected?.id, let report = model.reports.first(where: { $0.id == id })
        else { return }
        model.select(report)
      }
      .onChange(of: model.selected?.id) { _, id in selection = id }
      .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
        switch result {
        case .success(let url): model.analyze(url)
        case .failure(let error): model.error = error.localizedDescription
        }
      }
      .fileExporter(
        isPresented: $exporting, document: export, contentType: .json,
        defaultFilename: "Music analysis"
      ) { result in
        if case .failure(let error) = result { model.error = error.localizedDescription }
        export = nil
      }
      .alert(
        "Couldn't finish",
        isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })
      ) {
        Button("OK") { model.error = nil }
      } message: {
        Text(model.error ?? "")
      }
      .onDisappear {
        model.cancel()
        model.pause()
      }
  }
  private func metric(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      Text(value).font(.title3.weight(.semibold)).monospacedDigit()
    }
  }
  private func plot(_ values: [MetricPoint], title: String, duration: Double) -> some View {
    Group {
      if values.isEmpty {
        Text("No analysis available.").foregroundStyle(.secondary).frame(maxWidth: .infinity)
      } else {
        Chart {
          ForEach(Array(values.enumerated()), id: \.offset) { _, point in
            LineMark(x: .value("Seconds", point.seconds), y: .value(title, point.value))
          }
          RuleMark(x: .value("Playhead", model.position)).foregroundStyle(.secondary)
        }.chartXScale(domain: 0...duration).chartYAxisLabel(title).frame(height: 130)
      }
    }.padding(8)
  }
}
