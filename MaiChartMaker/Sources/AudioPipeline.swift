import Foundation
import AVFoundation

enum AudioPipelineError: LocalizedError {
    case noAudioTrack
    case cannotReadPCM
    case youtubeID
    case noPlayableYouTubeAudio
    case allYouTubeResolversFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "The selected file does not contain a readable audio track."
        case .cannotReadPCM:
            return "The audio stream could not be decoded on this iPhone."
        case .youtubeID:
            return "That does not look like a valid YouTube or youtu.be URL."
        case .noPlayableYouTubeAudio:
            return "The YouTube resolver returned no iPhone-compatible audio stream."
        case .allYouTubeResolversFailed(let detail):
            return "YouTube audio could not be resolved. \(detail)"
        }
    }
}

struct ImportedAudio: Sendable {
    let analysisURL: URL
    let exportURL: URL
    let originalURL: URL
}

struct YouTubeMetadata: Sendable {
    let title: String
    let artist: String
    let analysisURL: URL
    let exportURL: URL
    let originalURL: URL
}

struct AnalyzedAudio: Sendable {
    let analysis: AudioAnalysis
    let pianoGameNotes: [PianoGameNote]
}

enum AudioPipeline {
    static func importLocal(_ source: URL) async throws -> ImportedAudio {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }

        // Validate the file itself instead of trusting its extension/UTType.
        let sourceAsset = AVURLAsset(url: source)
        let sourceTracks = try await sourceAsset.loadTracks(withMediaType: .audio)
        guard !sourceTracks.isEmpty else { throw AudioPipelineError.noAudioTrack }

        let ext = source.pathExtension.isEmpty ? "audio" : source.pathExtension
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)

        try? FileManager.default.removeItem(at: temp)
        try FileManager.default.copyItem(at: source, to: temp)

        if source.pathExtension.lowercased() == "mp3" {
            return ImportedAudio(analysisURL: temp, exportURL: temp, originalURL: temp)
        }

        // Analyze the untouched source. Only the compatibility copy is encoded.
        let compatible = try await transcodeToMP3(temp)
        return ImportedAudio(analysisURL: temp, exportURL: compatible, originalURL: temp)
    }

    static func transcodeToMP3(_ source: URL) async throws -> URL {
        try await LAMEAudioEncoder.encodeToMP3(
            source: source,
            bitrateKbps: 320
        )
    }

    static func analyze(_ source: URL) async throws -> AudioAnalysis {
        try await analyzeWithTranscription(source).analysis
    }

    static func analyzeWithTranscription(_ source: URL) async throws -> AnalyzedAudio {
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

        let rawStrengths = onsets.map(\.strength)
        let maxStrength = rawStrengths.max() ?? 1
        let normalizedStrengths = rawStrengths.map {
            maxStrength > 0 ? min(1, max(0, $0 / maxStrength)) : 0
        }

        let secondsPerBeat = 60.0 / max(1, bpm)
        var drumBeats: [Double] = []
        var drumStrengths: [Double] = []

        for (index, onset) in onsets.enumerated() {
            let normalized = normalizedStrengths.indices.contains(index)
                ? normalizedStrengths[index]
                : 0

            guard normalized >= 0.34 else { continue }
            guard onset.time >= max(0, firstBeat - 0.08) else { continue }

            let beatPosition =
                max(0, (onset.time - firstBeat) / secondsPerBeat)
            drumBeats.append(
                (beatPosition * 4.0).rounded() / 4.0
            )
            drumStrengths.append(normalized)
        }

        let transcription: AudioTranscriptionResult?
        do {
            transcription = try await BasicPitchAudioTranscriber.shared.transcribe(
                audioURL: source,
                bpm: bpm,
                firstBeat: firstBeat
            )
        } catch {
            transcription = nil
        }

        let durationBeats =
            max(0.25, (duration - firstBeat) / secondsPerBeat)

        let analysis = AudioAnalysis(
            duration: duration,
            bpm: bpm,
            firstBeat: firstBeat,
            onsets: onsets.map(\.time),
            strengths: normalizedStrengths,
            beatPositions: nil,
            durationBeats: durationBeats,
            tempoMap: [TempoPoint(beat: 0, bpm: bpm)],
            exactScoreTiming: false,
            drumBeatPositions: drumBeats,
            drumStrengths: drumStrengths,
            drumNoteNumbers: [],
            melodyBeatPositions:
                transcription?.melodyBeatPositions ?? [],
            melodyPitches:
                transcription?.melodyPitches ?? [],
            melodyStrengths:
                transcription?.melodyStrengths ?? []
        )

        return AnalyzedAudio(
            analysis: analysis,
            pianoGameNotes: transcription?.pianoGameNotes ?? []
        )
    }

    static func importYouTube(_ rawURL: String) async throws -> YouTubeMetadata {
        guard let videoID = youtubeVideoID(rawURL) else { throw AudioPipelineError.youtubeID }

        var failures: [String] = []

        do {
            return try await importYouTubeViaInvidious(videoID: videoID)
        } catch {
            failures.append("Invidious: \(error.localizedDescription)")
        }

        do {
            return try await importYouTubeViaPiped(videoID: videoID)
        } catch {
            failures.append("Piped: \(error.localizedDescription)")
        }

        throw AudioPipelineError.allYouTubeResolversFailed(
            failures.joined(separator: " • ") + ". You can still import the MP3/M4A from Files."
        )
    }

    private static func importYouTubeViaInvidious(videoID: String) async throws -> YouTubeMetadata {
        let instances = [
            "https://inv.nadeko.net",
            "https://invidious.nerdvpn.de",
            "https://yt.chocolatemoo53.com",
            "https://invidious.tiekoetter.com"
        ]

        var lastError: Error = AudioPipelineError.noPlayableYouTubeAudio

        for base in instances {
            do {
                guard let apiURL = URL(string: "\(base)/api/v1/videos/\(videoID)") else { continue }
                var request = URLRequest(url: apiURL)
                request.timeoutInterval = 15
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("MaiChartMaker/1.1 iOS", forHTTPHeaderField: "User-Agent")

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else { continue }

                let info = try JSONDecoder().decode(InvidiousVideo.self, from: data)

                let audioFormats = info.adaptiveFormats
                    .filter { $0.type.lowercased().contains("audio/") }
                    .sorted { bitrateValue($0.bitrate) > bitrateValue($1.bitrate) }

                let preferred = audioFormats.first(where: {
                    $0.type.lowercased().contains("audio/mp4") ||
                    $0.container?.lowercased() == "m4a"
                }) ?? audioFormats.first

                guard let format = preferred else {
                    lastError = AudioPipelineError.noPlayableYouTubeAudio
                    continue
                }

                // Prefer the instance's local proxy so the media is fetched from
                // the same resolver IP; this avoids many expiring/403 stream URLs.
                let localURL = makeLatestVersionURL(base: base, videoID: videoID, itag: format.itag)
                let downloaded: URL

                if let localURL {
                    do {
                        downloaded = try await downloadMedia(localURL, extension: "m4a")
                    } catch {
                        guard let direct = URL(string: format.url) else { throw error }
                        downloaded = try await downloadMedia(direct, extension: "m4a")
                    }
                } else {
                    guard let direct = URL(string: format.url) else {
                        throw AudioPipelineError.noPlayableYouTubeAudio
                    }
                    downloaded = try await downloadMedia(direct, extension: "m4a")
                }

                let mp3 = try await transcodeToMP3(downloaded)
                return YouTubeMetadata(
                    title: info.title ?? "YouTube \(videoID)",
                    artist: info.author ?? "YouTube",
                    analysisURL: downloaded,
                    exportURL: mp3,
                    originalURL: downloaded
                )
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError
    }

    private static func importYouTubeViaPiped(videoID: String) async throws -> YouTubeMetadata {
        let instances = [
            "https://pipedapi.kavin.rocks",
            "https://pipedapi.tokhmi.xyz",
            "https://piped-api.lunar.icu",
            "https://piped-api.garudalinux.org",
            "https://api-piped.mha.fi",
            "https://pipedapi.rivo.lol",
            "https://pipedapi.colinslegacy.com"
        ]

        var lastError: Error = AudioPipelineError.noPlayableYouTubeAudio

        for base in instances {
            do {
                guard let endpoint = URL(string: "\(base)/streams/\(videoID)") else { continue }
                var request = URLRequest(url: endpoint)
                request.timeoutInterval = 12
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("MaiChartMaker/1.1 iOS", forHTTPHeaderField: "User-Agent")

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else { continue }

                let info = try JSONDecoder().decode(PipedStreams.self, from: data)
                let streams = info.audioStreams.sorted { ($0.bitrate ?? 0) > ($1.bitrate ?? 0) }

                let stream = streams.first(where: {
                    ($0.mimeType ?? "").lowercased().contains("audio/mp4")
                }) ?? streams.first

                guard let stream, let streamURL = URL(string: stream.url) else {
                    throw AudioPipelineError.noPlayableYouTubeAudio
                }

                let ext = (stream.mimeType ?? "").lowercased().contains("mp4") ? "m4a" : "audio"
                let downloaded = try await downloadMedia(streamURL, extension: ext)
                let mp3 = try await transcodeToMP3(downloaded)

                return YouTubeMetadata(
                    title: info.title ?? "YouTube \(videoID)",
                    artist: info.uploader ?? "YouTube",
                    analysisURL: downloaded,
                    exportURL: mp3,
                    originalURL: downloaded
                )
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError
    }

    private static func downloadMedia(_ url: URL, extension ext: String) async throws -> URL {
        var request = URLRequest(url: url)
        request.timeoutInterval = 90
        request.setValue("MaiChartMaker/1.1 iOS", forHTTPHeaderField: "User-Agent")
        request.setValue("audio/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let (temporary, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("youtube-\(UUID().uuidString)")
            .appendingPathExtension(ext)

        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: temporary, to: target)
        return target
    }

    private static func makeLatestVersionURL(base: String, videoID: String, itag: String) -> URL? {
        guard var components = URLComponents(string: "\(base)/latest_version") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "id", value: videoID),
            URLQueryItem(name: "itag", value: itag),
            URLQueryItem(name: "local", value: "true")
        ]
        return components.url
    }

    private static func bitrateValue(_ value: String?) -> Int {
        Int(value ?? "") ?? 0
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
            if let index = parts.firstIndex(where: { $0 == "shorts" || $0 == "embed" || $0 == "live" }),
               parts.indices.contains(index + 1) {
                return parts[index + 1]
            }
        }
        return nil
    }
}

private struct InvidiousVideo: Decodable {
    let title: String?
    let author: String?
    let adaptiveFormats: [InvidiousFormat]
}

private struct InvidiousFormat: Decodable {
    let url: String
    let itag: String
    let type: String
    let bitrate: String?
    let container: String?
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
