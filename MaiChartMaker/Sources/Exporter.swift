import Foundation
import ZIPFoundation

enum ChartExporter {
    static func makeSongFolder(
        title: String,
        artist: String,
        audioURL: URL,
        analysis: AudioAnalysis,
        charts: [GeneratedChart],
        originalAudioURL: URL? = nil
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaiChartExport-\(UUID().uuidString)", isDirectory: true)
        let folderName = safeFilename(title.isEmpty ? "Untitled" : title)
        let song = root.appendingPathComponent(folderName, isDirectory: true)

        try FileManager.default.createDirectory(at: song, withIntermediateDirectories: true)

        // AstroDX-compatible playback copy.
        let trackName = "track.mp3"
        let maidata = ChartGenerator.maidata(
            title: title,
            artist: artist,
            analysis: analysis,
            charts: charts,
            trackFilename: trackName
        )
        try maidata.write(
            to: song.appendingPathComponent("maidata.txt"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.copyItem(
            at: audioURL,
            to: song.appendingPathComponent(trackName)
        )

        // WAV is a render/reference master only and is intentionally never
        // placed in the AstroDX export. For imported compressed originals we
        // may retain the source beside track.mp3.
        if let originalAudioURL,
           originalAudioURL.standardizedFileURL != audioURL.standardizedFileURL {
            let ext = originalAudioURL.pathExtension.lowercased()

            if !ext.isEmpty, ext != "wav" {
                let originalName = "source-original.\(ext)"
                try? FileManager.default.copyItem(
                    at: originalAudioURL,
                    to: song.appendingPathComponent(originalName)
                )
            }
        }

        return song
    }

    static func makeZip(from songFolder: URL) throws -> URL {
        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(songFolder.lastPathComponent)
            .appendingPathExtension("zip")
        try? FileManager.default.removeItem(at: zipURL)
        try FileManager.default.zipItem(
            at: songFolder,
            to: zipURL,
            shouldKeepParent: true,
            compressionMethod: .deflate
        )
        return zipURL
    }

    static func copySongFolder(_ songFolder: URL, into destination: URL) throws -> URL {
        let access = destination.startAccessingSecurityScopedResource()
        defer { if access { destination.stopAccessingSecurityScopedResource() } }

        let target = destination.appendingPathComponent(songFolder.lastPathComponent, isDirectory: true)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: songFolder, to: target)
        return target
    }

    private static func safeFilename(_ value: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = value.components(separatedBy: bad).joined(separator: "_")
        return String(cleaned.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
