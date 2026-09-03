import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: ChartMakerModel
    @State private var showAudioPicker = false
    @State private var showScorePicker = false
    @State private var showSoundFontPicker = false
    @State private var showDirectoryPicker = false
    @State private var showShare = false
    @State private var selectedDifficulty: ChartDifficulty = .master

    var body: some View {
        NavigationStack {
            ZStack {
                ArcadeBackground()

                ScrollView {
                    LazyVStack(spacing: 16) {
                        header
                        sourceCard

                        if model.audioURL != nil || model.analysis != nil {
                            songCard
                        }

                        if model.scoreMIDIURL != nil || !model.pianoGameNotes.isEmpty {
                            soundFontCard
                        }

                        if !model.charts.isEmpty {
                            chartCard
                            exportCard
                        }

                        statusCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAudioPicker) {
                AudioDocumentPicker(
                    onPick: { url in
                        showAudioPicker = false
                        model.importFile(url)
                    },
                    onCancel: { showAudioPicker = false }
                )
            }
            .sheet(isPresented: $showScorePicker) {
                AudioDocumentPicker(
                    onPick: { url in
                        showScorePicker = false
                        model.importScoreFile(url)
                    },
                    onCancel: { showScorePicker = false }
                )
            }
            .sheet(isPresented: $showSoundFontPicker) {
                AudioDocumentPicker(
                    onPick: { url in
                        showSoundFontPicker = false
                        model.importSoundFont(url)
                    },
                    onCancel: { showSoundFontPicker = false }
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
        .tint(ArcadePalette.purple)
    }

    private var header: some View {
        HStack(spacing: 14) {
            RingLogo()

            VStack(alignment: .leading, spacing: 3) {
                Text("MaiChart Maker")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(ArcadePalette.ink)

                Text("CREATE • FEEL • CHART")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [ArcadePalette.cyan, ArcadePalette.purple, ArcadePalette.pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }

            Spacer()
        }
        .padding(.top, 14)
    }

    private var sourceCard: some View {
        ArcadeCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("IMPORT MUSIC", icon: "waveform")

                HStack(spacing: 7) {
                    sourceSelector(.file, icon: "waveform", subtitle: "Audio")
                    sourceSelector(.score, icon: "music.note.list", subtitle: "Score")
                    sourceSelector(.youtube, icon: "play.rectangle.fill", subtitle: "YouTube")
                }

                switch model.source {
                case .file:
                    Button {
                        showAudioPicker = true
                    } label: {
                        Label("Choose Audio File", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(ArcadePrimaryButtonStyle(colors: [ArcadePalette.cyan, ArcadePalette.purple]))

                    Label("MP3, M4A, WAV and other iOS-readable audio", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .score:
                    Button {
                        showScorePicker = true
                    } label: {
                        Label("Choose MIDI / MusicXML / PDF", systemImage: "music.note.list")
                    }
                    .buttonStyle(ArcadePrimaryButtonStyle(colors: [ArcadePalette.aqua, ArcadePalette.purple]))

                    VStack(alignment: .leading, spacing: 5) {
                        Label("MIDI + MusicXML use exact note beats and tempo changes.", systemImage: "metronome.fill")
                        Label("MusicXML: .musicxml, .xml, .mxl", systemImage: "doc.text.fill")
                        Label("PDF needs OMR to MusicXML first; SmartScore/Audiveris output can be imported here.", systemImage: "doc.viewfinder")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                case .youtube:
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "link")
                                .foregroundStyle(ArcadePalette.red)

                            TextField("Paste YouTube link", text: $model.youtubeURL)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                                .font(.system(.body, design: .rounded))
                        }
                        .padding(13)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(ArcadePalette.red.opacity(0.25), lineWidth: 1)
                        )

                        Button {
                            model.importYouTube()
                        } label: {
                            Label("Import YouTube Audio", systemImage: "sparkles")
                        }
                        .buttonStyle(ArcadePrimaryButtonStyle(colors: [ArcadePalette.red, ArcadePalette.pink]))
                        .disabled(model.youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isWorking)
                    }
                }
            }
        }
    }

    private var songCard: some View {
        ArcadeCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("SONG ANALYSIS", icon: "music.quarternote.3")

                VStack(spacing: 10) {
                    styledTextField("Song title", text: $model.title, icon: "music.note")
                    styledTextField("Artist", text: $model.artist, icon: "person.wave.2.fill")
                }

                if let analysis = model.analysis {
                    HStack(spacing: 8) {
                        metric("BPM", String(format: "%.1f", analysis.bpm), ArcadePalette.pink)
                        metric("OFFSET", String(format: "%.3fs", analysis.firstBeat), ArcadePalette.cyan)
                        metric(model.hasExactScoreTiming ? "NOTES" : "ONSETS", "\(analysis.onsets.count)", ArcadePalette.aqua)
                    }
                }
            }
        }
    }

    private var soundFontCard: some View {
        ArcadeCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    sectionTitle("SOUNDFONT STUDIO", icon: "pianokeys")
                    Spacer()
                    Text("SF2 / DLS")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(ArcadePalette.purple)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(ArcadePalette.purple.opacity(0.10), in: Capsule())
                }

                if model.soundFontURL == nil {
                    HStack(spacing: 10) {
                        Image(systemName: "pianokeys")
                            .foregroundStyle(ArcadePalette.aqua)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.selectedInstrumentName)
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                            Text("Apple Sampler • GeneralUser GS built in")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    Button {
                        showSoundFontPicker = true
                    } label: {
                        Label("Load Optional SoundFont Bank", systemImage: "externaldrive.badge.plus")
                    }
                    .buttonStyle(ArcadePrimaryButtonStyle(colors: [ArcadePalette.pink, ArcadePalette.purple]))
                } else {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(ArcadePalette.aqua)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.soundFontName)
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .lineLimit(1)
                            Text("Loaded instrument bank")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Change") {
                            showSoundFontPicker = true
                        }
                        .font(.caption.bold())
                    }
                }

                Picker("Instrument", selection: $model.selectedProgram) {
                    ForEach(GMInstrument.popular) { instrument in
                        Text("\(instrument.program + 1) • \(instrument.name)")
                            .tag(instrument.program)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: model.selectedProgram) { _ in
                    model.instrumentSelectionChanged()
                }

                VStack(alignment: .leading, spacing: 10) {
                    MIDIPianoTilesGameView(
                        notes: model.pianoGameNotes,
                        onPlayNote: { midi, velocity in
                            model.previewNoteOn(midi, velocity: velocity)
                        },
                        onStopNote: { midi in
                            model.previewNoteOff(midi)
                        },
                        onStopAll: {
                            model.stopPreviewNotes()
                        }
                    )

                    Label(
                        "Game uses \(model.selectedInstrumentName)",
                        systemImage: model.soundFontURL == nil ? "waveform" : "externaldrive.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(
                    LinearGradient(
                        colors: [
                            ArcadePalette.cyan.opacity(0.08),
                            ArcadePalette.purple.opacity(0.07)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(ArcadePalette.purple.opacity(0.12), lineWidth: 1)
                )

                if model.scoreMIDIURL != nil {
                    Button {
                        model.renderScoreAudio()
                    } label: {
                        Label(
                            "Render \(model.selectedInstrumentName) MP3",
                            systemImage: "waveform.badge.plus"
                        )
                    }
                    .buttonStyle(ArcadePrimaryButtonStyle(colors: [ArcadePalette.cyan, ArcadePalette.purple]))
                    .disabled(model.isWorking)
                }

                if let comparison = model.waveformComparison {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("ENCODE QUALITY CHECK", systemImage: "waveform.path.ecg")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(ArcadePalette.aqua)

                        Text(comparison.summary)
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(ArcadePalette.ink)

                        Text("Compared by decoding the final MP3 back to PCM and measuring it against the lossless WAV reference.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(
                        ArcadePalette.aqua.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }

                Text(model.scoreMIDIURL == nil
                     ? "MP3/M4A are transcribed on-device with Basic Pitch CoreML. Piano Tiles uses the selected Apple Sampler instrument, while chart generation combines percussive rhythm anchors with melody motion."
                     : "MIDI/MusicXML render through Apple AVAudioUnitSampler with the bundled GeneralUser GS bank, then LAME creates a 320 kbps MP3. The WAV remains an internal render reference and is not included in AstroDX export.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var chartCard: some View {
        ArcadeCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    sectionTitle("CHART WORKSHOP", icon: "circle.grid.cross.fill")
                    Spacer()
                    Text("HUMANIZED")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(ArcadePalette.pink)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(ArcadePalette.pink.opacity(0.10), in: Capsule())
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(ChartDifficulty.allCases) { difficulty in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                    selectedDifficulty = difficulty
                                }
                            } label: {
                                DifficultyBadge(
                                    difficulty: difficulty,
                                    selected: selectedDifficulty == difficulty
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let chart = model.charts.first(where: { $0.difficulty == selectedDifficulty }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedDifficulty.name)
                                .font(.system(.headline, design: .rounded, weight: .black))
                                .foregroundStyle(ArcadePalette.difficulty(selectedDifficulty))
                            Text("Hierarchical chart family • drum rhythm + melody motion")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        TextField(
                            "Level",
                            text: Binding(
                                get: { chart.level },
                                set: { model.updateLevel(id: chart.id, level: $0) }
                            )
                        )
                        .multilineTextAlignment(.center)
                        .font(.system(.headline, design: .rounded, weight: .black))
                        .frame(width: 62)
                        .padding(.vertical, 9)
                        .background(
                            ArcadePalette.difficulty(selectedDifficulty).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                    }

                    MaimaiPlaytestView(
                        noteText: chart.noteText,
                        bpm: model.analysis?.bpm ?? 120,
                        firstBeat: model.analysis?.firstBeat ?? 0,
                        audioURL: model.audioURL,
                        difficulty: selectedDifficulty
                    )
                    .padding(12)
                    .background(
                        Color.white.opacity(0.72),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                ArcadePalette.difficulty(selectedDifficulty).opacity(0.16),
                                lineWidth: 1
                            )
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(
                                "AUDIO / CHART SYNC",
                                systemImage: "metronome.fill"
                            )
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .foregroundStyle(ArcadePalette.aqua)

                            Spacer()

                            Text(
                                String(
                                    format: "%+.0f ms",
                                    model.syncOffsetMilliseconds
                                )
                            )
                            .font(.system(.caption, design: .rounded, weight: .black))
                            .foregroundStyle(
                                abs(model.syncOffsetMilliseconds) < 0.5
                                    ? .secondary
                                    : ArcadePalette.pink
                            )
                        }

                        HStack(spacing: 6) {
                            Button("−50") {
                                model.adjustSyncOffset(by: -50)
                            }
                            .buttonStyle(.bordered)

                            Button("−10") {
                                model.adjustSyncOffset(by: -10)
                            }
                            .buttonStyle(.bordered)

                            Button("Reset") {
                                model.resetSyncOffset()
                            }
                            .buttonStyle(.bordered)

                            Button("+10") {
                                model.adjustSyncOffset(by: 10)
                            }
                            .buttonStyle(.bordered)

                            Button("+50") {
                                model.adjustSyncOffset(by: 50)
                            }
                            .buttonStyle(.bordered)
                        }
                        .font(.caption.bold())

                        Text("Auto alignment is estimated from the full-song beat phase. Use these controls only if the hit ring still lands early or late; the same offset is written to AstroDX export.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(
                        ArcadePalette.aqua.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )

                    TextEditor(
                        text: Binding(
                            get: { model.charts.first(where: { $0.id == chart.id })?.noteText ?? "" },
                            set: { model.updateChart(id: chart.id, text: $0) }
                        )
                    )
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 230)
                    .background(Color(red: 0.975, green: 0.98, blue: 1.0))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(ArcadePalette.difficulty(selectedDifficulty).opacity(0.22), lineWidth: 1)
                    )

                    Button {
                        model.regenerate()
                    } label: {
                        Label("Remix All Charts", systemImage: "shuffle")
                    }
                    .buttonStyle(ArcadePrimaryButtonStyle(colors: [ArcadePalette.aqua, ArcadePalette.purple]))
                }
            }
        }
    }

    private var exportCard: some View {
        ArcadeCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("EXPORT TO ASTRODX", icon: "arrow.down.doc.fill")

                Button {
                    model.prepareExport()
                    showDirectoryPicker = true
                } label: {
                    Label("Copy to AstroDX / levels", systemImage: "folder.badge.plus")
                }
                .buttonStyle(ArcadePrimaryButtonStyle(colors: [ArcadePalette.yellow, ArcadePalette.pink]))

                if model.exportZipURL != nil {
                    Button {
                        model.prepareExport()
                        showShare = true
                    } label: {
                        Label("Share Chart ZIP", systemImage: "square.and.arrow.up")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 16))
                }

                Label("Exports maidata.txt + AstroDX-compatible track audio", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusCard: some View {
        ArcadeCard {
            HStack(spacing: 12) {
                if model.isWorking {
                    ProgressView()
                        .tint(ArcadePalette.purple)
                } else {
                    Image(systemName: model.analysis == nil ? "sparkles" : "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(model.analysis == nil ? ArcadePalette.pink : ArcadePalette.aqua)
                }

                Text(model.status)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(ArcadePalette.ink.opacity(0.78))
                    .textSelection(.enabled)

                Spacer()
            }
        }
    }

    private func sectionTitle(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 13, weight: .black, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(ArcadePalette.ink)
    }

    private func sourceSelector(_ source: ImportSource, icon: String, subtitle: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                model.source = source
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.headline)
                Text(subtitle)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
            }
            .foregroundStyle(model.source == source ? .white : ArcadePalette.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Group {
                    if model.source == source {
                        LinearGradient(
                            colors: sourceGradient(source),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else {
                        LinearGradient(colors: [Color.white, Color.white], startPoint: .leading, endPoint: .trailing)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(model.source == source ? 0 : 0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func styledTextField(_ placeholder: String, text: Binding<String>, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(ArcadePalette.purple)
            TextField(placeholder, text: text)
                .font(.system(.body, design: .rounded))
        }
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private func sourceGradient(_ source: ImportSource) -> [Color] {
        switch source {
        case .file: return [ArcadePalette.cyan, ArcadePalette.purple]
        case .score: return [ArcadePalette.aqua, ArcadePalette.purple]
        case .youtube: return [ArcadePalette.red, ArcadePalette.pink]
        }
    }

    private func metric(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .black))
                .foregroundStyle(ArcadePalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
