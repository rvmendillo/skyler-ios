import Foundation
import AVFoundation

struct WaveformComparison: Sendable {
    let correlation: Double
    let rmsErrorPercent: Double
    let comparedSamples: Int64

    var summary: String {
        let corr = max(0, min(1, correlation)) * 100
        return String(
            format: "Waveform %.2f%% correlated • RMS error %.2f%%",
            corr,
            rmsErrorPercent
        )
    }
}

enum WaveformQualityCheckerError: LocalizedError {
    case incompatibleFormats
    case cannotReadSamples
    case noSamples

    var errorDescription: String? {
        switch self {
        case .incompatibleFormats:
            return "Reference WAV and decoded MP3 formats do not match for waveform comparison."
        case .cannotReadSamples:
            return "Could not decode samples for waveform comparison."
        case .noSamples:
            return "No samples were available for waveform comparison."
        }
    }
}

enum WaveformQualityChecker {
    static func compare(referenceWAV: URL, encodedMP3: URL) async throws -> WaveformComparison {
        try await Task.detached(priority: .utility) {
            try compareSynchronously(referenceWAV: referenceWAV, encodedMP3: encodedMP3)
        }.value
    }

    private static func compareSynchronously(
        referenceWAV: URL,
        encodedMP3: URL
    ) throws -> WaveformComparison {
        let reference = try AVAudioFile(forReading: referenceWAV)
        let encoded = try AVAudioFile(forReading: encodedMP3)

        let refFormat = reference.processingFormat
        let encFormat = encoded.processingFormat

        guard abs(refFormat.sampleRate - encFormat.sampleRate) < 1,
              refFormat.channelCount == encFormat.channelCount,
              refFormat.commonFormat == .pcmFormatFloat32,
              encFormat.commonFormat == .pcmFormatFloat32 else {
            throw WaveformQualityCheckerError.incompatibleFormats
        }

        let capacity: AVAudioFrameCount = 4096
        guard let refBuffer = AVAudioPCMBuffer(pcmFormat: refFormat, frameCapacity: capacity),
              let encBuffer = AVAudioPCMBuffer(pcmFormat: encFormat, frameCapacity: capacity) else {
            throw WaveformQualityCheckerError.cannotReadSamples
        }

        var sumXY = 0.0
        var sumX2 = 0.0
        var sumY2 = 0.0
        var sumError2 = 0.0
        var sampleCount: Int64 = 0

        while true {
            try reference.read(into: refBuffer, frameCount: capacity)
            try encoded.read(into: encBuffer, frameCount: capacity)

            let frames = min(Int(refBuffer.frameLength), Int(encBuffer.frameLength))
            if frames == 0 { break }

            guard let refChannels = refBuffer.floatChannelData,
                  let encChannels = encBuffer.floatChannelData else {
                throw WaveformQualityCheckerError.cannotReadSamples
            }

            for channel in 0..<Int(refFormat.channelCount) {
                let x = refChannels[channel]
                let y = encChannels[channel]

                for i in 0..<frames {
                    let xd = Double(x[i])
                    let yd = Double(y[i])
                    let diff = xd - yd

                    sumXY += xd * yd
                    sumX2 += xd * xd
                    sumY2 += yd * yd
                    sumError2 += diff * diff
                    sampleCount += 1
                }
            }

            if refBuffer.frameLength < capacity || encBuffer.frameLength < capacity {
                break
            }
        }

        guard sampleCount > 0, sumX2 > 0, sumY2 > 0 else {
            throw WaveformQualityCheckerError.noSamples
        }

        let correlation = sumXY / sqrt(sumX2 * sumY2)
        let normalizedRMSE = sqrt(sumError2 / sumX2)

        return WaveformComparison(
            correlation: correlation,
            rmsErrorPercent: normalizedRMSE * 100,
            comparedSamples: sampleCount
        )
    }
}
