import Foundation
import ffmpegkit

enum FFmpegAudioConverterError: LocalizedError {
    case failed(String)
    case missingOutput

    var errorDescription: String? {
        switch self {
        case .failed(let details):
            return "FFmpeg MP3 conversion failed. \(details)"
        case .missingOutput:
            return "FFmpeg completed without creating the MP3 file."
        }
    }
}

enum FFmpegAudioConverter {
    static func wavToHighQualityMP3(_ input: URL) throws -> URL {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("ffmpeg-\(UUID().uuidString).mp3")

        try? FileManager.default.removeItem(at: output)

        let session = FFmpegKit.executeWithArguments([
            "-y",
            "-hide_banner",
            "-loglevel", "error",
            "-i", input.path,
            "-vn",
            "-c:a", "libmp3lame",
            "-b:a", "320k",
            "-compression_level", "0",
            "-ar", "48000",
            "-ac", "2",
            "-write_xing", "1",
            output.path
        ])

        guard ReturnCode.isSuccess(session.getReturnCode()) else {
            let details = session.getOutput().trimmingCharacters(in: .whitespacesAndNewlines)
            throw FFmpegAudioConverterError.failed(details.isEmpty ? "Unknown FFmpeg error." : details)
        }

        guard FileManager.default.fileExists(atPath: output.path) else {
            throw FFmpegAudioConverterError.missingOutput
        }

        return output
    }
}
