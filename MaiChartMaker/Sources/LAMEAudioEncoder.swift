import Foundation
import AVFoundation
import LAME

enum LAMEAudioEncoderError: LocalizedError {
    case noAudioTrack
    case cannotReadPCM
    case encoderInitFailed
    case encoderConfigurationFailed(Int32)
    case encodeFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "The source does not contain a readable audio track."
        case .cannotReadPCM:
            return "Could not decode PCM samples for MP3 encoding."
        case .encoderInitFailed:
            return "Could not initialize the LAME MP3 encoder."
        case .encoderConfigurationFailed(let code):
            return "LAME encoder configuration failed (code \(code))."
        case .encodeFailed(let code):
            return "LAME MP3 encoding failed (code \(code))."
        }
    }
}

enum LAMEAudioEncoder {
    static func encodeToMP3(
        source: URL,
        bitrateKbps: Int32 = 320
    ) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            throw LAMEAudioEncoderError.noAudioTrack
        }

        let sourceRate =
            (try? AVAudioFile(forReading: source).processingFormat.sampleRate)
            ?? 48_000
        let supported = [32_000.0, 44_100.0, 48_000.0]
        let outputRate = supported.min {
            abs($0 - sourceRate) < abs($1 - sourceRate)
        } ?? 48_000

        return try await Task.detached(priority: .userInitiated) {
            let reader = try AVAssetReader(asset: asset)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: outputRate,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]

            let output = AVAssetReaderTrackOutput(
                track: track,
                outputSettings: settings
            )
            output.alwaysCopiesSampleData = false

            guard reader.canAdd(output) else {
                throw LAMEAudioEncoderError.cannotReadPCM
            }

            reader.add(output)
            guard reader.startReading() else {
                throw reader.error ?? LAMEAudioEncoderError.cannotReadPCM
            }

            guard let gfp = lame_init() else {
                throw LAMEAudioEncoderError.encoderInitFailed
            }
            defer { lame_close(gfp) }

            lame_set_num_channels(gfp, 2)
            lame_set_in_samplerate(gfp, Int32(outputRate))
            lame_set_out_samplerate(gfp, Int32(outputRate))
            lame_set_brate(gfp, bitrateKbps)
            lame_set_quality(gfp, 0)
            lame_set_bWriteVbrTag(gfp, 0)

            let initCode = lame_init_params(gfp)
            guard initCode >= 0 else {
                throw LAMEAudioEncoderError.encoderConfigurationFailed(initCode)
            }

            let outURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("lame-\(UUID().uuidString).mp3")
            FileManager.default.createFile(
                atPath: outURL.path,
                contents: nil
            )
            let handle = try FileHandle(forWritingTo: outURL)
            defer { try? handle.close() }

            while let sampleBuffer = output.copyNextSampleBuffer() {
                guard let floats = interleavedFloatData(from: sampleBuffer) else {
                    continue
                }

                let frames = floats.count / 2
                guard frames > 0 else { continue }

                let mp3Capacity = Int(ceil(1.25 * Double(frames))) + 7200
                var mp3 = [UInt8](repeating: 0, count: mp3Capacity)

                let written: Int32 = floats.withUnsafeBufferPointer { pcm in
                    mp3.withUnsafeMutableBufferPointer { out in
                        lame_encode_buffer_interleaved_ieee_float(
                            gfp,
                            pcm.baseAddress,
                            Int32(frames),
                            out.baseAddress,
                            Int32(mp3Capacity)
                        )
                    }
                }

                guard written >= 0 else {
                    throw LAMEAudioEncoderError.encodeFailed(written)
                }

                if written > 0 {
                    try handle.write(
                        contentsOf: Data(mp3.prefix(Int(written)))
                    )
                }
            }

            if reader.status == .failed {
                throw reader.error ?? LAMEAudioEncoderError.cannotReadPCM
            }

            var flush = [UInt8](repeating: 0, count: 7200)
            let flushed = flush.withUnsafeMutableBufferPointer {
                lame_encode_flush(gfp, $0.baseAddress, Int32($0.count))
            }

            guard flushed >= 0 else {
                throw LAMEAudioEncoderError.encodeFailed(flushed)
            }

            if flushed > 0 {
                try handle.write(
                    contentsOf: Data(flush.prefix(Int(flushed)))
                )
            }

            return outURL
        }.value
    }

    private static func interleavedFloatData(
        from sample: CMSampleBuffer
    ) -> [Float]? {
        guard let buffer = CMSampleBufferGetDataBuffer(sample) else {
            return nil
        }

        var lengthAtOffset = 0
        var totalLength = 0
        var pointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(
            buffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &pointer
        )

        guard status == kCMBlockBufferNoErr,
              let pointer,
              totalLength > 0 else {
            return nil
        }

        let count = totalLength / MemoryLayout<Float>.size
        let floats = UnsafeRawPointer(pointer)
            .assumingMemoryBound(to: Float.self)

        return Array(
            UnsafeBufferPointer(start: floats, count: count)
        )
    }
}
