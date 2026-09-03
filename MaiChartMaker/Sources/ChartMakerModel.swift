import Foundation
import SwiftUI

@MainActor
final class ChartMakerModel: ObservableObject {
    @Published var source: ImportSource = .file
    @Published var youtubeURL = ""
    @Published var title = ""
    @Published var artist = ""
    @Published var status = "Import an MP3/M4A/WAV or paste a YouTube link."
    @Published var isWorking = false
    @Published var analysis: AudioAnalysis?
    @Published var charts: [GeneratedChart] = []
    @Published var audioURL: URL?
    @Published var analysisAudioURL: URL?
    @Published var originalAudioURL: URL?
    @Published var exportZipURL: URL?
    @Published var preparedSongFolder: URL?
    @Published var errorMessage: String?

    func importFile(_ url: URL) {
        Task {
            await perform {
                self.status = "Preparing audio…"
                let imported = try await AudioPipeline.importLocal(url)
                self.audioURL = imported.exportURL
                self.analysisAudioURL = imported.analysisURL
                self.originalAudioURL = imported.originalURL
                if self.title.isEmpty {
                    self.title = url.deletingPathExtension().lastPathComponent
                }
                try await self.analyzeAndGenerate()
            }
        }
    }

    func importYouTube() {
        Task {
            await perform {
                self.status = "Resolving YouTube audio…"
                let result = try await AudioPipeline.importYouTube(self.youtubeURL)
                self.audioURL = result.exportURL
                self.analysisAudioURL = result.analysisURL
                self.originalAudioURL = result.originalURL
                self.title = result.title
                self.artist = result.artist
                try await self.analyzeAndGenerate()
            }
        }
    }

    func regenerate() {
        guard let analysis else { return }
        charts = ChartGenerator.generateAll(analysis: analysis)
        status = "Generated \(charts.count) difficulties."
        prepareExport()
    }

    func updateChart(id: Int, text: String) {
        guard let index = charts.firstIndex(where: { $0.id == id }) else { return }
        charts[index].noteText = text
    }

    func updateLevel(id: Int, level: String) {
        guard let index = charts.firstIndex(where: { $0.id == id }) else { return }
        charts[index].level = level
    }

    func prepareExport() {
        guard let audioURL, let analysis, !charts.isEmpty else { return }
        do {
            let folder = try ChartExporter.makeSongFolder(
                title: title,
                artist: artist,
                audioURL: audioURL,
                analysis: analysis,
                charts: charts,
                originalAudioURL: originalAudioURL
            )
            preparedSongFolder = folder
            exportZipURL = try ChartExporter.makeZip(from: folder)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copyPreparedFolder(to destination: URL) {
        guard let folder = preparedSongFolder else { return }
        do {
            let target = try ChartExporter.copySongFolder(folder, into: destination)
            status = "Copied to \(target.lastPathComponent). AstroDX can load it from levels."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func analyzeAndGenerate() async throws {
        guard let source = analysisAudioURL ?? audioURL else { return }
        status = "Detecting tempo, beats and onsets from original audio…"
        let analysis = try await AudioPipeline.analyze(source)
        self.analysis = analysis
        self.charts = ChartGenerator.generateAll(analysis: analysis)
        status = "Detected \(String(format: "%.1f", analysis.bpm)) BPM • generated \(charts.count) charts."
        prepareExport()
    }

    private func perform(_ operation: @escaping () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
            status = "Could not complete the import."
        }
        isWorking = false
    }
}
