import Foundation
import AudioToolbox

struct PianoGameNote: Identifiable, Sendable, Hashable {
    let id: UUID
    let time: Double
    let duration: Double
    let midiNote: UInt8
    let velocity: UInt8
    let lane: Int

    init(
        id: UUID = UUID(),
        time: Double,
        duration: Double,
        midiNote: UInt8,
        velocity: UInt8,
        lane: Int
    ) {
        self.id = id
        self.time = time
        self.duration = duration
        self.midiNote = midiNote
        self.velocity = velocity
        self.lane = lane
    }
}

enum MIDIPianoGameLoaderError: LocalizedError {
    case invalidMIDI(OSStatus)
    case noNotes

    var errorDescription: String? {
        switch self {
        case .invalidMIDI(let status):
            return "Could not read MIDI for Piano Tiles (status \(status))."
        case .noNotes:
            return "No playable MIDI notes were found for Piano Tiles."
        }
    }
}

enum MIDIPianoGameLoader {
    private struct RawNote {
        let time: Double
        let duration: Double
        let midiNote: UInt8
        let velocity: UInt8
    }

    static func load(from midiURL: URL) throws -> [PianoGameNote] {
        var sequence: MusicSequence?
        let create = NewMusicSequence(&sequence)
        guard create == noErr, let sequence else {
            throw MIDIPianoGameLoaderError.invalidMIDI(create)
        }
        defer { DisposeMusicSequence(sequence) }

        let load = MusicSequenceFileLoad(
            sequence,
            midiURL as CFURL,
            .midiType,
            .smf_ChannelsToTracks
        )
        guard load == noErr else {
            throw MIDIPianoGameLoaderError.invalidMIDI(load)
        }

        var raw: [RawNote] = []
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

                    raw.append(
                        RawNote(
                            time: max(0, startSeconds),
                            duration: max(0.04, endSeconds - startSeconds),
                            midiNote: message.note,
                            velocity: max(1, message.velocity)
                        )
                    )
                }

                MusicEventIteratorNextEvent(iterator)
                MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)
            }
        }

        guard !raw.isEmpty else {
            throw MIDIPianoGameLoaderError.noNotes
        }

        let sorted = raw.sorted {
            if abs($0.time - $1.time) < 0.0005 {
                return $0.midiNote < $1.midiNote
            }
            return $0.time < $1.time
        }

        var output: [PianoGameNote] = []
        var index = 0

        while index < sorted.count {
            let start = sorted[index].time
            var group: [RawNote] = []

            while index < sorted.count, abs(sorted[index].time - start) <= 0.012 {
                group.append(sorted[index])
                index += 1
            }

            var used = Set<Int>()

            for (position, item) in group.enumerated() {
                let preferred = Int(item.midiNote) % 4
                var lane = preferred

                if used.contains(lane), used.count < 4 {
                    for offset in 1...3 {
                        let candidate = (preferred + offset) % 4
                        if !used.contains(candidate) {
                            lane = candidate
                            break
                        }
                    }
                }

                if group.count > 4, position >= 4 {
                    lane = position % 4
                }

                used.insert(lane)

                output.append(
                    PianoGameNote(
                        time: item.time,
                        duration: item.duration,
                        midiNote: item.midiNote,
                        velocity: item.velocity,
                        lane: lane
                    )
                )
            }
        }

        return output.sorted { $0.time < $1.time }
    }
}
