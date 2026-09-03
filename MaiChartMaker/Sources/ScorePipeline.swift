import Foundation
import AudioToolbox
import ZIPFoundation

enum ScorePipelineError: LocalizedError {
    case unsupported
    case invalidMIDI(OSStatus)
    case emptyScore
    case malformedMusicXML
    case pdfRequiresOMR

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "Use MIDI (.mid/.midi), MusicXML (.musicxml/.xml/.mxl), or a PDF for OMR."
        case .invalidMIDI(let status):
            return "The MIDI file could not be parsed (AudioToolbox status \(status))."
        case .emptyScore:
            return "No playable notes were found in the score."
        case .malformedMusicXML:
            return "The MusicXML file could not be parsed."
        case .pdfRequiresOMR:
            return "PDF notation needs optical music recognition first. Export it to MusicXML with Audiveris/SmartScore, then import the MusicXML here."
        }
    }
}

struct ScoreImportResult: Sendable {
    let analysis: AudioAnalysis
    let midiURL: URL
    let sourceURL: URL
    let suggestedTitle: String
}

enum ScorePipeline {
    static func importScore(_ source: URL) throws -> ScoreImportResult {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }

        let ext = source.pathExtension.lowercased()
        let copied = try copyToTemporary(source)

        switch ext {
        case "mid", "midi":
            let analysis = try analyzeMIDI(copied)
            return ScoreImportResult(
                analysis: analysis,
                midiURL: copied,
                sourceURL: copied,
                suggestedTitle: source.deletingPathExtension().lastPathComponent
            )

        case "musicxml", "xml", "mxl":
            let xmlURL = try musicXMLURL(from: copied)
            let score = try MusicXMLReader.read(xmlURL)
            guard !score.notes.isEmpty else { throw ScorePipelineError.emptyScore }
            let midiURL = try MIDIWriter.write(score: score)
            let analysis = analysisFromScore(score)
            return ScoreImportResult(
                analysis: analysis,
                midiURL: midiURL,
                sourceURL: copied,
                suggestedTitle: score.title ?? source.deletingPathExtension().lastPathComponent
            )

        case "pdf":
            throw ScorePipelineError.pdfRequiresOMR

        default:
            throw ScorePipelineError.unsupported
        }
    }

    private static func copyToTemporary(_ source: URL) throws -> URL {
        let ext = source.pathExtension
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("score-\(UUID().uuidString)")
            .appendingPathExtension(ext)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: source, to: target)
        return target
    }

    private static func musicXMLURL(from source: URL) throws -> URL {
        guard source.pathExtension.lowercased() == "mxl" else { return source }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("mxl-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.unzipItem(at: source, to: folder)

        let files = try FileManager.default.subpathsOfDirectory(atPath: folder.path)
        if let relative = files.first(where: {
            let lower = $0.lowercased()
            return !lower.contains("meta-inf") && (lower.hasSuffix(".musicxml") || lower.hasSuffix(".xml"))
        }) {
            return folder.appendingPathComponent(relative)
        }
        throw ScorePipelineError.malformedMusicXML
    }

    private static func analyzeMIDI(_ url: URL) throws -> AudioAnalysis {
        var sequence: MusicSequence?
        let createStatus = NewMusicSequence(&sequence)
        guard createStatus == noErr, let sequence else {
            throw ScorePipelineError.invalidMIDI(createStatus)
        }
        defer { DisposeMusicSequence(sequence) }

        let loadStatus = MusicSequenceFileLoad(
            sequence,
            url as CFURL,
            .midiType,
            .smf_ChannelsToTracks
        )
        guard loadStatus == noErr else {
            throw ScorePipelineError.invalidMIDI(loadStatus)
        }

        var notesByBeat: [Int64: (beat: Double, velocity: Double, count: Int)] = [:]
        var maxBeat = 0.0

        var trackCount: UInt32 = 0
        MusicSequenceGetTrackCount(sequence, &trackCount)

        for index in 0..<trackCount {
            var track: MusicTrack?
            guard MusicSequenceGetIndTrack(sequence, index, &track) == noErr, let track else { continue }

            var iterator: MusicEventIterator?
            guard NewMusicEventIterator(track, &iterator) == noErr, let iterator else { continue }
            defer { DisposeMusicEventIterator(iterator) }

            var hasEvent = DarwinBoolean(false)
            MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)

            while hasEvent.boolValue {
                var time: MusicTimeStamp = 0
                var type: MusicEventType = 0
                var data: UnsafeRawPointer?
                var size: UInt32 = 0

                if MusicEventIteratorGetEventInfo(iterator, &time, &type, &data, &size) == noErr,
                   type == kMusicEventType_MIDINoteMessage,
                   let data {
                    let note = data.load(as: MIDINoteMessage.self)
                    let beat = Double(time)
                    let endBeat = beat + Double(note.duration)
                    maxBeat = max(maxBeat, endBeat)

                    let key = Int64((beat * 1_000_000).rounded())
                    let velocity = Double(note.velocity) / 127.0
                    if var existing = notesByBeat[key] {
                        existing.velocity = max(existing.velocity, velocity)
                        existing.count += 1
                        notesByBeat[key] = existing
                    } else {
                        notesByBeat[key] = (beat, velocity, 1)
                    }
                }

                MusicEventIteratorNextEvent(iterator)
                MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)
            }
        }

        guard !notesByBeat.isEmpty else { throw ScorePipelineError.emptyScore }

        var tempoPoints: [TempoPoint] = []
        var tempoTrack: MusicTrack?
        if MusicSequenceGetTempoTrack(sequence, &tempoTrack) == noErr, let tempoTrack {
            var iterator: MusicEventIterator?
            if NewMusicEventIterator(tempoTrack, &iterator) == noErr, let iterator {
                defer { DisposeMusicEventIterator(iterator) }
                var hasEvent = DarwinBoolean(false)
                MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)

                while hasEvent.boolValue {
                    var time: MusicTimeStamp = 0
                    var type: MusicEventType = 0
                    var data: UnsafeRawPointer?
                    var size: UInt32 = 0
                    if MusicEventIteratorGetEventInfo(iterator, &time, &type, &data, &size) == noErr,
                       type == kMusicEventType_ExtendedTempo,
                       let data {
                        let tempo = data.load(as: ExtendedTempoEvent.self)
                        tempoPoints.append(TempoPoint(beat: Double(time), bpm: tempo.bpm))
                    }
                    MusicEventIteratorNextEvent(iterator)
                    MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)
                }
            }
        }

        if tempoPoints.isEmpty {
            tempoPoints = [TempoPoint(beat: 0, bpm: 120)]
        }
        tempoPoints = normalizedTempoMap(tempoPoints)

        let sorted = notesByBeat.values.sorted { $0.beat < $1.beat }
        var onsetSeconds: [Double] = []
        for item in sorted {
            var seconds: Float64 = 0
            MusicSequenceGetSecondsForBeats(sequence, item.beat, &seconds)
            onsetSeconds.append(seconds)
        }

        var durationSeconds: Float64 = 0
        MusicSequenceGetSecondsForBeats(sequence, maxBeat, &durationSeconds)

        return AudioAnalysis(
            duration: max(0.1, durationSeconds),
            bpm: tempoPoints.first?.bpm ?? 120,
            firstBeat: 0,
            onsets: onsetSeconds,
            strengths: sorted.map { min(1, $0.velocity + Double(max(0, $0.count - 1)) * 0.08) },
            beatPositions: sorted.map(\.beat),
            durationBeats: maxBeat,
            tempoMap: tempoPoints,
            exactScoreTiming: true
        )
    }

    private static func analysisFromScore(_ score: ParsedScore) -> AudioAnalysis {
        var byBeat: [Int64: (beat: Double, strength: Double, count: Int)] = [:]
        var maxBeat = 0.0

        for note in score.notes {
            maxBeat = max(maxBeat, note.beat + note.duration)
            let key = Int64((note.beat * 1_000_000).rounded())
            let base = Double(note.velocity) / 127.0
            if var existing = byBeat[key] {
                existing.strength = max(existing.strength, base)
                existing.count += 1
                byBeat[key] = existing
            } else {
                byBeat[key] = (note.beat, base, 1)
            }
        }

        let tempo = normalizedTempoMap(score.tempos.isEmpty ? [TempoPoint(beat: 0, bpm: 120)] : score.tempos)
        let sorted = byBeat.values.sorted { $0.beat < $1.beat }
        let seconds = sorted.map { secondsForBeat($0.beat, tempo: tempo) }
        let duration = secondsForBeat(maxBeat, tempo: tempo)

        return AudioAnalysis(
            duration: max(0.1, duration),
            bpm: tempo.first?.bpm ?? 120,
            firstBeat: 0,
            onsets: seconds,
            strengths: sorted.map { min(1, $0.strength + Double(max(0, $0.count - 1)) * 0.08) },
            beatPositions: sorted.map(\.beat),
            durationBeats: maxBeat,
            tempoMap: tempo,
            exactScoreTiming: true
        )
    }

    static func normalizedTempoMap(_ input: [TempoPoint]) -> [TempoPoint] {
        let sorted = input
            .filter { $0.bpm > 1 && $0.beat >= 0 }
            .sorted { $0.beat < $1.beat }

        var output: [TempoPoint] = []
        for item in sorted {
            if let last = output.last, abs(last.beat - item.beat) < 0.000001 {
                output[output.count - 1] = item
            } else {
                output.append(item)
            }
        }
        if output.first?.beat ?? 1 > 0 {
            output.insert(TempoPoint(beat: 0, bpm: output.first?.bpm ?? 120), at: 0)
        }
        return output.isEmpty ? [TempoPoint(beat: 0, bpm: 120)] : output
    }

    static func secondsForBeat(_ beat: Double, tempo: [TempoPoint]) -> Double {
        let map = normalizedTempoMap(tempo)
        var seconds = 0.0
        var lastBeat = 0.0
        var bpm = map.first?.bpm ?? 120

        for point in map.dropFirst() {
            if point.beat >= beat { break }
            seconds += max(0, point.beat - lastBeat) * 60.0 / bpm
            lastBeat = point.beat
            bpm = point.bpm
        }

        seconds += max(0, beat - lastBeat) * 60.0 / bpm
        return seconds
    }
}

struct ParsedNote: Sendable {
    let beat: Double
    let duration: Double
    let midiNote: UInt8
    let velocity: UInt8
}

struct ParsedScore: Sendable {
    let title: String?
    let notes: [ParsedNote]
    let tempos: [TempoPoint]
}

private final class MusicXMLReader: NSObject, XMLParserDelegate {
    private var notes: [ParsedNote] = []
    private var tempos: [TempoPoint] = []
    private var title: String?

    private var currentText = ""
    private var currentPartID = ""
    private var partCursor = 0.0
    private var measureStart = 0.0
    private var measureMax = 0.0
    private var divisions = 1.0
    private var lastNoteStart = 0.0

    private var inNote = false
    private var inBackup = false
    private var inForward = false
    private var noteRest = false
    private var noteChord = false
    private var noteTieStop = false
    private var noteDurationDivisions = 0.0
    private var step = "C"
    private var alter = 0
    private var octave = 4
    private var pendingTempo: Double?

    static func read(_ url: URL) throws -> ParsedScore {
        guard let parser = XMLParser(contentsOf: url) else {
            throw ScorePipelineError.malformedMusicXML
        }
        let reader = MusicXMLReader()
        parser.delegate = reader
        guard parser.parse() else {
            throw parser.parserError ?? ScorePipelineError.malformedMusicXML
        }
        return ParsedScore(
            title: reader.title,
            notes: reader.notes.sorted { $0.beat < $1.beat },
            tempos: ScorePipeline.normalizedTempoMap(reader.tempos)
        )
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentText = ""

        switch elementName {
        case "part":
            currentPartID = attributeDict["id"] ?? ""
            partCursor = 0
            measureStart = 0
            measureMax = 0
            divisions = 1

        case "measure":
            measureStart = partCursor
            measureMax = partCursor

        case "note":
            inNote = true
            noteRest = false
            noteChord = false
            noteTieStop = false
            noteDurationDivisions = 0
            step = "C"
            alter = 0
            octave = 4

        case "rest":
            if inNote { noteRest = true }

        case "chord":
            if inNote { noteChord = true }

        case "tie":
            if inNote, attributeDict["type"] == "stop" {
                noteTieStop = true
            }

        case "backup":
            inBackup = true

        case "forward":
            inForward = true

        case "sound":
            if let raw = attributeDict["tempo"], let bpm = Double(raw) {
                tempos.append(TempoPoint(beat: partCursor, bpm: bpm))
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "work-title", "movement-title":
            if title == nil, !text.isEmpty { title = text }

        case "divisions":
            if let value = Double(text), value > 0 { divisions = value }

        case "step":
            if inNote, !text.isEmpty { step = text }

        case "alter":
            if inNote { alter = Int(Double(text) ?? 0) }

        case "octave":
            if inNote { octave = Int(text) ?? 4 }

        case "duration":
            let value = Double(text) ?? 0
            if inNote {
                noteDurationDivisions = value
            } else if inBackup {
                partCursor -= value / divisions
            } else if inForward {
                partCursor += value / divisions
                measureMax = max(measureMax, partCursor)
            }

        case "per-minute":
            if let bpm = Double(text) {
                pendingTempo = bpm
            }

        case "direction":
            if let bpm = pendingTempo {
                tempos.append(TempoPoint(beat: partCursor, bpm: bpm))
                pendingTempo = nil
            }

        case "note":
            let durationBeats = noteDurationDivisions / divisions
            let startBeat = noteChord ? lastNoteStart : partCursor

            if !noteRest, !noteTieStop, let midi = midiNumber(step: step, alter: alter, octave: octave) {
                notes.append(
                    ParsedNote(
                        beat: max(0, startBeat),
                        duration: max(1.0 / 32.0, durationBeats),
                        midiNote: midi,
                        velocity: 92
                    )
                )
            }

            if !noteChord {
                lastNoteStart = partCursor
                partCursor += durationBeats
                measureMax = max(measureMax, partCursor)
            }
            inNote = false

        case "backup":
            inBackup = false

        case "forward":
            inForward = false

        case "measure":
            partCursor = max(partCursor, measureMax)
            measureStart = partCursor

        default:
            break
        }

        currentText = ""
    }

    private func midiNumber(step: String, alter: Int, octave: Int) -> UInt8? {
        let base: Int
        switch step.uppercased() {
        case "C": base = 0
        case "D": base = 2
        case "E": base = 4
        case "F": base = 5
        case "G": base = 7
        case "A": base = 9
        case "B": base = 11
        default: return nil
        }
        let value = (octave + 1) * 12 + base + alter
        guard (0...127).contains(value) else { return nil }
        return UInt8(value)
    }
}

private enum MIDIWriter {
    private static let ppq = 480

    static func write(score: ParsedScore) throws -> URL {
        var data = Data()
        data.appendASCII("MThd")
        data.appendBE32(6)
        data.appendBE16(1)
        data.appendBE16(2)
        data.appendBE16(UInt16(ppq))

        data.append(trackChunk(tempoTrack(score.tempos)))
        data.append(trackChunk(noteTrack(score.notes)))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("score-\(UUID().uuidString).mid")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func tempoTrack(_ tempos: [TempoPoint]) -> Data {
        var output = Data()
        var lastTick = 0

        for tempo in ScorePipeline.normalizedTempoMap(tempos) {
            let tick = max(0, Int((tempo.beat * Double(ppq)).rounded()))
            output.appendVLQ(tick - lastTick)
            output.append(contentsOf: [0xFF, 0x51, 0x03])
            let microseconds = max(1, Int((60_000_000.0 / tempo.bpm).rounded()))
            output.append(UInt8((microseconds >> 16) & 0xFF))
            output.append(UInt8((microseconds >> 8) & 0xFF))
            output.append(UInt8(microseconds & 0xFF))
            lastTick = tick
        }

        output.append(contentsOf: [0x00, 0xFF, 0x2F, 0x00])
        return output
    }

    private struct Event {
        let tick: Int
        let priority: Int
        let bytes: [UInt8]
    }

    private static func noteTrack(_ notes: [ParsedNote]) -> Data {
        var events: [Event] = [
            Event(tick: 0, priority: 0, bytes: [0xC0, 0x00])
        ]

        for note in notes {
            let onTick = max(0, Int((note.beat * Double(ppq)).rounded()))
            let offTick = max(onTick + 1, Int(((note.beat + note.duration) * Double(ppq)).rounded()))
            events.append(Event(tick: onTick, priority: 1, bytes: [0x90, note.midiNote, note.velocity]))
            events.append(Event(tick: offTick, priority: 0, bytes: [0x80, note.midiNote, 0]))
        }

        events.sort {
            if $0.tick == $1.tick { return $0.priority < $1.priority }
            return $0.tick < $1.tick
        }

        var output = Data()
        var lastTick = 0
        for event in events {
            output.appendVLQ(event.tick - lastTick)
            output.append(contentsOf: event.bytes)
            lastTick = event.tick
        }
        output.append(contentsOf: [0x00, 0xFF, 0x2F, 0x00])
        return output
    }

    private static func trackChunk(_ body: Data) -> Data {
        var chunk = Data()
        chunk.appendASCII("MTrk")
        chunk.appendBE32(UInt32(body.count))
        chunk.append(body)
        return chunk
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(string.data(using: .ascii)!)
    }

    mutating func appendBE16(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func appendBE32(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func appendVLQ(_ value: Int) {
        var buffer = [UInt8](repeating: 0, count: 5)
        var v = max(0, value)
        var index = 4
        buffer[index] = UInt8(v & 0x7F)
        while {
            v >>= 7
            if v == 0 { break }
            index -= 1
            buffer[index] = UInt8((v & 0x7F) | 0x80)
        }
        append(contentsOf: buffer[index...4])
    }
}
