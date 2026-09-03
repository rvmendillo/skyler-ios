import Foundation
import AVFoundation
import SwiftMP3

enum AudioPipelineError: LocalizedError {
    case noAudioTrack
    case cannotReadPCM
    case youtubeID
    case noPlayableYouTubeAudio
    case allYouTubeResolversFailed

    var errorDescription: String? {
        switch self {
        case .noAudioTrack: return "No audio track was found."
        case .cannotReadPCM: return "The audio stream could not be decoded."
        case .youtubeID: return "That does not look like a valid YouTube URL."
        case .noPlayableYouTubeAudio: return "No compatible YouTube audio stream was returned."
        case .allYouTubeResolversFailed: return "YouTube audio could not be resolved right now. Try again or import the MP3 directly."
        }
    }
}

struct YouTubeMetadata: Sendable {
    let title: String
    let artist: String
    let downloadedURL: URL
}

enum AudioPipeline {
    static func importLocal(_ source: URL) async throws -> URL {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(source.pathExtension.isEmpty ? "audio" : source.pathExtension)

        try? FileManager.default.removeItem(at: temp)
        try FileManager.default.copyItem(at: source, to: temp)

        if source.pathExtension.lowercased() == "mp3" {
            return temp
        }
        return try await transcodeToMP3(temp)
    }

    static func transcodeToMP3(_ source: URL) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { throw AudioPipelineError.noAudioTrack }

        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw AudioPipelineError.cannotReadPCM }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? AudioPipelineError.cannotReadPCM }

        let encoder = MP3Encoder(options: MP3EncoderOptions(
            sampleRate: 44_100,
            bitrateKbps: 192,
            vbr: false,
            mode: .stereo,
            quality: 4
        ))
        var session = encoder.newSession()
        var encoded = Data()

        while let sample = output.copyNextSampleBuffer() {
            if let data = floatData(from: sample) {
                encoded.append(session.encode(samples: data))
            }
        }
        if reader.status == .failed {
            throw reader.error ?? AudioPipelineError.cannotReadPCM
        }
        encoded.append(session.flush())

        var fileData = Data()
        fileData.append(session.generateID3Tag())
        fileData.append(session.generateXingHeader())
        fileData.append(encoded)

        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("track-\(UUID().uuidString).mp3")
        try fileData.write(to: out, options: .atomic)
        return out
    }

    static func analyze(_ source: URL) async throws -> AudioAnalysis {
        let asset = AVURLAsset(url: source)
        let durationTime = try await asset.load(.duration)
        let duration = max(0.1, CMTimeGetSeconds(durationTime))
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { throw AudioPipelineError.noAudioTrack }

        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw AudioPipelineError.cannotReadPCM }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? AudioPipelineError.cannotReadPCM }

        let hop = 512
        let sampleRate = 44_100.0
        var envelope: [Double] = []
        var carry: [Float] = []

        while let sample = output.copyNextSampleBuffer() {
            guard let floats = floatData(from: sample) else { continue }
            var block = carry
            block.append(contentsOf: floats)
            var index = 0
            while index + hop <= block.count {
                let slice = block[index..<(index + hop)]
                var sum = 0.0
                for value in slice {
                    let x = Double(value)
                    sum += x * x
                }
                envelope.append(sqrt(sum / Double(hop)))
                index += hop
            }
            carry = index < block.count ? Array(block[index...]) : []
        }

        guard envelope.count > 8 else { throw AudioPipelineError.cannotReadPCM }

        var flux = Array(repeating: 0.0, count: envelope.count)
        for i in 1..<envelope.count {
            flux[i] = max(0, envelope[i] - envelope[i - 1])
        }

        let mean = flux.reduce(0, +) / Double(flux.count)
        let variance = flux.reduce(0) { $0 + pow($1 - mean, 2) } / Double(flux.count)
        let threshold = mean + sqrt(variance) * 0.75
        let envRate = sampleRate / Double(hop)

        var onsets: [(time: Double, strength: Double)] = []
        if flux.count > 2 {
            for i in 1..<(flux.count - 1) {
                if flux[i] > threshold && flux[i] >= flux[i - 1] && flux[i] >= flux[i + 1] {
                    onsets.append((Double(i) / envRate, flux[i]))
                }
            }
        }

        let minBPM = 70.0
        let maxBPM = 200.0
        let minLag = max(1, Int(envRate * 60.0 / maxBPM))
        let maxLag = min(flux.count / 2, Int(envRate * 60.0 / minBPM))
        var bestLag = Int(envRate * 60.0 / 120.0)
        var bestScore = -Double.infinity

        if maxLag > minLag {
            for lag in minLag...maxLag {
                var score = 0.0
                var i = lag
                while i < flux.count {
                    score += flux[i] * flux[i - lag]
                    i += 1
                }
                if score > bestScore {
                    bestScore = score
                    bestLag = lag
                }
            }
        }

        var bpm = 60.0 * envRate / Double(max(1, bestLag))
        while bpm < 85 { bpm *= 2 }
        while bpm > 190 { bpm /= 2 }

        let beat = 60.0 / bpm
        let firstWindow = onsets.filter { $0.time < min(duration, beat * 2.0) }
        let firstBeat = firstWindow.max(by: { $0.strength < $1.strength })?.time ?? 0.0

        return AudioAnalysis(
            duration: duration,
            bpm: bpm,
            firstBeat: firstBeat,
            onsets: onsets.map(\.time),
            strengths: onsets.map(\.strength)
        )
    }

    static func importYouTube(_ rawURL: String) async throws -> YouTubeMetadata {
        guard let videoID = youtubeVideoID(rawURL) else { throw AudioPipelineError.youtubeID }

        let instances = [
            "https://pipedapi.kavin.rocks",
            "https://pipedapi.tokhmi.xyz",
            "https://piped-api.lunar.icu",
            "https://piped-api.garudalinux.org",
            "https://api-piped.mha.fi",
            "https://pipedapi.rivo.lol",
            "https://pipedapi.colinslegacy.com"
        ]

        for base in instances {
            do {
                guard let endpoint = URL(string: "\(base)/streams/\(videoID)") else { continue }
                var request = URLRequest(url: endpoint)
                request.timeoutInterval = 12
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
                let info = try JSONDecoder().decode(PipedStreams.self, from: data)

                let stream = info.audioStreams
                    .filter { ($0.mimeType ?? "").contains("audio/mp4") }
                    .sorted { ($0.bitrate ?? 0) > ($1.bitrate ?? 0) }
                    .first
                    ?? info.audioStreams.sorted { ($0.bitrate ?? 0) > ($1.bitrate ?? 0) }.first

                guard let stream, let streamURL = URL(string: stream.url) else {
                    throw AudioPipelineError.noPlayableYouTubeAudio
                }

                var audioRequest = URLRequest(url: streamURL)
                audioRequest.timeoutInterval = 45
                let (audioData, audioResponse) = try await URLSession.shared.data(for: audioRequest)
                guard let audioHTTP = audioResponse as? HTTPURLResponse,
                      (200..<300).contains(audioHTTP.statusCode),
                      !audioData.isEmpty else { continue }

                let ext = (stream.mimeType ?? "").contains("mp4") ? "m4a" : "audio"
                let downloaded = FileManager.default.temporaryDirectory
                    .appendingPathComponent("youtube-\(videoID)")
                    .appendingPathExtension(ext)
                try audioData.write(to: downloaded, options: .atomic)
                let mp3 = try await transcodeToMP3(downloaded)
                return YouTubeMetadata(
                    title: info.title ?? "YouTube \(videoID)",
                    artist: info.uploader ?? "YouTube",
                    downloadedURL: mp3
                )
            } catch {
                continue
            }
        }
        throw AudioPipelineError.allYouTubeResolversFailed
    }

    private static func floatData(from sample: CMSampleBuffer) -> [Float]? {
        guard let buffer = CMSampleBufferGetDataBuffer(sample) else { return nil }
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
        guard status == kCMBlockBufferNoErr, let pointer, totalLength > 0 else { return nil }
        let count = totalLength / MemoryLayout<Float>.size
        let floats = UnsafeRawPointer(pointer).assumingMemoryBound(to: Float.self)
        return Array(UnsafeBufferPointer(start: floats, count: count))
    }

    private static func youtubeVideoID(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return nil }
        if url.host?.contains("youtu.be") == true {
            return url.pathComponents.dropFirst().first
        }
        if url.host?.contains("youtube.com") == true || url.host?.contains("music.youtube.com") == true {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let value = components.queryItems?.first(where: { $0.name == "v" })?.value,
               !value.isEmpty {
                return value
            }
            let parts = url.pathComponents
            if let index = parts.firstIndex(where: { $0 == "shorts" || $0 == "embed" }),
               parts.indices.contains(index + 1) {
                return parts[index + 1]
            }
        }
        return nil
    }
}

private struct PipedStreams: Decodable {
    let title: String?
    let uploader: String?
    let audioStreams: [PipedAudioStream]
}

private struct PipedAudioStream: Decodable {
    let url: String
    let mimeType: String?
    let bitrate: Int?
}
