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

private struct BrowserItem: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    var id: URL { url }
}

struct ContentView: View {
    @State private var showFolderPicker = false
    @State private var showFilePicker = false
    @State private var folderRoot: URL?
    @State private var currentFolder: URL?
    @State private var folderScopeActive = false
    @State private var browserItems: [BrowserItem] = []
    @State private var selected: URL?
    @State private var format: OutputFormat = .sevenZ
    @State private var preset: CompressionPreset = .maximum
    @State private var busy = false
    @State private var output: URL?
    @State private var message = "For very large iCloud files, choose the containing folder first."

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
                        inputCard
                        if currentFolder != nil { folderBrowserCard }
                        settingsCard
                        actionCard
                    }
                    .padding(16)
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showFolderPicker) {
            FolderDocumentPicker { url in
                showFolderPicker = false
                guard let url else { return }
                openFolder(url)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showFilePicker) {
            SingleFileDocumentPicker { url in
                showFilePicker = false
                guard let url else { return }
                selected = url
                output = nil
                message = "Selected \(url.lastPathComponent)."
            }
            .ignoresSafeArea()
        }
        .onOpenURL { url in
            selected = url
            output = nil
            message = "Received \(url.lastPathComponent) from Files."
        }
        .onDisappear {
            if folderScopeActive, let folderRoot {
                folderRoot.stopAccessingSecurityScopedResource()
            }
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
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
                Text("Maximum ratio • large-file safe")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("INPUT", systemImage: "tray.and.arrow.down.fill")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Button { showFolderPicker = true } label: {
                inputRow(
                    icon: "folder.fill.badge.plus",
                    title: "Browse a folder",
                    subtitle: "Recommended for large iCloud files"
                )
            }
            .buttonStyle(.plain)

            Divider()

            Button { showFilePicker = true } label: {
                inputRow(
                    icon: "doc.badge.plus",
                    title: "Pick one file directly",
                    subtitle: "Best for files already stored on this iPhone"
                )
            }
            .buttonStyle(.plain)

            Divider()

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(.indigo)
                Text("You can also bypass the picker completely: in Files, long-press the IPA/ZIP → Share or Open With → UltraCompress.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let selected {
                Divider()
                HStack(spacing: 10) {
                    Image(systemName: selected.pathExtension.lowercased() == "ipa" ? "apps.iphone" : "doc.fill")
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

    private func inputRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.indigo.opacity(0.10))
                    .frame(width: 46, height: 46)
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(.indigo)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private var folderBrowserCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if canGoUp {
                    Button { goUp() } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .font(.subheadline.weight(.semibold))
                }
                Spacer()
                Text(currentFolder?.lastPathComponent ?? "Folder")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if browserItems.isEmpty {
                ContentUnavailableView("No visible files", systemImage: "folder")
                    .frame(minHeight: 110)
            } else {
                ForEach(browserItems) { item in
                    Button {
                        if item.isDirectory {
                            currentFolder = item.url
                            reloadFolder()
                        } else {
                            selected = item.url
                            output = nil
                            message = "Selected \(item.url.lastPathComponent) from the granted folder."
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.isDirectory ? "folder.fill" : fileIcon(item.url))
                                .foregroundStyle(item.isDirectory ? .yellow : .indigo)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.url.lastPathComponent)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                if !item.isDirectory {
                                    Text(sizeText(item.url))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: item.isDirectory ? "chevron.right" : (selected == item.url ? "checkmark.circle.fill" : "circle"))
                                .foregroundStyle(selected == item.url ? .green : .secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if item.id != browserItems.last?.id { Divider() }
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
                ForEach(OutputFormat.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("Compression", selection: $preset) {
                ForEach(CompressionPreset.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)

            Text(format == .sevenZ
                 ? "7z Maximum uses LZMA2 level 9, solid mode, and fully compressed headers."
                 : "ZIP prioritizes compatibility. IPA files are already ZIP containers, so 7z usually gives the better storage ratio.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                    if busy { ProgressView().tint(.white) }
                    Image(systemName: busy ? "icloud.and.arrow.down.fill" : "archivebox.fill")
                    Text(busy ? "Downloading / Compressing…" : "Compress Now")
                        .font(.headline.bold())
                    Spacer()
                }
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .disabled(selected == nil || busy)

            if let output {
                ShareLink(item: output) {
                    Label("Save or Share \(output.lastPathComponent)", systemImage: "square.and.arrow.up")
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

    private var canGoUp: Bool {
        guard let root = folderRoot, let current = currentFolder else { return false }
        return current.standardizedFileURL != root.standardizedFileURL
    }

    private func openFolder(_ url: URL) {
        if folderScopeActive, let old = folderRoot { old.stopAccessingSecurityScopedResource() }
        folderScopeActive = url.startAccessingSecurityScopedResource()
        folderRoot = url
        currentFolder = url
        selected = nil
        output = nil
        message = "Folder access granted. Pick the large file inside UltraCompress."
        reloadFolder()
    }

    private func reloadFolder() {
        guard let currentFolder else { browserItems = []; return }
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: currentFolder,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            browserItems = urls.map { url in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return BrowserItem(url: url, isDirectory: isDirectory)
            }
            .sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory && !$1.isDirectory }
                return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
        } catch {
            browserItems = []
            message = "Could not list this folder: \(error.localizedDescription)"
        }
    }

    private func goUp() {
        guard let root = folderRoot, let current = currentFolder else { return }
        let parent = current.deletingLastPathComponent()
        let rootPath = root.standardizedFileURL.path
        if parent.standardizedFileURL.path.hasPrefix(rootPath) {
            currentFolder = parent
        } else {
            currentFolder = root
        }
        reloadFolder()
    }

    private func fileIcon(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "ipa": return "apps.iphone"
        case "zip", "7z", "rar", "xz", "tar", "gz": return "archivebox.fill"
        case "mp4", "mov", "mkv": return "film.fill"
        default: return "doc.fill"
        }
    }

    private func sizeText(_ url: URL) -> String {
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, let size {
            return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        }
        return "Cloud / provider item"
    }

    @MainActor
    private func compress() async {
        guard let selected else { return }
        busy = true
        output = nil
        message = "Preparing \(selected.lastPathComponent). If it is in iCloud, the download happens now."

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
                if delta >= 0 {
                    message = String(format: "Done • %@ → %@ • %.1f%% smaller", ByteCountFormatter.string(fromByteCount: original, countStyle: .file), ByteCountFormatter.string(fromByteCount: packed, countStyle: .file), delta)
                } else {
                    message = String(format: "Done • %@ → %@ • %.1f%% larger because the source was already compressed", ByteCountFormatter.string(fromByteCount: original, countStyle: .file), ByteCountFormatter.string(fromByteCount: packed, countStyle: .file), abs(delta))
                }
            } else {
                message = "Compression finished."
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

struct FolderDocumentPicker: UIViewControllerRepresentable {
    let completion: (URL?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (URL?) -> Void
        init(completion: @escaping (URL?) -> Void) { self.completion = completion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion(nil) }
    }
}

struct SingleFileDocumentPicker: UIViewControllerRepresentable {
    let completion: (URL?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        var types: [UTType] = [.data, .content]
        if let ipa = UTType(filenameExtension: "ipa") { types.insert(ipa, at: 0) }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (URL?) -> Void
        init(completion: @escaping (URL?) -> Void) { self.completion = completion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion(nil) }
    }
}

enum ArchiveEngine {
    static func compress(_ url: URL, as format: OutputFormat, preset: CompressionPreset) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        try prepareProviderItem(url)

        let base = url.deletingPathExtension().lastPathComponent.isEmpty ? "Archive" : url.deletingPathExtension().lastPathComponent
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("\(base)-Ultra.\(format.ext)")
        try? FileManager.default.removeItem(at: destination)

        switch format {
        case .sevenZ:
            try make7z(url, destination: destination, level: preset.level)
        case .zip:
            if url.pathExtension.lowercased() == "ipa" || url.pathExtension.lowercased() == "zip" {
                try FileManager.default.copyItem(at: url, to: destination)
            } else {
                try makeZip(url, destination: destination, level: preset.zipLevel)
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
        var readError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            do {
                let handle = try FileHandle(forReadingFrom: coordinatedURL)
                _ = try handle.read(upToCount: 1)
                try handle.close()
            } catch {
                readError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let readError { throw readError }
    }

    private static func make7z(_ url: URL, destination: URL, level: UInt8) throws {
        let stream = try OutStream(path: Path(destination.path))
        let encoder = try PLzmaSDK.Encoder(stream: stream, fileType: .sevenZ, method: .LZMA2)
        try encoder.setCompressionLevel(level)
        try encoder.setShouldCreateSolidArchive(true)
        try encoder.setShouldCompressHeader(true)
        try encoder.setShouldCompressHeaderFull(true)
        try encoder.add(path: Path(url.path), mode: .default, archivePath: Path(url.lastPathComponent))
        guard try encoder.open(), try encoder.compress() else { throw ArchiveError.compressionFailed }
    }

    private static func makeZip(_ url: URL, destination: URL, level: CompressionLevel) throws {
        let archive = try ZipArchive(url: destination, mode: .overwrite)
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        try archive.addFile(at: url.lastPathComponent, data: data, compression: level)
        try archive.finalize()
    }

    static func fileSize(_ url: URL) -> Int64 {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? nil
        return Int64(size ?? 0)
    }
}

enum ArchiveError: LocalizedError {
    case compressionFailed
    var errorDescription: String? { "The archive engine could not finish compression." }
}
