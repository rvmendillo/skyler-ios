import Foundation
import CoreML
import AVFoundation
import Accelerate

private enum BasicPitchConstants {
    static let sampleRate: Double = 22_050
    static let fftHop = 256
    static let framesPerWindow = 172
    static let audioSamplesPerWindow = 43_844
    static let noteBins = 88
    static let midiOffset = 21
    static let overlapFrames = 30
}

struct BasicPitchDetectedNote: Sendable {
    let start: Double
    let end: Double
    let midiPitch: UInt8
    let strength: Double

    var duration: Double { max(0.04, end - start) }
}

struct AudioTranscriptionResult: Sendable {
    let melodyBeatPositions: [Double]
    let melodyPitches: [UInt8]
    let melodyStrengths: [Double]
    let pianoGameNotes: [PianoGameNote]
}

enum BasicPitchAudioTranscriberError: LocalizedError {
    case modelMissing
    case audioConversionFailed
    case invalidModelOutput

    var errorDescription: String? {
        switch self {
        case .modelMissing:
            return "The bundled Basic Pitch CoreML model could not be found."
        case .audioConversionFailed:
            return "Could not prepare the audio for on-device melody transcription."
        case .invalidModelOutput:
            return "Basic Pitch returned an invalid model output."
        }
    }
}

actor BasicPitchAudioTranscriber {
    static let shared = BasicPitchAudioTranscriber()

    private var model: MLModel?

    func transcribe(
        audioURL: URL,
        bpm: Double,
        firstBeat: Double
    ) async throws -> AudioTranscriptionResult {
        let model = try await loadModelIfNeeded()
        let samples = try loadAudio(url: audioURL)
        let windows = windowAudio(samples: samples)

        var batchedNotes: [[[Float]]] = []
        var batchedOnsets: [[[Float]]] = []

        for window in windows {
            let input = try makeInput(window)
            let provider = try MLDictionaryFeatureProvider(
                dictionary: [
                    "input_2": MLFeatureValue(multiArray: input)
                ]
            )
            let result = try model.prediction(from: provider)

            guard
                let notesArray = result.featureValue(for: "Identity_1")?.multiArrayValue,
                let onsetsArray = result.featureValue(for: "Identity_2")?.multiArrayValue
            else {
                throw BasicPitchAudioTranscriberError.invalidModelOutput
            }

            batchedNotes.append(
                multiArrayTo2D(
                    notesArray,
                    rows: BasicPitchConstants.framesPerWindow,
                    cols: BasicPitchConstants.noteBins
                )
            )
            batchedOnsets.append(
                multiArrayTo2D(
                    onsetsArray,
                    rows: BasicPitchConstants.framesPerWindow,
                    cols: BasicPitchConstants.noteBins
                )
            )
        }

        let nOlap = BasicPitchConstants.overlapFrames / 2
        let notes = unwrap(batchedNotes, overlap: nOlap)
        let onsets = unwrap(batchedOnsets, overlap: nOlap)
        let detected = detectNotes(frames: notes, onsets: onsets)

        return makeResult(
            from: detected,
            bpm: bpm,
            firstBeat: firstBeat
        )
    }

    private func loadModelIfNeeded() async throws -> MLModel {
        if let model { return model }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        let compiled =
            Bundle.main.url(
                forResource: "BasicPitch_nmp",
                withExtension: "mlmodelc"
            )
            ?? Bundle.main.url(
                forResource: "nmp",
                withExtension: "mlmodelc"
            )

        if let compiled {
            let loaded = try MLModel(
                contentsOf: compiled,
                configuration: configuration
            )
            model = loaded
            return loaded
        }

        let package =
            Bundle.main.url(
                forResource: "BasicPitch_nmp",
                withExtension: "mlpackage"
            )
            ?? Bundle.main.url(
                forResource: "nmp",
                withExtension: "mlpackage"
            )

        guard let package else {
            throw BasicPitchAudioTranscriberError.modelMissing
        }

        let compiledURL = try await MLModel.compileModel(at: package)
        let loaded = try MLModel(
            contentsOf: compiledURL,
            configuration: configuration
        )
        model = loaded
        return loaded
    }

    private func loadAudio(url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: BasicPitchConstants.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw BasicPitchAudioTranscriberError.audioConversionFailed
        }

        guard let converter = AVAudioConverter(
            from: file.processingFormat,
            to: target
        ) else {
            throw BasicPitchAudioTranscriberError.audioConversionFailed
        }

        let ratio =
            BasicPitchConstants.sampleRate /
            max(1, file.processingFormat.sampleRate)
        let capacity =
            AVAudioFrameCount(Double(file.length) * ratio) + 4096

        guard let output = AVAudioPCMBuffer(
            pcmFormat: target,
            frameCapacity: capacity
        ) else {
            throw BasicPitchAudioTranscriberError.audioConversionFailed
        }

        let inputBlock: AVAudioConverterInputBlock = { requested, status in
            let capacity = max(1024, requested)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: capacity
            ) else {
                status.pointee = .endOfStream
                return nil
            }

            do {
                try file.read(into: buffer, frameCount: capacity)
                if buffer.frameLength == 0 {
                    status.pointee = .endOfStream
                    return nil
                }
                status.pointee = .haveData
                return buffer
            } catch {
                status.pointee = .endOfStream
                return nil
            }
        }

        var error: NSError?
        converter.convert(
            to: output,
            error: &error,
            withInputFrom: inputBlock
        )

        if let error { throw error }

        guard let channel = output.floatChannelData?[0] else {
            throw BasicPitchAudioTranscriberError.audioConversionFailed
        }

        var samples = Array(
            UnsafeBufferPointer(
                start: channel,
                count: Int(output.frameLength)
            )
        )

        var peak: Float = 0
        if !samples.isEmpty {
            vDSP_maxmgv(
                samples,
                1,
                &peak,
                vDSP_Length(samples.count)
            )
        }

        if peak > 0 {
            var scale: Float = 0.98 / peak
            vDSP_vsmul(
                samples,
                1,
                &scale,
                &samples,
                1,
                vDSP_Length(samples.count)
            )
        }

        return samples
    }

    private func windowAudio(samples: [Float]) -> [[Float]] {
        let overlap =
            BasicPitchConstants.overlapFrames *
            BasicPitchConstants.fftHop
        let hop =
            BasicPitchConstants.audioSamplesPerWindow - overlap

        let padded =
            [Float](repeating: 0, count: overlap / 2) +
            samples

        var windows: [[Float]] = []
        var offset = 0

        while offset < padded.count {
            let end = min(
                offset + BasicPitchConstants.audioSamplesPerWindow,
                padded.count
            )
            var window = Array(padded[offset..<end])

            if window.count < BasicPitchConstants.audioSamplesPerWindow {
                window.append(
                    contentsOf: repeatElement(
                        0,
                        count:
                            BasicPitchConstants.audioSamplesPerWindow -
                            window.count
                    )
                )
            }

            windows.append(window)
            offset += hop
        }

        return windows
    }

    private func makeInput(_ window: [Float]) throws -> MLMultiArray {
        let input = try MLMultiArray(
            shape: [
                1,
                NSNumber(value: BasicPitchConstants.audioSamplesPerWindow),
                1
            ],
            dataType: .float32
        )

        let strides = input.strides.map(\.intValue)
        let pointer = input.dataPointer
            .bindMemory(to: Float.self, capacity: input.count)

        for index in window.indices {
            pointer[index * strides[1]] = window[index]
        }

        return input
    }

    private func multiArrayTo2D(
        _ array: MLMultiArray,
        rows: Int,
        cols: Int
    ) -> [[Float]] {
        let strides = array.strides.map(\.intValue)
        let pointer = array.dataPointer
            .bindMemory(to: Float.self, capacity: array.count)

        let rowStride = strides.count >= 3 ? strides[1] : cols
        let colStride = strides.count >= 3 ? strides[2] : 1

        var output = [[Float]]()
        output.reserveCapacity(rows)

        for row in 0..<rows {
            var values = [Float](repeating: 0, count: cols)
            for col in 0..<cols {
                values[col] =
                    pointer[row * rowStride + col * colStride]
            }
            output.append(values)
        }

        return output
    }

    private func unwrap(
        _ batches: [[[Float]]],
        overlap: Int
    ) -> [[Float]] {
        var output: [[Float]] = []

        for batch in batches {
            guard batch.count > overlap * 2 else { continue }
            output.append(
                contentsOf:
                    batch[overlap..<(batch.count - overlap)]
            )
        }

        return output
    }

    private func detectNotes(
        frames: [[Float]],
        onsets: [[Float]]
    ) -> [BasicPitchDetectedNote] {
        guard
            !frames.isEmpty,
            frames.count == onsets.count,
            let width = frames.first?.count,
            width > 0
        else {
            return []
        }

        let inferred = inferredOnsets(
            onsets: onsets,
            frames: frames
        )
        var remaining = frames
        var peaks: [(time: Int, pitch: Int)] = []

        if frames.count > 2 {
            for time in 1..<(frames.count - 1) {
                for pitch in 0..<width {
                    if
                        inferred[time][pitch] >= 0.50,
                        inferred[time][pitch] >
                            inferred[time - 1][pitch],
                        inferred[time][pitch] >
                            inferred[time + 1][pitch]
                    {
                        peaks.append((time, pitch))
                    }
                }
            }
        }

        peaks.reverse()

        let frameThreshold: Float = 0.30
        let tolerance = 11
        let minLength = 7
        var output: [BasicPitchDetectedNote] = []

        for peak in peaks {
            guard peak.time < frames.count - 1 else { continue }

            var index = peak.time + 1
            var below = 0

            while index < frames.count - 1, below < tolerance {
                if remaining[index][peak.pitch] < frameThreshold {
                    below += 1
                } else {
                    below = 0
                }
                index += 1
            }

            index -= below

            guard index - peak.time > minLength else {
                continue
            }

            var amplitude: Float = 0
            for time in peak.time..<index {
                amplitude += frames[time][peak.pitch]
                remaining[time][peak.pitch] = 0

                if peak.pitch > 0 {
                    remaining[time][peak.pitch - 1] = 0
                }
                if peak.pitch + 1 < width {
                    remaining[time][peak.pitch + 1] = 0
                }
            }

            amplitude /=
                Float(max(1, index - peak.time))

            let start =
                Double(peak.time * BasicPitchConstants.fftHop) /
                BasicPitchConstants.sampleRate
            let end =
                Double(index * BasicPitchConstants.fftHop) /
                BasicPitchConstants.sampleRate

            output.append(
                BasicPitchDetectedNote(
                    start: start,
                    end: end,
                    midiPitch: UInt8(
                        clamping:
                            peak.pitch +
                            BasicPitchConstants.midiOffset
                    ),
                    strength: min(1, Double(amplitude))
                )
            )
        }

        return output.sorted { $0.start < $1.start }
    }

    private func inferredOnsets(
        onsets: [[Float]],
        frames: [[Float]]
    ) -> [[Float]] {
        let rows = frames.count
        let cols = frames[0].count

        var differences = [[Float]](
            repeating: [Float](
                repeating: 0,
                count: cols
            ),
            count: rows
        )

        for time in 2..<rows {
            for pitch in 0..<cols {
                let d1 =
                    frames[time][pitch] -
                    frames[time - 1][pitch]
                let d2 =
                    frames[time][pitch] -
                    frames[time - 2][pitch]
                differences[time][pitch] =
                    max(0, min(d1, d2))
            }
        }

        let originalMax =
            onsets.lazy.flatMap { $0 }.max() ?? 1
        let diffMax =
            differences.lazy.flatMap { $0 }.max() ?? 0
        let scale =
            diffMax > 0 ? originalMax / diffMax : 1

        var output = onsets
        for time in 0..<rows {
            for pitch in 0..<cols {
                output[time][pitch] =
                    max(
                        output[time][pitch],
                        differences[time][pitch] * scale
                    )
            }
        }

        return output
    }

    private func makeResult(
        from notes: [BasicPitchDetectedNote],
        bpm: Double,
        firstBeat: Double
    ) -> AudioTranscriptionResult {
        let safeBPM = max(1, bpm)
        let secondsPerBeat = 60.0 / safeBPM

        struct MelodyChoice {
            let beat: Double
            let pitch: UInt8
            let strength: Double
        }

        var byStep: [Int: MelodyChoice] = [:]

        for note in notes {
            guard note.start >= max(0, firstBeat - 0.15) else {
                continue
            }

            let beat =
                max(0, (note.start - firstBeat) / secondsPerBeat)
            let step = Int((beat * 4.0).rounded())

            let rangeBonus: Double
            switch note.midiPitch {
            case 55...96:
                rangeBonus = 0.18
            case 45...108:
                rangeBonus = 0.08
            default:
                rangeBonus = 0
            }

            let score = note.strength + rangeBonus

            if let old = byStep[step] {
                let oldBonus =
                    (55...96).contains(old.pitch) ? 0.18 : 0
                if score <= old.strength + oldBonus {
                    continue
                }
            }

            byStep[step] = MelodyChoice(
                beat: Double(step) / 4.0,
                pitch: note.midiPitch,
                strength: note.strength
            )
        }

        let melody = byStep.values.sorted { $0.beat < $1.beat }
        let gameNotes = makeGameNotes(notes)

        return AudioTranscriptionResult(
            melodyBeatPositions: melody.map(\.beat),
            melodyPitches: melody.map(\.pitch),
            melodyStrengths: melody.map(\.strength),
            pianoGameNotes: gameNotes
        )
    }

    private func makeGameNotes(
        _ notes: [BasicPitchDetectedNote]
    ) -> [PianoGameNote] {
        let sorted = notes
            .filter { $0.strength >= 0.30 }
            .sorted {
                if abs($0.start - $1.start) <= 0.020 {
                    return $0.strength > $1.strength
                }
                return $0.start < $1.start
            }

        var result: [PianoGameNote] = []
        var index = 0

        while index < sorted.count {
            let start = sorted[index].start
            var group: [BasicPitchDetectedNote] = []

            while
                index < sorted.count,
                abs(sorted[index].start - start) <= 0.025
            {
                group.append(sorted[index])
                index += 1
            }

            let selected = group
                .sorted {
                    if abs($0.strength - $1.strength) > 0.001 {
                        return $0.strength > $1.strength
                    }
                    return $0.midiPitch > $1.midiPitch
                }
                .prefix(2)

            var usedLanes = Set<Int>()

            for note in selected {
                var lane = Int(note.midiPitch) % 4

                if usedLanes.contains(lane) {
                    for offset in 1...3 {
                        let candidate = (lane + offset) % 4
                        if !usedLanes.contains(candidate) {
                            lane = candidate
                            break
                        }
                    }
                }

                usedLanes.insert(lane)

                result.append(
                    PianoGameNote(
                        time: note.start,
                        duration: note.duration,
                        midiNote: note.midiPitch,
                        velocity: UInt8(
                            clamping:
                                Int(
                                    max(
                                        1,
                                        min(
                                            127,
                                            (note.strength * 127).rounded()
                                        )
                                    )
                                )
                        ),
                        lane: lane
                    )
                )
            }
        }

        return result.sorted { $0.time < $1.time }
    }
}
