import SwiftUI
import UniformTypeIdentifiers
import UIKit
import Foundation
import PLzmaSDK
import ZIPFoundation

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
}

struct ImportProgressUpdate: Sendable {
    let fraction: Double?
    let copiedBytes: Int64
    let totalBytes: Int64
}

enum ImportEvent: Sendable {
    case progress(ImportProgressUpdate)
    case completed(URL)
}

struct CompressionProgressUpdate: Sendable {
    let fraction: Double?
    let detail: String
}

enum CompressionEvent: Sendable {
    case progress(CompressionProgressUpdate)
    case completed(URL)
}

struct ContentView: View {
    @State private var showPicker = false
    @State private var showShareSheet = false
    @State private var showExporter = false

    @State private var selected: URL?
    @State private var output: URL?
    @State private var format: OutputFormat = .sevenZ
    @State private var preset: CompressionPreset = .maximum

    @State private var importing = false
    @State private var importProgress: Double?
    @State private var importDetail = ""

    @State private var compressing = false
    @State private var compressionProgress: Double?
    @State private var compressionDetail = ""
    @State private var compressionStartedAt: Date?

    @State private var message = "Import a file. UltraCompress keeps a local working copy before compression."

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
                guard let url else {
                    importing = false
                    importProgress = nil
                    importDetail = ""
                    return
                }
                Task { await stageImportedURL(url) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showShareSheet) {
            if let output {
                ActivityView(url: output) { completed, error in
                    Task { @MainActor in
                        showShareSheet = false
                        if let error {
                            message = "Share failed: \(error.localizedDescription). Try Save to Files instead."
                        } else if completed {
                            message = "Shared successfully."
                        }
                    }
                }
                .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showExporter) {
            if let output {
                ExportDocumentPicker(url: output) { result in
                    Task { @MainActor in
                        showExporter = false
                        switch result {
                        case .success:
                            message = "Saved to Files successfully."
                        case .failure(let error):
                            message = "Save failed: \(error.localizedDescription)"
                        }
                    }
                }
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
                Text("Maximum ratio • real compression progress")
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
                importing = true
                importProgress = nil
                importDetail = "Waiting for Files to prepare the item…"
                message = "Choose a file. Cloud providers may need time to download it first."
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

            if importing {
                VStack(alignment: .leading, spacing: 7) {
                    if let importProgress {
                        ProgressView(value: importProgress, total: 1)
                        HStack {
                            Text(importDetail).lineLimit(1)
                            Spacer()
                            Text("\(Int((importProgress * 100).rounded()))%")
                                .monospacedDigit()
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                        Text(importDetail.isEmpty ? "Preparing file…" : importDetail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

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
                    Image(systemName: compressing ? "gearshape.2.fill" : "archivebox.fill")
                    Text(compressing ? "Compressing…" : "Compress Now")
                        .font(.headline.bold())
                    Spacer()
                }
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .disabled(selected == nil || importing || compressing)

            if compressing {
                compressionProgressView
            }

            if output != nil, !compressing {
                HStack(spacing: 10) {
                    Button {
                        showExporter = true
                    } label: {
                        Label("Save to Files", systemImage: "folder.badge.plus")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 14))

                    Button {
                        showShareSheet = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                }
            }

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .brandCard()
    }

    @ViewBuilder
    private var compressionProgressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let compressionProgress {
                ProgressView(value: compressionProgress, total: 1)
                    .progressViewStyle(.linear)

                HStack(spacing: 8) {
                    Text(compressionDetail.isEmpty ? "Compressing…" : compressionDetail)
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int((compressionProgress * 100).rounded()))%")
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .font(.caption)
            } else {
                ProgressView()
                Text(compressionDetail.isEmpty ? "Starting compression engine…" : compressionDetail)
                    .font(.caption)
            }

            if let compressionStartedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("Elapsed \(durationText(context.date.timeIntervalSince(compressionStartedAt)))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color.indigo.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private var engineDescription: String {
        if format == .sevenZ {
            return preset == .maximum
                ? "LZMA2 level 9 with solid archive and compressed headers. The progress bar comes directly from the 7z encoder."
                : "LZMA2 solid archive. The progress bar comes directly from the 7z encoder."
        }
        return "ZIP uses streaming DEFLATE with byte-based progress. Existing IPA/ZIP containers are copied instead of pointlessly recompressed."
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d", total / 60, total % 60)
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
        let size = ArchiveEngine.fileSize(url)
        return size > 0
            ? ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            : "Local working copy"
    }

    @MainActor
    private func stageImportedURL(_ source: URL) async {
        importing = true
        importProgress = nil
        importDetail = "Preparing \(source.lastPathComponent)…"
        output = nil
        message = "Preparing the selected file…"

        do {
            var stagedURL: URL?
            for try await event in ImportManager.stageStream(source) {
                switch event {
                case .progress(let update):
                    importProgress = update.fraction
                    if update.totalBytes > 0 {
                        let copied = ByteCountFormatter.string(fromByteCount: update.copiedBytes, countStyle: .file)
                        let total = ByteCountFormatter.string(fromByteCount: update.totalBytes, countStyle: .file)
                        importDetail = "\(copied) / \(total)"
                        message = "Importing \(source.lastPathComponent)…"
                    } else {
                        importDetail = "Reading from the file provider…"
                    }
                case .completed(let url):
                    stagedURL = url
                }
            }

            guard let staged = stagedURL else {
                throw ImportError.fileUnavailable
            }

            if let old = selected, old != staged {
                ImportManager.removeIfStaged(old)
            }
            selected = staged
            message = "Imported \(staged.lastPathComponent) • \(sizeText(staged)). Ready to compress."
        } catch {
            message = "Import failed: \(error.localizedDescription)"
        }

        importing = false
        importProgress = nil
        importDetail = ""
    }

    @MainActor
    private func compressSelected() async {
        guard let selected else { return }

        compressing = true
        compressionProgress = nil
        compressionDetail = "Starting \(format.rawValue) engine…"
        compressionStartedAt = Date()
        output = nil
        message = "Compression is running. Progress will update below."

        let chosenFormat = format
        let chosenPreset = preset

        do {
            var resultURL: URL?
            for try await event in ArchiveEngine.compressStream(selected, as: chosenFormat, preset: chosenPreset) {
                switch event {
                case .progress(let update):
                    compressionProgress = update.fraction
                    compressionDetail = update.detail
                    if let fraction = update.fraction {
                        message = "Compressing… \(Int((fraction * 100).rounded()))%"
                    } else {
                        message = update.detail
                    }
                case .completed(let url):
                    resultURL = url
                }
            }

            guard let result = resultURL else {
                throw ArchiveError.compressionFailed
            }

            compressionProgress = 1
            compressionDetail = "Finalized"
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
                    message = String(format: "Done • %@ → %@ • %.1f%% larger", originalText, packedText, abs(delta))
                }
            } else {
                message = "Compression finished."
            }
        } catch {
            message = "Compression failed: \(error.localizedDescription)"
        }

        compressing = false
        compressionStartedAt = nil
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

struct ExportDocumentPicker: UIViewControllerRepresentable {
    let url: URL
    let completion: (Result<Void, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (Result<Void, Error>) -> Void

        init(completion: @escaping (Result<Void, Error>) -> Void) {
            self.completion = completion
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            completion(.success(()))
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let url: URL
    let completion: (Bool, Error?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in
            completion(completed, error)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

enum ImportManager {
    static func stageStream(_ source: URL) -> AsyncThrowingStream<ImportEvent, Error> {
        AsyncThrowingStream { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    let staged = try stage(source) { update in
                        continuation.yield(.progress(update))
                    }
                    continuation.yield(.completed(staged))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private static func stage(
        _ source: URL,
        progress: @escaping @Sendable (ImportProgressUpdate) -> Void
    ) throws -> URL {
        let fm = FileManager.default
        let scoped = source.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                source.stopAccessingSecurityScopedResource()
            }
        }

        try? fm.startDownloadingUbiquitousItem(at: source)

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

                let totalBytes = ArchiveEngine.fileSize(coordinatedURL)
                progress(ImportProgressUpdate(
                    fraction: totalBytes > 0 ? 0 : nil,
                    copiedBytes: 0,
                    totalBytes: totalBytes
                ))

                guard fm.createFile(atPath: destination.path, contents: nil) else {
                    throw ImportError.couldNotCreateLocalCopy
                }

                let input = try FileHandle(forReadingFrom: coordinatedURL)
                let output = try FileHandle(forWritingTo: destination)
                defer {
                    try? input.close()
                    try? output.close()
                }

                let chunkSize = 4 * 1024 * 1024
                var copiedBytes: Int64 = 0

                while true {
                    guard let data = try input.read(upToCount: chunkSize), !data.isEmpty else {
                        break
                    }
                    try output.write(contentsOf: data)
                    copiedBytes += Int64(data.count)
                    let fraction = totalBytes > 0
                        ? min(1, Double(copiedBytes) / Double(totalBytes))
                        : nil
                    progress(ImportProgressUpdate(
                        fraction: fraction,
                        copiedBytes: copiedBytes,
                        totalBytes: totalBytes
                    ))
                }

                try output.synchronize()
            } catch {
                try? fm.removeItem(at: destination)
                copyError = error
            }
        }

        if let coordinationError {
            try? fm.removeItem(at: destination)
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
        if !fm.fileExists(atPath: candidate.path) {
            return candidate
        }

        let ext = source.pathExtension
        let stem = source.deletingPathExtension().lastPathComponent.isEmpty
            ? "ImportedFile"
            : source.deletingPathExtension().lastPathComponent
        var index = 2
        while fm.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(ext)"
            candidate = root.appendingPathComponent(name)
            index += 1
        }
        return candidate
    }
}

final class SevenZipProgressDelegate: NSObject, PLzmaSDK.EncoderDelegate, @unchecked Sendable {
    private let handler: @Sendable (Double, String) -> Void

    init(handler: @escaping @Sendable (Double, String) -> Void) {
        self.handler = handler
    }

    func encoder(encoder: PLzmaSDK.Encoder, path: String, progress: Double) {
        handler(min(1, max(0, progress)), path)
    }
}

enum ArchiveEngine {
    static func compressStream(
        _ url: URL,
        as format: OutputFormat,
        preset: CompressionPreset
    ) -> AsyncThrowingStream<CompressionEvent, Error> {
        AsyncThrowingStream { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    let result = try compress(url, as: format, preset: preset) { fraction, detail in
                        continuation.yield(.progress(CompressionProgressUpdate(
                            fraction: fraction,
                            detail: detail
                        )))
                    }
                    continuation.yield(.completed(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private static func compress(
        _ url: URL,
        as format: OutputFormat,
        preset: CompressionPreset,
        progress: @escaping @Sendable (Double?, String) -> Void
    ) throws -> URL {
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
            try make7z(url, destination: destination, level: preset.level, progress: progress)
        case .zip:
            let ext = url.pathExtension.lowercased()
            if ext == "ipa" || ext == "zip" {
                try copyExistingZip(url, destination: destination, progress: progress)
            } else {
                try makeZip(url, destination: destination, progress: progress)
            }
        }

        progress(1, "Finalizing archive…")
        return destination
    }

    private static func make7z(
        _ url: URL,
        destination: URL,
        level: UInt8,
        progress: @escaping @Sendable (Double?, String) -> Void
    ) throws {
        progress(nil, "Opening 7z encoder…")

        let delegate = SevenZipProgressDelegate { fraction, path in
            let name = path.isEmpty ? url.lastPathComponent : URL(fileURLWithPath: path).lastPathComponent
            progress(fraction, "LZMA2 • \(name)")
        }

        let stream = try OutStream(path: Path(destination.path))
        let encoder = try PLzmaSDK.Encoder(
            stream: stream,
            fileType: .sevenZ,
            method: .LZMA2,
            delegate: delegate
        )
        try encoder.setCompressionLevel(level)
        try encoder.setShouldCreateSolidArchive(true)
        try encoder.setShouldCompressHeader(true)
        try encoder.setShouldCompressHeaderFull(true)
        try encoder.add(path: Path(url.path), mode: .default, archivePath: Path(url.lastPathComponent))

        guard try encoder.open() else {
            throw ArchiveError.compressionFailed
        }
        progress(0, "LZMA2 compression started…")
        guard try encoder.compress() else {
            throw ArchiveError.compressionFailed
        }
    }

    private static func copyExistingZip(
        _ source: URL,
        destination: URL,
        progress: @escaping @Sendable (Double?, String) -> Void
    ) throws {
        let total = fileSize(source)
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw ArchiveError.compressionFailed
        }

        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: destination)
        defer {
            try? input.close()
            try? output.close()
        }

        var copied: Int64 = 0
        let chunkSize = 4 * 1024 * 1024
        while true {
            guard let data = try input.read(upToCount: chunkSize), !data.isEmpty else { break }
            try output.write(contentsOf: data)
            copied += Int64(data.count)
            let fraction = total > 0 ? min(1, Double(copied) / Double(total)) : nil
            let copiedText = ByteCountFormatter.string(fromByteCount: copied, countStyle: .file)
            let totalText = total > 0 ? ByteCountFormatter.string(fromByteCount: total, countStyle: .file) : "?"
            progress(fraction, "Copying existing ZIP • \(copiedText) / \(totalText)")
        }
        try output.synchronize()
    }

    private static func makeZip(
        _ source: URL,
        destination: URL,
        progress: @escaping @Sendable (Double?, String) -> Void
    ) throws {
        let total = fileSize(source)
        guard total >= 0 else {
            throw ArchiveError.fileUnavailable
        }

        let archive = try ZIPFoundation.Archive(url: destination, accessMode: .create)
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }

        var highestRead: Int64 = 0
        progress(0, "ZIP DEFLATE started…")

        try archive.addEntry(
            with: source.lastPathComponent,
            type: .file,
            uncompressedSize: total,
            compressionMethod: .deflate,
            bufferSize: 1024 * 1024,
            provider: { position, size in
                try input.seek(toOffset: UInt64(position))
                let data = try input.read(upToCount: size) ?? Data()
                highestRead = max(highestRead, position + Int64(data.count))
                let fraction = total > 0 ? min(1, Double(highestRead) / Double(total)) : nil
                let doneText = ByteCountFormatter.string(fromByteCount: highestRead, countStyle: .file)
                let totalText = total > 0 ? ByteCountFormatter.string(fromByteCount: total, countStyle: .file) : "?"
                progress(fraction, "ZIP DEFLATE • \(doneText) / \(totalText)")
                return data
            }
        )
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
    case couldNotCreateLocalCopy

    var errorDescription: String? {
        switch self {
        case .fileUnavailable:
            return "The selected file could not be read completely."
        case .noApplicationSupportDirectory:
            return "UltraCompress could not create its local import folder."
        case .couldNotCreateLocalCopy:
            return "UltraCompress could not create a local working copy."
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
