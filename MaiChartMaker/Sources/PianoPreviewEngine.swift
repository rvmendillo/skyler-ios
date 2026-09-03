import Foundation
import AVFoundation

@MainActor
final class PianoPreviewEngine {
    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0

    private var loadedBankURL: URL?
    private var loadedProgram: Int?
    private var builtInBuffers: [Int: AVAudioPCMBuffer] = [:]
    private var activeSamplerNotes: [UInt8: Int] = [:]

    init() {
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)

        for _ in 0..<6 {
            let player = AVAudioPlayerNode()
            players.append(player)
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: nil)
        }
    }

    func play(
        midiNote: UInt8,
        velocity: UInt8 = 100,
        soundFontURL: URL?,
        program: Int
    ) throws {
        try prepareAudioSession()

        let playableNote = normalizedPlayableNote(midiNote)

        if let bankURL = soundFontURL ?? BundledSoundBank.url {
            try ensureSoundFont(bankURL, program: program)
            activeSamplerNotes[playableNote, default: 0] += 1
            sampler.startNote(playableNote, withVelocity: velocity, onChannel: 0)
        } else {
            let key = (program << 8) | Int(playableNote)
            let buffer = builtInBuffers[key] ?? makeBuiltInBuffer(
                note: playableNote,
                velocity: velocity,
                program: program
            )
            builtInBuffers[key] = buffer

            guard !players.isEmpty else { return }
            let player = players[nextPlayer % players.count]
            nextPlayer = (nextPlayer + 1) % players.count

            player.stop()
            player.scheduleBuffer(buffer, at: nil, options: .interrupts)
            player.play()
        }
    }

    func stop(midiNote: UInt8, soundFontURL: URL?) {
        let playableNote = normalizedPlayableNote(midiNote)
        let remaining = max(0, (activeSamplerNotes[playableNote] ?? 1) - 1)

        if remaining == 0 {
            activeSamplerNotes.removeValue(forKey: playableNote)
            sampler.stopNote(playableNote, onChannel: 0)
        } else {
            activeSamplerNotes[playableNote] = remaining
        }
    }

    func stopAll() {
        for note in UInt8(0)...UInt8(127) {
            sampler.stopNote(note, onChannel: 0)
        }
        players.forEach { $0.stop() }
        activeSamplerNotes.removeAll()
    }

    func invalidateSoundFont() {
        loadedBankURL = nil
        loadedProgram = nil
    }

    func instrumentChanged() {
        stopAll()
        loadedProgram = nil
    }

    private func prepareAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)

        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    private func ensureSoundFont(_ url: URL, program: Int) throws {
        if loadedBankURL == url, loadedProgram == program {
            return
        }

        try sampler.loadSoundBankInstrument(
            at: url,
            program: UInt8(clamping: program),
            bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
            bankLSB: UInt8(kAUSampler_DefaultBankLSB)
        )

        loadedBankURL = url
        loadedProgram = program
    }

    private func normalizedPlayableNote(_ note: UInt8) -> UInt8 {
        var value = Int(note)

        // A few SF2 presets have sparse extreme ranges. Fold preview-only
        // notes by octaves into a reliable audible range rather than dropping
        // them. The chart keeps the original MIDI pitch and timing.
        while value < 36 { value += 12 }
        while value > 96 { value -= 12 }

        return UInt8(clamping: value)
    }

    private func makeBuiltInBuffer(
        note: UInt8,
        velocity: UInt8,
        program: Int
    ) -> AVAudioPCMBuffer {
        let sampleRate = 48_000.0
        let noteDuration = 0.78
        let duration = noteDuration + BuiltInInstrumentSynth.tailDuration(program: program)
        let frames = AVAudioFrameCount(duration * sampleRate)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        )!

        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames

        let frequency = 440.0 * pow(2.0, (Double(note) - 69.0) / 12.0)
        let pan = max(-0.42, min(0.42, (Double(note) - 60.0) / 48.0))
        let leftGain = sqrt((1.0 - pan) * 0.5)
        let rightGain = sqrt((1.0 + pan) * 0.5)
        let normalizedVelocity = max(0.08, Double(velocity) / 127.0)

        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]

        for frame in 0..<Int(frames) {
            let t = Double(frame) / sampleRate
            let value = BuiltInInstrumentSynth.sample(
                frequency: frequency,
                time: t,
                noteDuration: noteDuration,
                velocity: normalizedVelocity,
                program: program
            )
            left[frame] = Float(value * leftGain)
            right[frame] = Float(value * rightGain)
        }

        return buffer
    }
}
