import SwiftUI
import UniformTypeIdentifiers
import PLzmaSDK
import Zip

@main
struct UltraCompressApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case sevenZ = "7z"
    case zip = "ZIP"
    var id: String { rawValue }
    var ext: String { self == .sevenZ ? "7z" : "zip" }
}

enum CompressionPreset: String, CaseIterable, Identifiable {
    case maximum = "Maximum"
    case balanced = "Balanced"
    case fast = "Fast"
    var id: String { rawValue }
    var level: UInt8 {
        switch self { case .maximum: 9; case .balanced: 6; case .fast: 1 }
    }
    var zipLevel: CompressionLevel {
        switch self { case .maximum: .best; case .balanced: .default; case .fast: .fastest }
    }
}

struct ContentView: View {
    @State private var picker = false
    @State private var files: [URL] = []
    @State private var format: OutputFormat = .sevenZ
    @State private var preset: CompressionPreset = .maximum
    @State private var busy = false
    @State private var output: URL?
    @State private var message = "Choose any file or folder."

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { picker = true } label: {
                        Label(files.isEmpty ? "Choose files / folders" : "Change selection", systemImage: "folder.badge.plus")
                    }
                    if !files.isEmpty {
                        ForEach(files, id: \.self) { url in
                            HStack { Image(systemName: "doc"); Text(url.lastPathComponent).lineLimit(1); Spacer() }
                        }
                    }
                }

                Section("Output") {
                    Picker("Format", selection: $format) {
                        ForEach(OutputFormat.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Compression", selection: $preset) {
                        ForEach(CompressionPreset.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if format == .sevenZ && preset == .maximum {
                        Text("LZMA2 level 9 + solid archive + compressed headers. Best ratio, slower compression.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if format == .zip {
                        Text("For a single IPA, ZIP mode preserves its existing ZIP bytes instead of recompressing them unnecessarily.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        Task { await compress() }
                    } label: {
                        HStack {
                            Spacer()
                            if busy { ProgressView().padding(.trailing, 6) }
                            Text(busy ? "Compressing…" : "Compress")
                            Spacer()
                        }
                    }
                    .disabled(files.isEmpty || busy)

                    if let output {
                        ShareLink(item: output) {
                            Label("Share / Save \(output.lastPathComponent)", systemImage: "square.and.arrow.up")
                        }
                    }
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("UltraCompress")
        }
        .fileImporter(isPresented: $picker, allowedContentTypes: [.item, .folder], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): files = urls; output = nil; message = "Selected \(urls.count) item(s)."
            case .failure(let error): message = error.localizedDescription
            }
        }
    }

    @MainActor
    private func compress() async {
        busy = true; output = nil; message = "Compressing…"
        let selected = files
        let chosenFormat = format
        let chosenPreset = preset
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try ArchiveEngine.compress(selected, as: chosenFormat, preset: chosenPreset)
            }.value
            output = result
            let original = ArchiveEngine.totalSize(of: selected)
            let packed = (try? result.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            if original > 0 {
                let saved = max(0, 100.0 * (1.0 - Double(packed) / Double(original)))
                message = String(format: "Done • %@ → %@ • %.1f%% smaller", ByteCountFormatter.string(fromByteCount: original, countStyle: .file), ByteCountFormatter.string(fromByteCount: packed, countStyle: .file), saved)
            } else { message = "Done." }
        } catch {
            message = "Failed: \(error.localizedDescription)"
        }
        busy = false
    }
}

enum ArchiveEngine {
    static func compress(_ urls: [URL], as format: OutputFormat, preset: CompressionPreset) throws -> URL {
        var scoped: [(URL, Bool)] = []
        for url in urls { scoped.append((url, url.startAccessingSecurityScopedResource())) }
        defer { for (url, access) in scoped where access { url.stopAccessingSecurityScopedResource() } }

        let base = urls.count == 1 ? urls[0].deletingPathExtension().lastPathComponent : "Archive"
        let safeBase = base.isEmpty ? "Archive" : base
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeBase)-Ultra.\(format.ext)")
        try? FileManager.default.removeItem(at: destination)

        switch format {
        case .sevenZ:
            try make7z(urls, destination: destination, level: preset.level)
        case .zip:
            if urls.count == 1 && urls[0].pathExtension.lowercased() == "ipa" {
                try FileManager.default.copyItem(at: urls[0], to: destination)
            } else {
                try makeZip(urls, destination: destination, level: preset.zipLevel)
            }
        }
        return destination
    }

    private static func make7z(_ urls: [URL], destination: URL, level: UInt8) throws {
        let stream = try OutStream(path: Path(destination.path))
        let encoder = try PLzmaSDK.Encoder(stream: stream, fileType: .sevenZ, method: .LZMA2)
        try encoder.setCompressionLevel(level)
        try encoder.setShouldCreateSolidArchive(true)
        try encoder.setShouldCompressHeader(true)
        try encoder.setShouldCompressHeaderFull(true)
        for url in urls {
            try encoder.add(path: Path(url.path), mode: .default, archivePath: Path(url.lastPathComponent))
        }
        guard try encoder.open(), try encoder.compress() else { throw ArchiveError.compressionFailed }
    }

    private static func makeZip(_ urls: [URL], destination: URL, level: CompressionLevel) throws {
        let archive = try ZipArchive(url: destination)
        for url in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                let root = url.lastPathComponent
                let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                while let child = enumerator?.nextObject() as? URL {
                    let values = try child.resourceValues(forKeys: [.isRegularFileKey])
                    guard values.isRegularFile == true else { continue }
                    let relative = child.path.replacingOccurrences(of: url.path + "/", with: "")
                    let data = try Data(contentsOf: child, options: .mappedIfSafe)
                    try archive.addFile(at: root + "/" + relative, data: data, compression: level)
                }
            } else {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                try archive.addFile(at: url.lastPathComponent, data: data, compression: level)
            }
        }
        try archive.finalize()
    }

    static func totalSize(of urls: [URL]) -> Int64 {
        var total: Int64 = 0
        for url in urls {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize { total += Int64(size) }
            else if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
                while let child = enumerator.nextObject() as? URL {
                    if let s = try? child.resourceValues(forKeys: [.fileSizeKey]).fileSize { total += Int64(s) }
                }
            }
        }
        return total
    }
}

enum ArchiveError: LocalizedError {
    case compressionFailed
    var errorDescription: String? { "Archive engine could not finish compression." }
}
