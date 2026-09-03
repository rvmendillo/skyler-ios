import Foundation
import ZIPFoundation

enum ChartExporter {
    static func makeSongFolder(
        title: String,
        artist: String,
        audioURL: URL,
        analysis: AudioAnalysis,
        charts: [GeneratedChart]
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaiChartExport-\(UUID().uuidString)", isDirectory: true)
        let folderName = safeFilename(title.isEmpty ? "Untitled" : title)
        let song = root.appendingPathComponent(folderName, isDirectory: true)

        try FileManager.default.createDirectory(at: song, withIntermediateDirectories: true)
        let maidata = ChartGenerator.maidata(title: title, artist: artist, analysis: analysis, charts: charts)
        try maidata.write(to: song.appendingPathComponent("maidata.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.copyItem(at: audioURL, to: song.appendingPathComponent("track.mp3"))
        return song
    }

    static func makeZip(from songFolder: URL) throws -> URL {
        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(songFolder.lastPathComponent)
            .appendingPathExtension("zip")
        try? FileManager.default.removeItem(at: zipURL)

        guard let archive = Archive(url: zipURL, accessMode: .create) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let parent = songFolder.deletingLastPathComponent()
        let enumerator = FileManager.default.enumerator(
            at: songFolder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let file = enumerator?.nextObject() as? URL {
            let relative = file.path.replacingOccurrences(of: parent.path + "/", with: "")
            let values = try file.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                try archive.addEntry(with: relative + "/", type: .directory, uncompressedSize: 0, provider: { _, _ in Data() })
            } else {
                try archive.addEntry(with: relative, relativeTo: parent)
            }
        }
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
