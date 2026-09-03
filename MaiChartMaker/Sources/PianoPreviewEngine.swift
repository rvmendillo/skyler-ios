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
    private var builtInBuffers: [UInt8: AVAudioPCMBuffer] = [:]

    init() {
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)

        for _ in 0..<10 {
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

        if let soundFontURL {
            try ensureSoundFont(soundFontURL, program: program)
            sampler.startNote(midiNote, withVelocity: velocity, onChannel: 0)
        } else {
            let buffer = builtInBuffers[midiNote] ?? makeBuiltInPianoBuffer(note: midiNote)
            builtInBuffers[midiNote] = buffer

            guard !players.isEmpty else { return }
            let player = players[nextPlayer % players.count]
            nextPlayer = (nextPlayer + 1) % players.count

            player.stop()
            player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
            player.play()
        }
    }

    func stop(midiNote: UInt8, soundFontURL: URL?) {
        if soundFontURL != nil {
            sampler.stopNote(midiNote, onChannel: 0)
        }
    }

    func stopAll() {
        for note in UInt8(0)...UInt8(127) {
            sampler.stopNote(note, onChannel: 0)
        }
        players.forEach { $0.stop() }
    }

    func invalidateSoundFont() {
        loadedBankURL = nil
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

    private func makeBuiltInPianoBuffer(note: UInt8) -> AVAudioPCMBuffer {
        let sampleRate = 48_000.0
        let duration = 1.65
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

        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]

        for frame in 0..<Int(frames) {
            let t = Double(frame) / sampleRate
            let attack = min(1.0, t / 0.006)
            let decay = 0.19 + 0.81 * exp(-max(0, t - 0.006) / 1.45)
            let release = t > 0.72 ? exp(-(t - 0.72) / 0.82) : 1.0
            let envelope = attack * decay * release

            let phase = 2.0 * Double.pi * frequency * t
            let hammer = exp(-t * 30.0)

            var sample =
                sin(phase) * 1.00 +
                sin(phase * 2.0) * 0.42 +
                sin(phase * 3.0) * 0.18 +
                sin(phase * 4.0) * 0.08 +
                sin(phase * 5.0) * 0.035

            sample += sin(phase * 7.03) * 0.10 * hammer
            sample += sin(phase * 11.11) * 0.045 * hammer

            let value = tanh(sample * 0.105 * envelope * 1.15) * 0.88
            left[frame] = Float(value * leftGain)
            right[frame] = Float(value * rightGain)
        }

        return buffer
    }
}
