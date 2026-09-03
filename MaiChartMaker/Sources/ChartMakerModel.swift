import Foundation
import SwiftUI

@MainActor
final class ChartMakerModel: ObservableObject {
    @Published var source: ImportSource = .file
    @Published var youtubeURL = ""
    @Published var title = ""
    @Published var artist = ""
    @Published var status = "Import audio, MIDI/MusicXML, or paste a YouTube link."
    @Published var isWorking = false
    @Published var analysis: AudioAnalysis?
    @Published var charts: [GeneratedChart] = []
    @Published var audioURL: URL?
    @Published var analysisAudioURL: URL?
    @Published var originalAudioURL: URL?
    @Published var exportZipURL: URL?
    @Published var preparedSongFolder: URL?
    @Published var errorMessage: String?

    @Published var scoreMIDIURL: URL?
    @Published var scoreSourceURL: URL?
    @Published var soundFontURL: URL?
    @Published var soundFontName = ""
    @Published var selectedProgram = 0
    @Published var waveformComparison: WaveformComparison?
    @Published var pianoGameNotes: [PianoGameNote] = []

    private let pianoPreviewEngine = PianoPreviewEngine()

    var hasExactScoreTiming: Bool {
        analysis?.exactScoreTiming == true
    }

    var selectedInstrumentName: String {
        GMInstrument.popular.first(where: { $0.program == selectedProgram })?.name
            ?? "Program \(selectedProgram + 1)"
    }

    func importFile(_ url: URL) {
        Task {
            await perform {
                self.status = "Preparing audio…"
                let imported = try await AudioPipeline.importLocal(url)
                self.audioURL = imported.exportURL
                self.analysisAudioURL = imported.analysisURL
                self.originalAudioURL = imported.originalURL
                self.scoreMIDIURL = nil
                self.scoreSourceURL = nil
                self.pianoGameNotes = []
                if self.title.isEmpty {
                    self.title = url.deletingPathExtension().lastPathComponent
                }
                try await self.analyzeAndGenerate()
            }
        }
    }

    func importScoreFile(_ url: URL) {
        Task {
            await perform {
                self.status = "Reading exact score timing…"
                let result = try ScorePipeline.importScore(url)
                self.analysis = result.analysis
                self.scoreMIDIURL = result.midiURL
                self.scoreSourceURL = result.sourceURL
                self.pianoGameNotes = (try? MIDIPianoGameLoader.load(from: result.midiURL)) ?? []
                self.audioURL = nil
                self.analysisAudioURL = nil
                self.originalAudioURL = nil
                self.exportZipURL = nil
                self.preparedSongFolder = nil
                self.waveformComparison = nil

                if self.title.isEmpty || self.source == .score {
                    self.title = result.suggestedTitle
                }

                self.charts = ChartGenerator.generateAll(analysis: result.analysis)

                let soundName = self.selectedInstrumentName
                self.status = "Exact score loaded • \(self.pianoGameNotes.count) Piano Tiles notes • testing \(soundName). Render MP3 when ready."
            }
        }
    }

    func importSoundFont(_ url: URL) {
        Task {
            await perform {
                self.status = "Loading soundfont…"
                let copied = try SoundFontRenderer.copyBank(url)
                self.soundFontURL = copied
                self.soundFontName = url.lastPathComponent
                self.pianoPreviewEngine.invalidateSoundFont()

                if self.scoreMIDIURL != nil {
                    self.status = "Soundfont loaded • Piano Tiles now tests \(self.selectedInstrumentName). Tap Render when ready."
                } else {
                    self.status = "Soundfont loaded. Import MIDI or MusicXML to test it."
                }
            }
        }
    }

    func previewNoteOn(_ midiNote: UInt8, velocity: UInt8 = 105) {
        do {
            try pianoPreviewEngine.play(
                midiNote: midiNote,
                velocity: velocity,
                soundFontURL: soundFontURL,
                program: selectedProgram
            )
        } catch {
            errorMessage = "Piano preview failed: \(error.localizedDescription)"
        }
    }

    func previewNoteOff(_ midiNote: UInt8) {
        pianoPreviewEngine.stop(
            midiNote: midiNote,
            soundFontURL: soundFontURL
        )
    }

    func stopPreviewNotes() {
        pianoPreviewEngine.stopAll()
    }

    func instrumentSelectionChanged() {
        pianoPreviewEngine.instrumentChanged()
        if scoreMIDIURL != nil {
            status = "Piano Tiles + render instrument: \(selectedInstrumentName)."
        }
    }

    func renderScoreAudio() {
        Task {
            await perform {
                if self.soundFontURL != nil {
                    try await self.renderScoreWithCurrentSoundFont()
                } else {
                    try await self.renderScoreWithDefaultPiano()
                }
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
                self.scoreMIDIURL = nil
                self.scoreSourceURL = nil
                self.pianoGameNotes = []
                self.title = result.title
                self.artist = result.artist
                try await self.analyzeAndGenerate()
            }
        }
    }

    func regenerate() {
        guard let analysis else { return }
        charts = ChartGenerator.generateAll(analysis: analysis)
        status = analysis.exactScoreTiming
            ? "Remixed \(charts.count) charts on the exact score grid."
            : "Remixed \(charts.count) audio-derived charts."
        if audioURL != nil { prepareExport() }
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
        guard let analysis, !charts.isEmpty else { return }
        guard let audioURL else {
            errorMessage = "The chart timing is ready, but AstroDX also needs track audio. Load an SF2/DLS soundfont and render the score first."
            return
        }

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

    private func renderScoreWithDefaultPiano() async throws {
        guard let midiURL = scoreMIDIURL else {
            throw NSError(
                domain: "MaiChartMaker",
                code: 43,
                userInfo: [NSLocalizedDescriptionKey: "Import MIDI or MusicXML first."]
            )
        }

        let program = selectedProgram
        let instrumentName = selectedInstrumentName

        status = "Rendering \(instrumentName) to lossless WAV…"
        let wav = try await Task.detached(priority: .userInitiated) {
            try DefaultMIDIRenderer.renderBuiltInWAV(
                midiURL: midiURL,
                program: program
            )
        }.value

        status = "Encoding native 320 kbps MP3…"
        let mp3 = try await AudioPipeline.transcodeToMP3(wav)

        status = "Comparing WAV and decoded MP3 waveforms…"
        let comparison = try? await WaveformQualityChecker.compare(
            referenceWAV: wav,
            encodedMP3: mp3
        )

        self.analysisAudioURL = wav
        self.originalAudioURL = wav
        self.audioURL = mp3
        self.waveformComparison = comparison
        self.status = comparison.map {
            "Exact score • \(instrumentName) • native MP3 ready • \($0.summary)"
        } ?? "Exact score • \(instrumentName) • native 320 kbps MP3 ready."
        prepareExport()
    }

    private func renderScoreWithCurrentSoundFont() async throws {
        guard let midiURL = scoreMIDIURL else {
            throw NSError(
                domain: "MaiChartMaker",
                code: 41,
                userInfo: [NSLocalizedDescriptionKey: "Import MIDI or MusicXML first."]
            )
        }
        guard let soundFontURL else {
            throw NSError(
                domain: "MaiChartMaker",
                code: 42,
                userInfo: [NSLocalizedDescriptionKey: "Load an SF2 or DLS soundfont first."]
            )
        }

        let program = selectedProgram
        let instrumentName = selectedInstrumentName

        status = "Rendering \(instrumentName) to lossless WAV…"
        let wav = try await SoundFontRenderer.renderWAV(
            midiURL: midiURL,
            bankURL: soundFontURL,
            program: program
        )

        status = "Encoding native 320 kbps MP3…"
        let mp3 = try await AudioPipeline.transcodeToMP3(wav)

        status = "Comparing WAV and decoded MP3 waveforms…"
        let comparison = try? await WaveformQualityChecker.compare(
            referenceWAV: wav,
            encodedMP3: mp3
        )

        self.analysisAudioURL = wav
        self.originalAudioURL = wav
        self.audioURL = mp3
        self.waveformComparison = comparison
        self.status = comparison.map {
            "Exact score • \(instrumentName) • native MP3 ready • \($0.summary)"
        } ?? "Exact score • \(instrumentName) • native 320 kbps MP3 ready."
        prepareExport()
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
