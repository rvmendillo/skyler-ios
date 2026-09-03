import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: ChartMakerModel
    @State private var showFileImporter = false
    @State private var showDirectoryPicker = false
    @State private var showShare = false
    @State private var selectedDifficulty: ChartDifficulty = .master

    private var audioTypes: [UTType] {
        var values: [UTType] = [.audio, .mpeg4Audio]
        if let mp3 = UTType(filenameExtension: "mp3") { values.append(mp3) }
        return values
    }

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
                            showFileImporter = true
                        } label: {
                            Label("Choose MP3 / M4A / WAV", systemImage: "waveform.badge.plus")
                        }
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
                        .disabled(model.youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Text("Use only audio you have permission to download. YouTube resolution uses public Piped-compatible instances and may need an MP3 fallback if YouTube changes access.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Song") {
                    TextField("Title", text: $model.title)
                    TextField("Artist", text: $model.artist)
                    if let analysis = model.analysis {
                        LabeledContent("Tempo", value: "\(analysis.bpm, specifier: "%.1f") BPM")
                        LabeledContent("Offset", value: "\(analysis.firstBeat, specifier: "%.3f") s")
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

                        Text("Direct copy: choose the AstroDX/levels folder in Files. The app creates a song folder containing maidata.txt and track.mp3.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Status") {
                    HStack {
                        if model.isWorking { ProgressView() }
                        Text(model.status)
                    }
                }
            }
            .navigationTitle("MaiChart Maker")
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: audioTypes,
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    model.importFile(url)
                } else if case .failure(let error) = result {
                    model.errorMessage = error.localizedDescription
                }
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
