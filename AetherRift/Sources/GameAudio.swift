import AVFoundation
import Foundation

enum GameSoundCue {
    case uiSelect
    case attack
    case skill1
    case skill2
    case skill3
    case ultimate
    case hit
    case purchase
    case levelUp
    case objective
    case respawn
    case victory
    case defeat
}

final class GameAudio {
    static let shared = GameAudio()

    private let engine = AVAudioEngine()
    private let ambienceMixer = AVAudioMixerNode()
    private let sfxMixer = AVAudioMixerNode()
    private var ambienceSource: AVAudioSourceNode?
    private var sfxNodes: [AVAudioPlayerNode] = []
    private var nextSFXNode = 0
    private let sampleRate = 44_100.0
    private var configured = false
    private let lock = NSLock()

    private init() {
        configureIfNeeded()
    }

    func startBattleAmbience() {
        configureIfNeeded()
        activateSession()
        ambienceMixer.outputVolume = 0.11
        sfxMixer.outputVolume = 0.82
        if !engine.isRunning {
            try? engine.start()
        }
    }

    func stopBattleAmbience() {
        ambienceMixer.outputVolume = 0
    }

    func play(_ cue: GameSoundCue) {
        configureIfNeeded()
        activateSession()
        if !engine.isRunning {
            try? engine.start()
        }

        let spec = soundSpec(for: cue)
        guard let buffer = makeBuffer(spec: spec) else { return }

        lock.lock()
        guard !sfxNodes.isEmpty else {
            lock.unlock()
            return
        }
        let node = sfxNodes[nextSFXNode % sfxNodes.count]
        nextSFXNode += 1
        lock.unlock()

        node.stop()
        node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        node.play()
    }

    private func configureIfNeeded() {
        guard !configured else { return }
        configured = true

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        engine.attach(ambienceMixer)
        engine.attach(sfxMixer)
        engine.connect(ambienceMixer, to: engine.mainMixerNode, format: format)
        engine.connect(sfxMixer, to: engine.mainMixerNode, format: format)

        var phaseA = 0.0
        var phaseB = 0.0
        var shimmerPhase = 0.0
        var noiseSeed: UInt64 = 0x9E3779B97F4A7C15

        let source = AVAudioSourceNode(format: format) { [sampleRate] _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let count = Int(frameCount)

            for frame in 0..<count {
                phaseA += 2 * .pi * 73.0 / sampleRate
                phaseB += 2 * .pi * 109.5 / sampleRate
                shimmerPhase += 2 * .pi * 418.0 / sampleRate
                if phaseA > 2 * .pi { phaseA -= 2 * .pi }
                if phaseB > 2 * .pi { phaseB -= 2 * .pi }
                if shimmerPhase > 2 * .pi { shimmerPhase -= 2 * .pi }

                noiseSeed ^= noiseSeed << 13
                noiseSeed ^= noiseSeed >> 7
                noiseSeed ^= noiseSeed << 17
                let unitNoise = Double(noiseSeed & 0xFFFF) / Double(0xFFFF)
                let wind = (unitNoise * 2 - 1) * 0.022
                let drone = sin(phaseA) * 0.038 + sin(phaseB) * 0.025
                let shimmer = sin(shimmerPhase) * 0.006
                let sample = Float(drone + wind + shimmer)

                for buffer in buffers {
                    guard let data = buffer.mData else { continue }
                    data.assumingMemoryBound(to: Float.self)[frame] = sample
                }
            }
            return noErr
        }
        ambienceSource = source
        engine.attach(source)
        engine.connect(source, to: ambienceMixer, format: format)

        for _ in 0..<8 {
            let node = AVAudioPlayerNode()
            sfxNodes.append(node)
            engine.attach(node)
            engine.connect(node, to: sfxMixer, format: format)
        }

        ambienceMixer.outputVolume = 0
        sfxMixer.outputVolume = 0.82
        try? engine.prepare()
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // Audio is non-critical; gameplay remains available if the session is unavailable.
        }
    }

    private struct SoundSpec {
        let duration: Double
        let startFrequency: Double
        let endFrequency: Double
        let secondFrequency: Double
        let noise: Double
        let gain: Double
        let pulse: Double
    }

    private func soundSpec(for cue: GameSoundCue) -> SoundSpec {
        switch cue {
        case .uiSelect:
            return .init(duration: 0.12, startFrequency: 520, endFrequency: 760, secondFrequency: 1040, noise: 0.02, gain: 0.24, pulse: 0)
        case .attack:
            return .init(duration: 0.16, startFrequency: 310, endFrequency: 125, secondFrequency: 610, noise: 0.20, gain: 0.34, pulse: 0)
        case .skill1:
            return .init(duration: 0.26, startFrequency: 440, endFrequency: 760, secondFrequency: 880, noise: 0.05, gain: 0.30, pulse: 8)
        case .skill2:
            return .init(duration: 0.30, startFrequency: 260, endFrequency: 980, secondFrequency: 520, noise: 0.08, gain: 0.31, pulse: 11)
        case .skill3:
            return .init(duration: 0.38, startFrequency: 720, endFrequency: 300, secondFrequency: 1080, noise: 0.10, gain: 0.30, pulse: 6)
        case .ultimate:
            return .init(duration: 0.72, startFrequency: 180, endFrequency: 920, secondFrequency: 360, noise: 0.14, gain: 0.38, pulse: 4)
        case .hit:
            return .init(duration: 0.10, startFrequency: 150, endFrequency: 72, secondFrequency: 290, noise: 0.34, gain: 0.23, pulse: 0)
        case .purchase:
            return .init(duration: 0.34, startFrequency: 660, endFrequency: 990, secondFrequency: 1320, noise: 0.01, gain: 0.27, pulse: 10)
        case .levelUp:
            return .init(duration: 0.62, startFrequency: 440, endFrequency: 1320, secondFrequency: 660, noise: 0.01, gain: 0.29, pulse: 7)
        case .objective:
            return .init(duration: 0.78, startFrequency: 135, endFrequency: 520, secondFrequency: 270, noise: 0.08, gain: 0.36, pulse: 3)
        case .respawn:
            return .init(duration: 0.55, startFrequency: 330, endFrequency: 880, secondFrequency: 495, noise: 0.02, gain: 0.27, pulse: 5)
        case .victory:
            return .init(duration: 1.2, startFrequency: 392, endFrequency: 1176, secondFrequency: 588, noise: 0.01, gain: 0.32, pulse: 3)
        case .defeat:
            return .init(duration: 0.95, startFrequency: 300, endFrequency: 92, secondFrequency: 150, noise: 0.12, gain: 0.29, pulse: 2)
        }
    }

    private func makeBuffer(spec: SoundSpec) -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let frameCount = AVAudioFrameCount(max(1, Int(spec.duration * sampleRate)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frameCount

        var seed: UInt64 = UInt64(Date().timeIntervalSinceReferenceDate * 1_000_000) | 1
        let total = Int(frameCount)
        for i in 0..<total {
            let t = Double(i) / sampleRate
            let progress = Double(i) / Double(max(1, total - 1))
            let frequency = spec.startFrequency + (spec.endFrequency - spec.startFrequency) * progress
            let primary = sin(2 * .pi * frequency * t)
            let secondary = sin(2 * .pi * spec.secondFrequency * t) * 0.42

            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            let random = Double(seed & 0xFFFF) / Double(0xFFFF) * 2 - 1

            let attack = min(1, progress / 0.06)
            let release = pow(max(0, 1 - progress), 1.55)
            let pulse = spec.pulse > 0 ? (0.74 + 0.26 * sin(2 * .pi * spec.pulse * t)) : 1
            let value = (primary + secondary + random * spec.noise) * spec.gain * attack * release * pulse
            let sample = Float(max(-1, min(1, value)))

            channels[0][i] = sample
            channels[1][i] = sample * 0.96
        }
        return buffer
    }
}
