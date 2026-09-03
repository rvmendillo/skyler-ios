import Foundation
import AVFoundation

struct WaveformComparison: Sendable {
    let correlation: Double
    let rmsErrorPercent: Double
    let comparedSamples: Int64
    let alignmentFrames: Int

    var passedHighQualityGate: Bool {
        correlation >= 0.985 && rmsErrorPercent <= 18.0
    }

    var summary: String {
        let corr = max(0, min(1, correlation)) * 100
        return String(
            format:
                "Aligned waveform %.2f%% correlated • RMS error %.2f%% • delay %+d frames",
            corr,
            rmsErrorPercent,
            alignmentFrames
        )
    }
}

enum WaveformQualityCheckerError: LocalizedError {
    case incompatibleFormats
    case cannotReadSamples
    case noSamples
    case qualityBelowThreshold(WaveformComparison)

    var errorDescription: String? {
        switch self {
        case .incompatibleFormats:
            return "Reference WAV and decoded MP3 formats do not match for waveform comparison."
        case .cannotReadSamples:
            return "Could not decode samples for waveform comparison."
        case .noSamples:
            return "No samples were available for waveform comparison."
        case .qualityBelowThreshold(let result):
            return "MP3 rejected by the WAV quality gate. \(result.summary). Required: at least 98.5% aligned correlation and at most 18% normalized RMS error."
        }
    }
}

enum WaveformQualityChecker {
    static func compare(
        referenceWAV: URL,
        encodedMP3: URL
    ) async throws -> WaveformComparison {
        try await Task.detached(priority: .utility) {
            try compareSynchronously(
                referenceWAV: referenceWAV,
                encodedMP3: encodedMP3
            )
        }.value
    }

    static func verify(
        referenceWAV: URL,
        encodedMP3: URL
    ) async throws -> WaveformComparison {
        let result = try await compare(
            referenceWAV: referenceWAV,
            encodedMP3: encodedMP3
        )

        guard result.passedHighQualityGate else {
            try? FileManager.default.removeItem(at: encodedMP3)
            throw WaveformQualityCheckerError.qualityBelowThreshold(result)
        }

        return result
    }

    private static func compareSynchronously(
        referenceWAV: URL,
        encodedMP3: URL
    ) throws -> WaveformComparison {
        let referencePreview = try AVAudioFile(forReading: referenceWAV)
        let encodedPreview = try AVAudioFile(forReading: encodedMP3)

        let refFormat = referencePreview.processingFormat
        let encFormat = encodedPreview.processingFormat

        guard
            abs(refFormat.sampleRate - encFormat.sampleRate) < 1,
            refFormat.channelCount == encFormat.channelCount,
            refFormat.commonFormat == .pcmFormatFloat32,
            encFormat.commonFormat == .pcmFormatFloat32
        else {
            throw WaveformQualityCheckerError.incompatibleFormats
        }

        let previewFrames = AVAudioFrameCount(
            min(refFormat.sampleRate * 4.0, 192_000)
        )

        let refMono = try readMono(
            file: referencePreview,
            frameCount: previewFrames
        )
        let encMono = try readMono(
            file: encodedPreview,
            frameCount: previewFrames + 4096
        )

        guard !refMono.isEmpty, !encMono.isEmpty else {
            throw WaveformQualityCheckerError.noSamples
        }

        let lag = estimateAlignment(
            reference: refMono,
            encoded: encMono,
            maxLag: 4096
        )

        let reference = try AVAudioFile(forReading: referenceWAV)
        let encoded = try AVAudioFile(forReading: encodedMP3)

        if lag >= 0 {
            encoded.framePosition = AVAudioFramePosition(lag)
        } else {
            reference.framePosition = AVAudioFramePosition(-lag)
        }

        let capacity: AVAudioFrameCount = 8192

        guard
            let refBuffer = AVAudioPCMBuffer(
                pcmFormat: reference.processingFormat,
                frameCapacity: capacity
            ),
            let encBuffer = AVAudioPCMBuffer(
                pcmFormat: encoded.processingFormat,
                frameCapacity: capacity
            )
        else {
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

            let frames = min(
                Int(refBuffer.frameLength),
                Int(encBuffer.frameLength)
            )

            if frames == 0 { break }

            guard
                let refChannels = refBuffer.floatChannelData,
                let encChannels = encBuffer.floatChannelData
            else {
                throw WaveformQualityCheckerError.cannotReadSamples
            }

            for channel in 0..<Int(refFormat.channelCount) {
                let x = refChannels[channel]
                let y = encChannels[channel]

                for index in 0..<frames {
                    let xd = Double(x[index])
                    let yd = Double(y[index])
                    let difference = xd - yd

                    sumXY += xd * yd
                    sumX2 += xd * xd
                    sumY2 += yd * yd
                    sumError2 += difference * difference
                    sampleCount += 1
                }
            }

            if
                refBuffer.frameLength < capacity ||
                encBuffer.frameLength < capacity
            {
                break
            }
        }

        guard
            sampleCount > 0,
            sumX2 > 0,
            sumY2 > 0
        else {
            throw WaveformQualityCheckerError.noSamples
        }

        let correlation =
            sumXY / sqrt(sumX2 * sumY2)
        let normalizedRMSE =
            sqrt(sumError2 / sumX2)

        return WaveformComparison(
            correlation: correlation,
            rmsErrorPercent: normalizedRMSE * 100,
            comparedSamples: sampleCount,
            alignmentFrames: lag
        )
    }

    private static func readMono(
        file: AVAudioFile,
        frameCount: AVAudioFrameCount
    ) throws -> [Float] {
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: frameCount
        ) else {
            throw WaveformQualityCheckerError.cannotReadSamples
        }

        try file.read(into: buffer, frameCount: frameCount)

        guard
            buffer.frameLength > 0,
            let channels = buffer.floatChannelData
        else {
            return []
        }

        let frames = Int(buffer.frameLength)
        let channelCount = Int(file.processingFormat.channelCount)
        var mono = [Float](repeating: 0, count: frames)

        for channel in 0..<channelCount {
            for index in 0..<frames {
                mono[index] += channels[channel][index]
            }
        }

        let scale = 1.0 / Float(max(1, channelCount))
        for index in mono.indices {
            mono[index] *= scale
        }

        return mono
    }

    private static func estimateAlignment(
        reference: [Float],
        encoded: [Float],
        maxLag: Int
    ) -> Int {
        let boundedLag = min(
            maxLag,
            max(0, min(reference.count, encoded.count) / 4)
        )

        guard boundedLag > 0 else { return 0 }

        var bestLag = 0
        var bestScore = -Double.infinity

        var lag = -boundedLag
        while lag <= boundedLag {
            let score = normalizedCorrelation(
                reference: reference,
                encoded: encoded,
                lag: lag,
                stride: 16,
                maxPairs: 12_000
            )

            if score > bestScore {
                bestScore = score
                bestLag = lag
            }

            lag += 8
        }

        let start = max(-boundedLag, bestLag - 12)
        let end = min(boundedLag, bestLag + 12)

        for refined in start...end {
            let score = normalizedCorrelation(
                reference: reference,
                encoded: encoded,
                lag: refined,
                stride: 2,
                maxPairs: 48_000
            )

            if score > bestScore {
                bestScore = score
                bestLag = refined
            }
        }

        return bestLag
    }

    private static func normalizedCorrelation(
        reference: [Float],
        encoded: [Float],
        lag: Int,
        stride: Int,
        maxPairs: Int
    ) -> Double {
        let refStart = lag < 0 ? -lag : 0
        let encStart = lag > 0 ? lag : 0

        let available = min(
            reference.count - refStart,
            encoded.count - encStart
        )

        guard available > stride else {
            return -Double.infinity
        }

        var sumXY = 0.0
        var sumX2 = 0.0
        var sumY2 = 0.0
        var pairs = 0
        var index = 0

        while index < available, pairs < maxPairs {
            let x = Double(reference[refStart + index])
            let y = Double(encoded[encStart + index])

            sumXY += x * y
            sumX2 += x * x
            sumY2 += y * y
            pairs += 1
            index += stride
        }

        guard sumX2 > 0, sumY2 > 0 else {
            return -Double.infinity
        }

        return sumXY / sqrt(sumX2 * sumY2)
    }
}
