import Foundation
import AVFoundation
import AudioToolbox

enum DefaultMIDIRendererError: LocalizedError {
    case invalidMIDI(OSStatus)
    case noNotes
    case cannotCreateBuffer

    var errorDescription: String? {
        switch self {
        case .invalidMIDI(let status):
            return "The MIDI file could not be rendered (AudioToolbox status \(status))."
        case .noNotes:
            return "The score contains no playable MIDI notes."
        case .cannotCreateBuffer:
            return "Could not create the default instrument audio buffer."
        }
    }
}

private struct RenderNote {
    let start: Double
    let duration: Double
    let frequency: Double
    let velocity: Double
    let pan: Double

    var end: Double { start + duration + 1.8 }
}

enum DefaultMIDIRenderer {
    static func renderPianoWAV(midiURL: URL) throws -> URL {
        let notes = try readNotes(midiURL)
        guard !notes.isEmpty else { throw DefaultMIDIRendererError.noNotes }

        let sampleRate = 48_000.0
        let blockFrames = 2048
        let totalDuration = (notes.map(\.end).max() ?? 0) + 0.35
        let totalFrames = Int64(ceil(totalDuration * sampleRate))

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        ) else {
            throw DefaultMIDIRendererError.cannotCreateBuffer
        }

        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("default-piano-\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: out, settings: format.settings)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(blockFrames)
        ) else {
            throw DefaultMIDIRendererError.cannotCreateBuffer
        }

        let sorted = notes.sorted { $0.start < $1.start }
        var nextIndex = 0
        var active: [RenderNote] = []
        var framePosition: Int64 = 0

        while framePosition < totalFrames {
            let framesThisBlock = Int(min(Int64(blockFrames), totalFrames - framePosition))
            let blockStart = Double(framePosition) / sampleRate
            let blockEnd = Double(framePosition + Int64(framesThisBlock)) / sampleRate

            while nextIndex < sorted.count, sorted[nextIndex].start <= blockEnd {
                active.append(sorted[nextIndex])
                nextIndex += 1
            }
            active.removeAll { $0.end < blockStart }

            buffer.frameLength = AVAudioFrameCount(framesThisBlock)
            guard let channels = buffer.floatChannelData else {
                throw DefaultMIDIRendererError.cannotCreateBuffer
            }

            let left = channels[0]
            let right = channels[1]

            for i in 0..<framesThisBlock {
                left[i] = 0
                right[i] = 0
            }

            for note in active {
                let firstSample = max(
                    0,
                    Int(floor((note.start - blockStart) * sampleRate))
                )
                let lastSample = min(
                    framesThisBlock,
                    Int(ceil((note.end - blockStart) * sampleRate))
                )
                guard firstSample < lastSample else { continue }

                let leftGain = sqrt((1.0 - note.pan) * 0.5)
                let rightGain = sqrt((1.0 + note.pan) * 0.5)

                for i in firstSample..<lastSample {
                    let absoluteTime = blockStart + Double(i) / sampleRate
                    let t = absoluteTime - note.start
                    guard t >= 0 else { continue }

                    let envelope = pianoEnvelope(time: t, noteDuration: note.duration)
                    guard envelope > 0.00001 else { continue }

                    let phase = 2.0 * Double.pi * note.frequency * t
                    let hammer = exp(-t * 30.0)

                    var sample =
                        sin(phase) * 1.00 +
                        sin(phase * 2.0) * 0.42 +
                        sin(phase * 3.0) * 0.18 +
                        sin(phase * 4.0) * 0.08 +
                        sin(phase * 5.0) * 0.035

                    sample += sin(phase * 7.03) * 0.10 * hammer
                    sample += sin(phase * 11.11) * 0.045 * hammer

                    let gain = 0.105 * pow(note.velocity, 1.25) * envelope
                    let value = sample * gain

                    left[i] += Float(value * leftGain)
                    right[i] += Float(value * rightGain)
                }
            }

            for i in 0..<framesThisBlock {
                left[i] = Float(tanh(Double(left[i]) * 1.15) * 0.88)
                right[i] = Float(tanh(Double(right[i]) * 1.15) * 0.88)
            }

            try file.write(from: buffer)
            framePosition += Int64(framesThisBlock)
        }

        return out
    }

    private static func pianoEnvelope(time: Double, noteDuration: Double) -> Double {
        let attack = 0.006
        let decay = 1.45
        let sustain = 0.19
        let release = 0.82

        if time < attack {
            return time / attack
        }

        let held = sustain + (1.0 - sustain) * exp(-(time - attack) / decay)
        if time <= noteDuration {
            return held
        }

        let atRelease = sustain + (1.0 - sustain) * exp(-(max(0, noteDuration - attack)) / decay)
        return atRelease * exp(-(time - noteDuration) / release)
    }

    private static func readNotes(_ url: URL) throws -> [RenderNote] {
        var sequence: MusicSequence?
        let create = NewMusicSequence(&sequence)
        guard create == noErr, let sequence else {
            throw DefaultMIDIRendererError.invalidMIDI(create)
        }
        defer { DisposeMusicSequence(sequence) }

        let load = MusicSequenceFileLoad(
            sequence,
            url as CFURL,
            .midiType,
            .smf_ChannelsToTracks
        )
        guard load == noErr else {
            throw DefaultMIDIRendererError.invalidMIDI(load)
        }

        var output: [RenderNote] = []
        var trackCount: UInt32 = 0
        MusicSequenceGetTrackCount(sequence, &trackCount)

        for index in 0..<trackCount {
            var track: MusicTrack?
            guard MusicSequenceGetIndTrack(sequence, index, &track) == noErr,
                  let track else { continue }

            var iterator: MusicEventIterator?
            guard NewMusicEventIterator(track, &iterator) == noErr,
                  let iterator else { continue }
            defer { DisposeMusicEventIterator(iterator) }

            var hasEvent = DarwinBoolean(false)
            MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)

            while hasEvent.boolValue {
                var beat: MusicTimeStamp = 0
                var eventType: MusicEventType = 0
                var eventData: UnsafeRawPointer?
                var eventDataSize: UInt32 = 0

                if MusicEventIteratorGetEventInfo(
                    iterator,
                    &beat,
                    &eventType,
                    &eventData,
                    &eventDataSize
                ) == noErr,
                   eventType == kMusicEventType_MIDINoteMessage,
                   let eventData {
                    let message = eventData.load(as: MIDINoteMessage.self)

                    var startSeconds: Float64 = 0
                    var endSeconds: Float64 = 0
                    MusicSequenceGetSecondsForBeats(sequence, beat, &startSeconds)
                    MusicSequenceGetSecondsForBeats(
                        sequence,
                        beat + MusicTimeStamp(message.duration),
                        &endSeconds
                    )

                    let midi = Double(message.note)
                    let frequency = 440.0 * pow(2.0, (midi - 69.0) / 12.0)
                    let normalizedVelocity = max(0.08, Double(message.velocity) / 127.0)
                    let pan = max(-0.42, min(0.42, (midi - 60.0) / 48.0))

                    output.append(
                        RenderNote(
                            start: startSeconds,
                            duration: max(0.03, endSeconds - startSeconds),
                            frequency: frequency,
                            velocity: normalizedVelocity,
                            pan: pan
                        )
                    )
                }

                MusicEventIteratorNextEvent(iterator)
                MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)
            }
        }

        return output
    }
}
