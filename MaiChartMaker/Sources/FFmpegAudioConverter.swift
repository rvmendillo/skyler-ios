import Foundation
import Darwin

enum FFmpegAudioConverterError: LocalizedError {
    case runtimeUnavailable(String)
    case failed(Int32)
    case missingOutput

    var errorDescription: String? {
        switch self {
        case .runtimeUnavailable(let details):
            return "FFmpeg could not be loaded on this device. \(details)"
        case .failed(let code):
            return "FFmpeg/libmp3lame conversion failed with code \(code)."
        case .missingOutput:
            return "FFmpeg completed without creating the MP3 file."
        }
    }
}

private enum DynamicFFmpegRuntime {
    typealias ExecuteFunction = @convention(c) (
        Int32,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32

    private static let lock = NSLock()
    private static var handles: [UnsafeMutableRawPointer] = []
    private static var executeFunction: ExecuteFunction?

    static func execute(arguments: [String]) throws -> Int32 {
        let function = try loadIfNeeded()

        var argv: [UnsafeMutablePointer<CChar>?] = (["ffmpeg"] + arguments).map {
            strdup($0)
        }
        defer {
            for pointer in argv {
                if let pointer { free(pointer) }
            }
        }

        return argv.withUnsafeMutableBufferPointer { buffer in
            function(Int32(buffer.count), buffer.baseAddress)
        }
    }

    private static func loadIfNeeded() throws -> ExecuteFunction {
        lock.lock()
        defer { lock.unlock() }

        if let executeFunction {
            return executeFunction
        }

        guard let frameworkRoot = Bundle.main.privateFrameworksURL else {
            throw FFmpegAudioConverterError.runtimeUnavailable(
                "The app bundle does not contain a Frameworks directory."
            )
        }

        let names = [
            "libavutil",
            "libswresample",
            "libswscale",
            "libavcodec",
            "libavformat",
            "libavfilter",
            "libavdevice",
            "ffmpegkit"
        ]

        var loaded: [UnsafeMutableRawPointer] = []

        for name in names {
            let binary = frameworkRoot
                .appendingPathComponent("\(name).framework", isDirectory: true)
                .appendingPathComponent(name)

            guard FileManager.default.fileExists(atPath: binary.path) else {
                throw FFmpegAudioConverterError.runtimeUnavailable(
                    "Missing \(name).framework."
                )
            }

            dlerror()
            guard let handle = dlopen(binary.path, RTLD_NOW | RTLD_GLOBAL) else {
                let details = dlerror().map { String(cString: $0) }
                    ?? "Unknown dynamic-loader error."
                throw FFmpegAudioConverterError.runtimeUnavailable(
                    "\(name): \(details)"
                )
            }

            loaded.append(handle)
        }

        guard let ffmpegHandle = loaded.last else {
            throw FFmpegAudioConverterError.runtimeUnavailable(
                "FFmpeg runtime did not load."
            )
        }

        dlerror()
        guard let symbol = dlsym(ffmpegHandle, "ffmpeg_execute") else {
            let details = dlerror().map { String(cString: $0) }
                ?? "ffmpeg_execute symbol was not found."
            throw FFmpegAudioConverterError.runtimeUnavailable(details)
        }

        let function = unsafeBitCast(symbol, to: ExecuteFunction.self)
        handles = loaded
        executeFunction = function
        return function
    }
}

enum FFmpegAudioConverter {
    static func wavToHighQualityMP3(_ input: URL) throws -> URL {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("ffmpeg-\(UUID().uuidString).mp3")

        try? FileManager.default.removeItem(at: output)

        let code = try DynamicFFmpegRuntime.execute(arguments: [
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

        guard code == 0 else {
            throw FFmpegAudioConverterError.failed(code)
        }

        guard FileManager.default.fileExists(atPath: output.path) else {
            throw FFmpegAudioConverterError.missingOutput
        }

        return output
    }
}
