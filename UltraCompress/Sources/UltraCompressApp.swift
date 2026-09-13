import SwiftUI
import UniformTypeIdentifiers
import UIKit
import PLzmaSDK
import Zip

@main
struct UltraCompressApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(.indigo)
        }
    }
}

enum OutputFormat: String, CaseIterable, Identifiable, Sendable {
    case sevenZ = "7z"
    case zip = "ZIP"
    var id: String { rawValue }
    var ext: String { self == .sevenZ ? "7z" : "zip" }
}

enum CompressionPreset: String, CaseIterable, Identifiable, Sendable {
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
            ZStack {
                LinearGradient(
                    colors: [Color.indigo.opacity(0.16), Color.purple.opacity(0.07), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        brandHeader
                        importCard
                        settingsCard
                        actionCard
                    }
                    .padding(16)
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $picker) {
            SystemDocumentPicker { urls in
                picker = false
                files = urls
                output = nil
                message = urls.isEmpty ? "No file selected." : "Selected \(urls.count) item(s). Ready to compress."
            }
            .ignoresSafeArea()
        }
        .onOpenURL { url in
            files = [url]
            output = nil
            message = "Received \(url.lastPathComponent) from Files."
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.indigo, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 66, height: 66)
                    .shadow(color: .indigo.opacity(0.28), radius: 14, y: 7)

                VStack(spacing: 2) {
                    Image(systemName: "arrow.down.to.line.compact")
                        .font(.system(size: 26, weight: .black))
                    Text("UC")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                }
                .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("ULTRACOMPRESS")
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .tracking(1.5)
                Text("Maximum ratio. Any file.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("INPUT", systemImage: "tray.and.arrow.down.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if !files.isEmpty {
                    Text("\(files.count) selected")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.indigo)
                }
            }

            Button { picker = true } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.indigo.opacity(0.10))
                            .frame(width: 44, height: 44)
                        Image(systemName: files.isEmpty ? "plus" : "arrow.triangle.2.circlepath")
                            .font(.headline.bold())
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(files.isEmpty ? "Choose files or folders" : "Change selection")
                            .font(.headline)
                        Text("IPA • ZIP • 7Z • documents • media • any file")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !files.isEmpty {
                Divider()
                ForEach(files, id: \.self) { url in
                    HStack(spacing: 10) {
                        Image(systemName: fileIcon(url))
                            .frame(width: 26)
                            .foregroundStyle(.indigo)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(fileSizeText(url))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "icloud.and.arrow.down")
                    .foregroundStyle(.secondary)
                Text("Large iCloud files can be selected without first making a duplicate. UltraCompress requests the file from its provider when compression starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .brandCard()
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("COMPRESSION ENGINE", systemImage: "cpu.fill")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Picker("Format", selection: $format) {
                ForEach(OutputFormat.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("Compression", selection: $preset) {
                ForEach(CompressionPreset.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: format == .sevenZ ? "bolt.badge.clock.fill" : "archivebox.fill")
                    .foregroundStyle(.indigo)
                Text(engineDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .brandCard()
    }

    private var actionCard: some View {
        VStack(spacing: 14) {
            Button {
                Task { await compress() }
            } label: {
                HStack {
                    Spacer()
                    if busy { ProgressView().tint(.white).padding(.trailing, 5) }
                    Image(systemName: busy ? "hourglass" : "arrow.down.to.line.compact")
                    Text(busy ? "Preparing / Compressing…" : "Compress Now")
                        .font(.headline.bold())
                    Spacer()
                }
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .disabled(files.isEmpty || busy)

            if let output {
                ShareLink(item: output) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Save or Share \(output.lastPathComponent)")
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 14))
            }

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .brandCard()
    }

    private var engineDescription: String {
        if format == .sevenZ {
            return preset == .maximum
                ? "LZMA2 level 9 + solid archive + fully compressed headers. This is the smallest-output preset and trades speed for ratio."
                : "LZMA2 solid archive with a lower compression level for faster processing."
        }
        return "ZIP uses Deflate for maximum compatibility. IPA files are already ZIP containers, so 7z is normally the better choice when storage size matters most."
    }

    private func fileIcon(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "ipa": return "apps.iphone"
        case "zip", "7z", "rar", "xz", "tar", "gz": return "archivebox.fill"
        default: return "doc.fill"
        }
    }

    private func fileSizeText(_ url: URL) -> String {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return "Cloud / provider item" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    @MainActor
    private func compress() async {
        busy = true
        output = nil
        message = "Preparing selected files. Cloud items may download now…"

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
                let delta = 100.0 * (1.0 - Double(packed) / Double(original))
                if delta >= 0 {
                    message = String(format: "Done • %@ → %@ • %.1f%% smaller", ByteCountFormatter.string(fromByteCount: original, countStyle: .file), ByteCountFormatter.string(fromByteCount: packed, countStyle: .file), delta)
                } else {
                    message = String(format: "Done • %@ → %@ • %.1f%% larger (source was already highly compressed)", ByteCountFormatter.string(fromByteCount: original, countStyle: .file), ByteCountFormatter.string(fromByteCount: packed, countStyle: .file), abs(delta))
                }
            } else {
                message = "Done."
            }
        } catch {
            message = "Failed: \(error.localizedDescription)"
        }
        busy = false
    }
}

private extension View {
    func brandCard() -> some View {
        self
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
    }
}

struct SystemDocumentPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        var types: [UTType] = [.item]
        if let ipa = UTType(filenameExtension: "ipa") { types.insert(ipa, at: 0) }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.allowsMultipleSelection = true
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick([])
        }
    }
}

enum ArchiveEngine {
    static func compress(_ urls: [URL], as format: OutputFormat, preset: CompressionPreset) throws -> URL {
        var scoped: [(URL, Bool)] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            scoped.append((url, access))
            try prepareProviderItem(url)
        }
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
                // IPA already is a ZIP container. Rewrapping it would add overhead without meaningful benefit.
                try FileManager.default.copyItem(at: urls[0], to: destination)
            } else {
                try makeZip(urls, destination: destination, level: preset.zipLevel)
            }
        }
        return destination
    }

    private static func prepareProviderItem(_ url: URL) throws {
        let fm = FileManager.default
        if fm.isUbiquitousItem(at: url) {
            try? fm.startDownloadingUbiquitousItem(at: url)
        }

        var coordinationError: NSError?
        var reachabilityError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { coordinatedURL in
            do {
                guard try coordinatedURL.checkResourceIsReachable() else {
                    throw ArchiveError.fileUnavailable(coordinatedURL.lastPathComponent)
                }
                let handle = try FileHandle(forReadingFrom: coordinatedURL)
                try handle.close()
            } catch {
                reachabilityError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let reachabilityError { throw reachabilityError }
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
        let archive = try ZipArchive(url: destination, mode: .overwrite)
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
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            } else if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
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
    case fileUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "Archive engine could not finish compression."
        case .fileUnavailable(let name):
            return "\(name) is not available locally yet. Keep UltraCompress open while iCloud or the file provider finishes downloading it, then try again."
        }
    }
}
