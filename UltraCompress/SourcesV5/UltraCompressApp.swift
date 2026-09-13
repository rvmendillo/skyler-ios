import SwiftUI
import UniformTypeIdentifiers
import UIKit
import Foundation
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
        switch self {
        case .maximum: return 9
        case .balanced: return 6
        case .fast: return 1
        }
    }

    var zipLevel: CompressionLevel {
        switch self {
        case .maximum: return .best
        case .balanced: return .default
        case .fast: return .fastest
        }
    }
}

struct ContentView: View {
    @State private var showPicker = false
    @State private var showShareSheet = false
    @State private var selected: URL?
    @State private var output: URL?
    @State private var format: OutputFormat = .sevenZ
    @State private var preset: CompressionPreset = .maximum
    @State private var importing = false
    @State private var compressing = false
    @State private var message = "Import a file. UltraCompress makes its own local working copy before compression."

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.indigo.opacity(0.18), Color.purple.opacity(0.08), Color.clear],
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
        .sheet(isPresented: $showPicker) {
            LocalCopyDocumentPicker { url in
                showPicker = false
                guard let url else { return }
                Task { await stageImportedURL(url) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showShareSheet) {
            if let output {
                ActivityView(url: output)
                    .ignoresSafeArea()
            }
        }
        .onOpenURL { url in
            Task { await stageImportedURL(url) }
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
                    .frame(width: 68, height: 68)
                    .shadow(color: .indigo.opacity(0.28), radius: 14, y: 7)

                VStack(spacing: 1) {
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 25, weight: .black))
                    Text("UC")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                }
                .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("ULTRACOMPRESS")
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .tracking(1.4)
                Text("Maximum ratio • local-staged import")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("INPUT", systemImage: "tray.and.arrow.down.fill")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Button {
                showPicker = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.indigo.opacity(0.10))
                            .frame(width: 46, height: 46)
                        if importing {
                            ProgressView()
                        } else {
                            Image(systemName: selected == nil ? "doc.badge.plus" : "arrow.triangle.2.circlepath")
                                .font(.headline)
                                .foregroundStyle(.indigo)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(selected == nil ? "Import a file" : "Import another file")
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
            .disabled(importing || compressing)

            if let selected {
                Divider()
                HStack(spacing: 10) {
                    Image(systemName: fileIcon(selected))
                        .foregroundStyle(.indigo)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selected.lastPathComponent)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(sizeText(selected))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            Divider()

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "internaldrive.fill")
                    .foregroundStyle(.indigo)
                Text("The picker imports a copy, then UltraCompress stages that copy inside its own sandbox. Compression never depends on a long-lived Files/iCloud provider URL.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "square.and.arrow.down")
                    .foregroundStyle(.indigo)
                Text("You can also use Files → Share / Open With → UltraCompress. Incoming files are staged the same way.")
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
                ForEach(OutputFormat.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)

            Picker("Compression", selection: $preset) {
                ForEach(CompressionPreset.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
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
                Task { await compressSelected() }
            } label: {
                HStack {
                    Spacer()
                    if compressing {
                        ProgressView().tint(.white)
                    }
                    Image(systemName: compressing ? "hourglass" : "archivebox.fill")
                    Text(compressing ? "Compressing…" : "Compress Now")
                        .font(.headline.bold())
                    Spacer()
                }
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .disabled(selected == nil || importing || compressing)

            if output != nil {
                Button {
                    showShareSheet = true
                } label: {
                    Label("Save or Share Result", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
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
                ? "LZMA2 level 9 + solid archive + fully compressed headers. Smallest-output mode, with slower processing."
                : "LZMA2 solid archive at a lower compression level for faster processing."
        }
        return "ZIP prioritizes compatibility. IPA and ZIP inputs are already ZIP containers, so copying them avoids pointless recompression."
    }

    private func fileIcon(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "ipa": return "apps.iphone"
        case "zip", "7z", "rar", "xz", "tar", "gz": return "archivebox.fill"
        case "mp4", "mov", "mkv", "avi": return "film.fill"
        case "mp3", "m4a", "wav", "flac": return "waveform"
        default: return "doc.fill"
        }
    }

    private func sizeText(_ url: URL) -> String {
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
           let size = values.fileSize {
            return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        }
        return "Local working copy"
    }

    @MainActor
    private func stageImportedURL(_ source: URL) async {
        importing = true
        output = nil
        message = "Importing \(source.lastPathComponent) into UltraCompress…"

        do {
            let staged = try await Task.detached(priority: .userInitiated) {
                try ImportManager.stage(source)
            }.value

            if let old = selected, old != staged {
                ImportManager.removeIfStaged(old)
            }
            selected = staged
            message = "Imported \(staged.lastPathComponent) • \(sizeText(staged)). Ready to compress."
        } catch {
            message = "Import failed: \(error.localizedDescription)"
        }

        importing = false
    }

    @MainActor
    private func compressSelected() async {
        guard let selected else { return }
        compressing = true
        output = nil
        message = "Compressing the local working copy…"

        let chosenFormat = format
        let chosenPreset = preset

        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try ArchiveEngine.compress(selected, as: chosenFormat, preset: chosenPreset)
            }.value

            output = result
            let original = ArchiveEngine.fileSize(selected)
            let packed = ArchiveEngine.fileSize(result)

            if original > 0, packed > 0 {
                let delta = 100.0 * (1.0 - Double(packed) / Double(original))
                let originalText = ByteCountFormatter.string(fromByteCount: original, countStyle: .file)
                let packedText = ByteCountFormatter.string(fromByteCount: packed, countStyle: .file)
                if delta >= 0 {
                    message = String(format: "Done • %@ → %@ • %.1f%% smaller", originalText, packedText, delta)
                } else {
                    message = String(format: "Done • %@ → %@ • %.1f%% larger because the source was already compressed", originalText, packedText, abs(delta))
                }
            } else {
                message = "Compression finished."
            }
        } catch {
            message = "Compression failed: \(error.localizedDescription)"
        }

        compressing = false
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

struct LocalCopyDocumentPicker: UIViewControllerRepresentable {
    let completion: (URL?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (URL?) -> Void

        init(completion: @escaping (URL?) -> Void) {
            self.completion = completion
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            completion(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            completion(nil)
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

enum ImportManager {
    static func stage(_ source: URL) throws -> URL {
        let fm = FileManager.default
        let scoped = source.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                source.stopAccessingSecurityScopedResource()
            }
        }

        let root = try importsDirectory()
        let destination = uniqueDestination(for: source, in: root)

        var coordinationError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: source, options: [.withoutChanges], error: &coordinationError) { coordinatedURL in
            do {
                guard try coordinatedURL.checkResourceIsReachable() else {
                    throw ImportError.fileUnavailable
                }
                try fm.copyItem(at: coordinatedURL, to: destination)
            } catch {
                copyError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let copyError {
            throw copyError
        }

        return destination
    }

    static func removeIfStaged(_ url: URL) {
        guard let root = try? importsDirectory() else { return }
        let rootPath = root.standardizedFileURL.path
        let itemPath = url.standardizedFileURL.path
        guard itemPath.hasPrefix(rootPath) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func importsDirectory() throws -> URL {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ImportError.noApplicationSupportDirectory
        }
        let root = appSupport.appendingPathComponent("Imports", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func uniqueDestination(for source: URL, in root: URL) -> URL {
        let fm = FileManager.default
        let originalName = source.lastPathComponent.isEmpty ? "ImportedFile" : source.lastPathComponent
        var candidate = root.appendingPathComponent(originalName)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }

        let ext = source.pathExtension
        let stem = source.deletingPathExtension().lastPathComponent.isEmpty ? "ImportedFile" : source.deletingPathExtension().lastPathComponent
        var index = 2
        while fm.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(ext)"
            candidate = root.appendingPathComponent(name)
            index += 1
        }
        return candidate
    }
}

enum ArchiveEngine {
    static func compress(_ url: URL, as format: OutputFormat, preset: CompressionPreset) throws -> URL {
        guard try url.checkResourceIsReachable() else {
            throw ArchiveError.fileUnavailable
        }

        let base = url.deletingPathExtension().lastPathComponent.isEmpty
            ? "Archive"
            : url.deletingPathExtension().lastPathComponent
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(base)-Ultra.\(format.ext)")

        try? FileManager.default.removeItem(at: destination)

        switch format {
        case .sevenZ:
            try make7z(url, destination: destination, level: preset.level)
        case .zip:
            let ext = url.pathExtension.lowercased()
            if ext == "ipa" || ext == "zip" {
                try FileManager.default.copyItem(at: url, to: destination)
            } else {
                try makeZip(url, destination: destination, level: preset.zipLevel)
            }
        }

        return destination
    }

    private static func make7z(_ url: URL, destination: URL, level: UInt8) throws {
        let stream = try OutStream(path: Path(destination.path))
        let encoder = try PLzmaSDK.Encoder(stream: stream, fileType: .sevenZ, method: .LZMA2)
        try encoder.setCompressionLevel(level)
        try encoder.setShouldCreateSolidArchive(true)
        try encoder.setShouldCompressHeader(true)
        try encoder.setShouldCompressHeaderFull(true)
        try encoder.add(path: Path(url.path), mode: .default, archivePath: Path(url.lastPathComponent))
        guard try encoder.open(), try encoder.compress() else {
            throw ArchiveError.compressionFailed
        }
    }

    private static func makeZip(_ url: URL, destination: URL, level: CompressionLevel) throws {
        let archive = try ZipArchive(url: destination, mode: .overwrite)
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        try archive.addFile(at: url.lastPathComponent, data: data, compression: level)
        try archive.finalize()
    }

    static func fileSize(_ url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else {
            return 0
        }
        return Int64(size)
    }
}

enum ImportError: LocalizedError {
    case fileUnavailable
    case noApplicationSupportDirectory

    var errorDescription: String? {
        switch self {
        case .fileUnavailable:
            return "The selected file could not be read after import."
        case .noApplicationSupportDirectory:
            return "UltraCompress could not create its local import folder."
        }
    }
}

enum ArchiveError: LocalizedError {
    case compressionFailed
    case fileUnavailable

    var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "The archive engine could not finish compression."
        case .fileUnavailable:
            return "The local working copy is unavailable. Import the file again."
        }
    }
}
