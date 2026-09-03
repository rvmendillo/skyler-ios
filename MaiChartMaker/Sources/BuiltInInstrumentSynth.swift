import Foundation

enum BuiltInInstrumentSynth {
    static func tailDuration(program: Int) -> Double {
        switch program {
        case 16: return 0.35       // organ
        case 40, 42, 48, 52: return 1.2
        case 56, 60, 64, 73: return 0.65
        case 80, 88: return 1.0
        default: return 0.85
        }
    }

    static func sample(
        frequency: Double,
        time: Double,
        noteDuration: Double,
        velocity: Double,
        program: Int
    ) -> Double {
        let p = profile(program)
        let attackGain = min(1.0, time / max(0.001, p.attack))
        let held = p.sustain + (1.0 - p.sustain) * exp(-max(0, time - p.attack) / p.decay)

        let releaseGain: Double
        if time <= noteDuration {
            releaseGain = 1.0
        } else {
            releaseGain = exp(-(time - noteDuration) / p.release)
        }

        let env = attackGain * held * releaseGain
        if env < 0.000001 { return 0 }

        let vibrato = p.vibratoDepth == 0
            ? 1.0
            : 1.0 + sin(2.0 * .pi * p.vibratoRate * time) * p.vibratoDepth
        let phase = 2.0 * .pi * frequency * vibrato * time

        var raw = 0.0
        for (index, weight) in p.harmonics.enumerated() {
            let harmonic = Double(index + 1)
            raw += sin(phase * harmonic) * weight
        }

        if p.squareAmount > 0 {
            var square = 0.0
            for n in stride(from: 1, through: 11, by: 2) {
                square += sin(phase * Double(n)) / Double(n)
            }
            raw = raw * (1.0 - p.squareAmount) + square * p.squareAmount
        }

        if p.pluck > 0 {
            raw *= (1.0 - p.pluck) + p.pluck * exp(-time * 2.7)
        }

        if p.brightness > 0 {
            raw += sin(phase * 7.03) * p.brightness * exp(-time * 22.0)
            raw += sin(phase * 11.11) * p.brightness * 0.45 * exp(-time * 28.0)
        }

        let gain = p.gain * pow(max(0.05, velocity), 1.15) * env
        return tanh(raw * gain * 1.16) * 0.88
    }

    private struct Profile {
        let harmonics: [Double]
        let attack: Double
        let decay: Double
        let sustain: Double
        let release: Double
        let gain: Double
        let vibratoRate: Double
        let vibratoDepth: Double
        let brightness: Double
        let pluck: Double
        let squareAmount: Double
    }

    private static func profile(_ program: Int) -> Profile {
        switch program {
        case 1: // bright piano
            return .init(harmonics: [1,0.52,0.24,0.12,0.06], attack: 0.004, decay: 1.15, sustain: 0.16, release: 0.72, gain: 0.105, vibratoRate: 0, vibratoDepth: 0, brightness: 0.15, pluck: 0.18, squareAmount: 0)
        case 4: // electric piano
            return .init(harmonics: [1,0.28,0.08,0.03], attack: 0.008, decay: 1.7, sustain: 0.31, release: 0.9, gain: 0.12, vibratoRate: 5.2, vibratoDepth: 0.0012, brightness: 0.04, pluck: 0.05, squareAmount: 0)
        case 6: // harpsichord
            return .init(harmonics: [1,0.65,0.4,0.27,0.18,0.12], attack: 0.002, decay: 0.42, sustain: 0.05, release: 0.22, gain: 0.085, vibratoRate: 0, vibratoDepth: 0, brightness: 0.18, pluck: 0.52, squareAmount: 0)
        case 16: // organ
            return .init(harmonics: [1,0.62,0.34,0.22,0.13,0.08], attack: 0.02, decay: 8, sustain: 0.88, release: 0.28, gain: 0.072, vibratoRate: 5.5, vibratoDepth: 0.001, brightness: 0, pluck: 0, squareAmount: 0)
        case 24,25: // guitars
            return .init(harmonics: [1,0.46,0.22,0.12,0.06], attack: 0.003, decay: 0.72, sustain: 0.08, release: 0.38, gain: 0.105, vibratoRate: 0, vibratoDepth: 0, brightness: 0.08, pluck: 0.7, squareAmount: 0)
        case 32: // bass
            return .init(harmonics: [1,0.35,0.12,0.04], attack: 0.006, decay: 0.95, sustain: 0.28, release: 0.4, gain: 0.15, vibratoRate: 0, vibratoDepth: 0, brightness: 0.01, pluck: 0.18, squareAmount: 0)
        case 40,42: // violin/cello
            return .init(harmonics: [1,0.52,0.34,0.22,0.15,0.1], attack: 0.085, decay: 3.5, sustain: 0.76, release: 0.72, gain: 0.065, vibratoRate: 5.6, vibratoDepth: 0.003, brightness: 0, pluck: 0, squareAmount: 0)
        case 48: // string ensemble
            return .init(harmonics: [1,0.48,0.31,0.2,0.13], attack: 0.18, decay: 5, sustain: 0.82, release: 1.0, gain: 0.062, vibratoRate: 4.9, vibratoDepth: 0.0024, brightness: 0, pluck: 0, squareAmount: 0)
        case 52: // choir
            return .init(harmonics: [1,0.22,0.42,0.08,0.18], attack: 0.16, decay: 4.2, sustain: 0.8, release: 0.95, gain: 0.075, vibratoRate: 5.0, vibratoDepth: 0.0018, brightness: 0, pluck: 0, squareAmount: 0)
        case 56,60: // trumpet/horn
            return .init(harmonics: [1,0.62,0.42,0.3,0.2,0.13], attack: 0.035, decay: 2.8, sustain: 0.68, release: 0.38, gain: 0.065, vibratoRate: 5.1, vibratoDepth: 0.0012, brightness: 0.02, pluck: 0, squareAmount: 0)
        case 64: // sax
            return .init(harmonics: [1,0.18,0.43,0.08,0.2,0.05], attack: 0.035, decay: 2.5, sustain: 0.7, release: 0.42, gain: 0.085, vibratoRate: 5.2, vibratoDepth: 0.0024, brightness: 0.01, pluck: 0, squareAmount: 0)
        case 73: // flute
            return .init(harmonics: [1,0.09,0.025,0.01], attack: 0.055, decay: 3.8, sustain: 0.78, release: 0.5, gain: 0.13, vibratoRate: 5.4, vibratoDepth: 0.002, brightness: 0, pluck: 0, squareAmount: 0)
        case 80: // square lead
            return .init(harmonics: [1], attack: 0.008, decay: 4, sustain: 0.8, release: 0.35, gain: 0.085, vibratoRate: 5.8, vibratoDepth: 0.0015, brightness: 0, pluck: 0, squareAmount: 0.72)
        case 88: // fantasia pad
            return .init(harmonics: [1,0.34,0.16,0.08], attack: 0.32, decay: 5.5, sustain: 0.84, release: 1.1, gain: 0.085, vibratoRate: 4.3, vibratoDepth: 0.0025, brightness: 0, pluck: 0, squareAmount: 0.1)
        default: // acoustic grand piano
            return .init(harmonics: [1,0.42,0.18,0.08,0.035], attack: 0.006, decay: 1.45, sustain: 0.19, release: 0.82, gain: 0.105, vibratoRate: 0, vibratoDepth: 0, brightness: 0.10, pluck: 0.12, squareAmount: 0)
        }
    }
}
