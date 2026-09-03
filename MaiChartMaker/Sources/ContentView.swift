import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: ChartMakerModel
    @State private var showAudioPicker = false
    @State private var showDirectoryPicker = false
    @State private var showShare = false
    @State private var selectedDifficulty: ChartDifficulty = .master

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    Picker("Import", selection: $model.source) {
                        ForEach(ImportSource.allCases) { source in
                            Text(source.rawValue).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)

                    if model.source == .file {
                        Button {
                            showAudioPicker = true
                        } label: {
                            Label("Choose Audio File", systemImage: "waveform.badge.plus")
                        }

                        Text("The picker intentionally shows all files so MP3/M4A/WAV files from iCloud, Downloads, and third-party Files providers stay tappable. Non-audio files will be rejected after selection.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        TextField("https://youtube.com/watch?v=…", text: $model.youtubeURL)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()

                        Button {
                            model.importYouTube()
                        } label: {
                            Label("Import YouTube Audio", systemImage: "link")
                        }
                        .disabled(model.youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isWorking)

                        Text("YouTube import now tries multiple current Invidious playback endpoints first, then Piped-compatible fallbacks. Only import audio you have permission to use.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Song") {
                    TextField("Title", text: $model.title)
                    TextField("Artist", text: $model.artist)

                    if let analysis = model.analysis {
                        LabeledContent("Tempo", value: String(format: "%.1f BPM", analysis.bpm))
                        LabeledContent("Offset", value: String(format: "%.3f s", analysis.firstBeat))
                        LabeledContent("Onsets", value: "\(analysis.onsets.count)")
                        LabeledContent("Duration", value: durationString(analysis.duration))
                    }
                }

                if !model.charts.isEmpty {
                    Section("Charts") {
                        Picker("Difficulty", selection: $selectedDifficulty) {
                            ForEach(ChartDifficulty.allCases) { diff in
                                Text(diff.name).tag(diff)
                            }
                        }

                        if let chart = model.charts.first(where: { $0.difficulty == selectedDifficulty }) {
                            TextField(
                                "Level",
                                text: Binding(
                                    get: { chart.level },
                                    set: { model.updateLevel(id: chart.id, level: $0) }
                                )
                            )

                            TextEditor(
                                text: Binding(
                                    get: { model.charts.first(where: { $0.id == chart.id })?.noteText ?? "" },
                                    set: { model.updateChart(id: chart.id, text: $0) }
                                )
                            )
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 220)

                            Button("Regenerate All Difficulties") {
                                model.regenerate()
                            }
                        }
                    }

                    Section("Export to AstroDX") {
                        Button {
                            model.prepareExport()
                            showDirectoryPicker = true
                        } label: {
                            Label("Copy Song Folder to AstroDX/levels", systemImage: "folder.badge.plus")
                        }

                        if model.exportZipURL != nil {
                            Button {
                                model.prepareExport()
                                showShare = true
                            } label: {
                                Label("Share ZIP", systemImage: "square.and.arrow.up")
                            }
                        }

                        Text("Choose AstroDX/levels in Files. The app creates a song folder containing maidata.txt and track.mp3.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Status") {
                    HStack(alignment: .top) {
                        if model.isWorking { ProgressView() }
                        Text(model.status)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("MaiChart Maker")
            .sheet(isPresented: $showAudioPicker) {
                AudioDocumentPicker(
                    onPick: { url in
                        showAudioPicker = false
                        model.importFile(url)
                    },
                    onCancel: {
                        showAudioPicker = false
                    }
                )
            }
            .sheet(isPresented: $showDirectoryPicker) {
                DirectoryPicker { url in
                    model.prepareExport()
                    model.copyPreparedFolder(to: url)
                    showDirectoryPicker = false
                }
            }
            .sheet(isPresented: $showShare) {
                if let url = model.exportZipURL {
                    ShareSheet(items: [url])
                }
            }
            .alert("MaiChart Maker", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private func durationString(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
