import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import NobodyWho

struct NexusDownloadSnapshot: Equatable {
    var downloadedBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var bytesPerSecond: Double = 0
    var activeChunks: Int = 0
    var completedChunks: Int = 0
    var totalChunks: Int = 0

    static let zero = NexusDownloadSnapshot()

    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return max(0, min(1, Double(downloadedBytes) / Double(totalBytes)))
    }

    var percentText: String { String(format: "%.1f%%", fraction * 100) }

    var detailText: String {
        let done = ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)
        let total = totalBytes > 0 ? ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file) : "unknown"
        var parts = ["\(percentText) • \(done) / \(total)"]
        if bytesPerSecond > 0 {
            parts.append(String(format: "%.1f MB/s", bytesPerSecond / 1_048_576.0))
            if totalBytes > downloadedBytes {
                let seconds = Double(totalBytes - downloadedBytes) / bytesPerSecond
                if seconds.isFinite {
                    if seconds >= 3600 { parts.append(String(format: "ETA %.1fh", seconds / 3600)) }
                    else if seconds >= 60 { parts.append(String(format: "ETA %.0fm %.0fs", floor(seconds / 60), seconds.truncatingRemainder(dividingBy: 60))) }
                    else { parts.append(String(format: "ETA %.0fs", max(0, seconds))) }
                }
            }
        }
        if totalChunks > 1 { parts.append("\(activeChunks) parallel • \(completedChunks)/\(totalChunks) chunks") }
        return parts.joined(separator: " • ")
    }
}

private enum NexusDownloadError: LocalizedError {
    case invalidURL
    case rangeUnsupported
    case invalidResponse
    case incompleteFile

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "The model download URL is invalid."
        case .rangeUnsupported: return "The server does not support parallel byte-range downloads."
        case .invalidResponse: return "The model server returned an unexpected response."
        case .incompleteFile: return "The downloaded model did not match the expected size."
        }
    }
}

enum NexusParallelDownloader {
    private static let chunkSize: Int64 = 8 * 1_048_576

    static func download(modelPath: String,
                         destinationName: String,
                         estimatedBytes: UInt64 = 0,
                         concurrency requestedConcurrency: Int = 4,
                         progress: @escaping (NexusDownloadSnapshot) -> Void) async throws -> String {
        guard let remoteURL = remoteURL(for: modelPath) else { throw NexusDownloadError.invalidURL }
        let concurrency = max(2, min(6, requestedConcurrency))
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("NEXUS-Models", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        let safeName = destinationName.replacingOccurrences(of: "/", with: "_")
        let destination = base.appendingPathComponent(safeName)

        let probe = await probe(remoteURL: remoteURL)
        let expected = probe.totalBytes > 0 ? probe.totalBytes : Int64(estimatedBytes)
        if expected > 0,
           fm.fileExists(atPath: destination.path),
           let existing = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           Int64(existing) == expected {
            progress(.init(downloadedBytes: expected, totalBytes: expected, bytesPerSecond: 0, activeChunks: 0, completedChunks: 1, totalChunks: 1))
            return destination.path
        }

        if probe.supportsRanges, probe.totalBytes > 0 {
            do {
                return try await rangedDownload(remoteURL: remoteURL,
                                                destination: destination,
                                                totalBytes: probe.totalBytes,
                                                concurrency: concurrency,
                                                progress: progress)
            } catch NexusDownloadError.rangeUnsupported {
                // Some CDNs advertise ranges but ignore them on the final redirected object.
            }
        }

        let started = Date()
        let path = try await Model.downloadModel(modelPath: modelPath, headers: nil) { downloaded, total in
            let elapsed = max(Date().timeIntervalSince(started), 0.05)
            let speed = Double(downloaded) / elapsed
            progress(.init(downloadedBytes: Int64(downloaded),
                           totalBytes: Int64(total),
                           bytesPerSecond: speed,
                           activeChunks: 1,
                           completedChunks: downloaded >= total && total > 0 ? 1 : 0,
                           totalChunks: 1))
        }
        return path
    }

    private static func rangedDownload(remoteURL: URL,
                                       destination: URL,
                                       totalBytes: Int64,
                                       concurrency: Int,
                                       progress: @escaping (NexusDownloadSnapshot) -> Void) async throws -> String {
        let fm = FileManager.default
        let partsDirectory = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).nexus-parts", isDirectory: true)
        try fm.createDirectory(at: partsDirectory, withIntermediateDirectories: true)

        let totalChunks = Int((totalBytes + chunkSize - 1) / chunkSize)
        var completedBytes: Int64 = 0
        var completedChunks = 0
        var missing: [Int] = []

        for index in 0..<totalChunks {
            let start = Int64(index) * chunkSize
            let expected = min(chunkSize, totalBytes - start)
            let part = partsDirectory.appendingPathComponent("part-\(index)")
            if fm.fileExists(atPath: part.path),
               let n = try? part.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               Int64(n) == expected {
                completedBytes += expected
                completedChunks += 1
            } else {
                if fm.fileExists(atPath: part.path) { try? fm.removeItem(at: part) }
                missing.append(index)
            }
        }

        let resumedBytes = completedBytes
        let started = Date()
        progress(.init(downloadedBytes: completedBytes,
                       totalBytes: totalBytes,
                       bytesPerSecond: 0,
                       activeChunks: min(concurrency, missing.count),
                       completedChunks: completedChunks,
                       totalChunks: totalChunks))

        try await withThrowingTaskGroup(of: (Int, Int64).self) { group in
            var iterator = missing.makeIterator()
            var active = 0

            func addNext() {
                guard let index = iterator.next() else { return }
                active += 1
                group.addTask {
                    let start = Int64(index) * chunkSize
                    let end = min(totalBytes - 1, start + chunkSize - 1)
                    let part = partsDirectory.appendingPathComponent("part-\(index)")
                    let bytes = try await downloadChunk(remoteURL: remoteURL, range: start...end, destination: part)
                    return (index, bytes)
                }
            }

            for _ in 0..<min(concurrency, missing.count) { addNext() }

            while let (_, bytes) = try await group.next() {
                active -= 1
                completedBytes += bytes
                completedChunks += 1
                let sessionBytes = max(0, completedBytes - resumedBytes)
                let elapsed = max(Date().timeIntervalSince(started), 0.05)
                let speed = Double(sessionBytes) / elapsed
                addNext()
                progress(.init(downloadedBytes: completedBytes,
                               totalBytes: totalBytes,
                               bytesPerSecond: speed,
                               activeChunks: active,
                               completedChunks: completedChunks,
                               totalChunks: totalChunks))
            }
        }

        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        fm.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        do {
            for index in 0..<totalChunks {
                let part = partsDirectory.appendingPathComponent("part-\(index)")
                let input = try FileHandle(forReadingFrom: part)
                defer { try? input.close() }
                while true {
                    let data = try input.read(upToCount: 4 * 1_048_576) ?? Data()
                    if data.isEmpty { break }
                    try output.write(contentsOf: data)
                }
                try? input.close()
            }
            try output.close()
        } catch {
            try? output.close()
            throw error
        }

        let finalSize = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard Int64(finalSize) == totalBytes else { throw NexusDownloadError.incompleteFile }
        try? fm.removeItem(at: partsDirectory)
        progress(.init(downloadedBytes: totalBytes,
                       totalBytes: totalBytes,
                       bytesPerSecond: Double(max(0, totalBytes - resumedBytes)) / max(Date().timeIntervalSince(started), 0.05),
                       activeChunks: 0,
                       completedChunks: totalChunks,
                       totalChunks: totalChunks))
        return destination.path
    }

    private static func downloadChunk(remoteURL: URL,
                                      range: ClosedRange<Int64>,
                                      destination: URL) async throws -> Int64 {
        let expected = range.upperBound - range.lowerBound + 1
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                var request = URLRequest(url: remoteURL)
                request.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range")
                request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                request.timeoutInterval = 120
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw NexusDownloadError.invalidResponse }
                guard http.statusCode == 206 else {
                    if http.statusCode == 200 { throw NexusDownloadError.rangeUnsupported }
                    throw NexusDownloadError.invalidResponse
                }
                guard Int64(data.count) == expected else { throw NexusDownloadError.incompleteFile }
                try data.write(to: destination, options: .atomic)
                return expected
            } catch NexusDownloadError.rangeUnsupported {
                throw NexusDownloadError.rangeUnsupported
            } catch {
                lastError = error
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(350_000_000 * (attempt + 1)))
                }
            }
        }
        throw lastError ?? NexusDownloadError.invalidResponse
    }

    private static func probe(remoteURL: URL) async -> (totalBytes: Int64, supportsRanges: Bool) {
        var total: Int64 = 0
        var supportsRanges = false
        do {
            var head = URLRequest(url: remoteURL)
            head.httpMethod = "HEAD"
            head.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            head.timeoutInterval = 30
            let (_, response) = try await URLSession.shared.data(for: head)
            if let http = response as? HTTPURLResponse {
                if http.expectedContentLength > 0 { total = http.expectedContentLength }
                if let linked = http.value(forHTTPHeaderField: "X-Linked-Size"), let n = Int64(linked) { total = n }
                if let length = http.value(forHTTPHeaderField: "Content-Length"), let n = Int64(length), n > total { total = n }
                supportsRanges = http.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased().contains("bytes") == true
            }
        } catch {}

        if total > 0 && !supportsRanges {
            do {
                var request = URLRequest(url: remoteURL)
                request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
                request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                request.timeoutInterval = 20
                let (_, response) = try await URLSession.shared.bytes(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 206 {
                    supportsRanges = true
                    if let contentRange = http.value(forHTTPHeaderField: "Content-Range"),
                       let slash = contentRange.lastIndex(of: "/"),
                       let n = Int64(contentRange[contentRange.index(after: slash)...]) {
                        total = n
                    }
                }
            } catch {}
        }
        return (total, supportsRanges)
    }

    private static func remoteURL(for modelPath: String) -> URL? {
        if modelPath.hasPrefix("https://") { return URL(string: modelPath) }
        guard modelPath.hasPrefix("hf://") else { return nil }
        let raw = String(modelPath.dropFirst(5))
        let pieces = raw.split(separator: "/", omittingEmptySubsequences: true)
        guard pieces.count >= 3 else { return nil }
        let owner = pieces[0]
        let repo = pieces[1]
        let file = pieces.dropFirst(2).joined(separator: "/")
        let urlString = "https://huggingface.co/\(owner)/\(repo)/resolve/main/\(file)?download=true"
        return URL(string: urlString)
    }
}

struct NexusPortableModel: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let path: String
    let source: String
    let approximateSize: String
    var enabledForEnsemble: Bool

    var isPreset: Bool { path.hasPrefix("hf://") || path.hasPrefix("https://") }

    var estimatedBytes: UInt64 {
        let cleaned = approximateSize.lowercased().replacingOccurrences(of: "~", with: "")
        let number = cleaned.split(whereSeparator: { !$0.isNumber && $0 != "." }).compactMap { Double($0) }.first ?? 0
        if cleaned.contains("gb") { return UInt64(number * 1_073_741_824) }
        if cleaned.contains("mb") { return UInt64(number * 1_048_576) }
        return 0
    }
}

@MainActor
final class NexusPortableModelStore: ObservableObject {
    static let shared = NexusPortableModelStore()

    @Published var models: [NexusPortableModel] = []
    @Published var activeModelID: String = ""
    @Published var status: String = "No portable model loaded"
    @Published var progress: Double = 0
    @Published var busy = false
    @Published var lastError = ""
    @Published var downloadSnapshot: NexusDownloadSnapshot = .zero
    @Published var downloadingModelID = ""

    private var loadedModel: Model?
    private var chat: Chat?
    private var installedPaths: [String:String] = [:]
    private var memoryObserver: NSObjectProtocol?

    private let defaultsKey = "nexus.portable.models.v2"
    private let installedKey = "nexus.portable.installed.v3"
    private let activeKey = "nexus.portable.active.v2"

    init() {
        loadCatalog()
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.releaseForMemoryPressure() }
        }
    }

    static let qwenTinyPreset = NexusPortableModel(id: "qwen3-0.6b-q4", name: "Qwen3 0.6B Q4", path: "hf://NobodyWho/Qwen_Qwen3-0.6B-GGUF/Qwen_Qwen3-0.6B-Q4_K_M.gguf", source: "NobodyWho-compatible GGUF • multilingual reasoning", approximateSize: "~484 MB", enabledForEnsemble: true)
    static let smolTinyPreset = NexusPortableModel(id: "smollm2-360m-instruct-q4", name: "SmolLM2 360M Instruct Q4", path: "hf://tensorblock/SmolLM2-360M-Instruct-GGUF/SmolLM2-360M-Instruct-Q4_K_M.gguf", source: "GGUF • very small instruction model", approximateSize: "~271 MB", enabledForEnsemble: false)
    static let qwenBalancedPreset = NexusPortableModel(id: "qwen3-1.7b-q4", name: "Qwen3 1.7B Q4", path: "hf://NobodyWho/Qwen_Qwen3-1.7B-GGUF/Qwen_Qwen3-1.7B-Q4_K_M.gguf", source: "NobodyWho-compatible GGUF • higher quality, heavier", approximateSize: "~1.28 GB", enabledForEnsemble: false)
    static let qwen4BPreset = NexusPortableModel(id: "qwen3-4b-q4", name: "Qwen3 4B Q4_K_M", path: "hf://tensorblock/Qwen_Qwen3-4B-GGUF/Qwen3-4B-Q4_K_M.gguf", source: "GGUF • large optional reasoning model", approximateSize: "~2.50 GB", enabledForEnsemble: false)
    static let qwen8BPreset = NexusPortableModel(id: "qwen3-8b-q4", name: "Qwen3 8B Q4_K_M", path: "hf://tensorblock/Qwen_Qwen3-8B-GGUF/Qwen3-8B-Q4_K_M.gguf", source: "GGUF • very large optional reasoning model", approximateSize: "~5.03 GB", enabledForEnsemble: false)

    var memorySummary: String {
        let ramGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
        return String(format: "%.1f GB physical memory • adaptive context windows • one heavyweight model kept resident at a time", ramGB)
    }

    func addPreset(_ preset: NexusPortableModel) {
        guard !models.contains(where: { $0.id == preset.id }) else { return }
        models.append(preset)
        persist()
    }

    func isDownloaded(_ model: NexusPortableModel) -> Bool {
        if !model.isPreset { return FileManager.default.fileExists(atPath: model.path) }
        guard let path = installedPaths[model.id] else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    func download(_ model: NexusPortableModel) async {
        guard model.isPreset, !busy else { return }
        busy = true
        progress = 0.01
        downloadSnapshot = .zero
        downloadingModelID = model.id
        lastError = ""
        status = "Preparing parallel download • \(model.name)"
        defer {
            busy = false
            downloadingModelID = ""
        }
        do {
            _ = try await ensureLocalPath(for: model)
            progress = 1
            status = "Downloaded • \(model.name) • tap Load when needed"
        } catch {
            lastError = error.localizedDescription
            status = "Download failed • partial chunks are kept for resume"
            progress = downloadSnapshot.fraction
        }
    }

    func importGGUF(_ url: URL) async {
        guard !busy else { return }
        busy = true
        progress = 0.05
        status = "Copying local GGUF model…"
        lastError = ""
        defer { busy = false }
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let destination = try await Task.detached(priority: .utility) { () throws -> URL in
                let fm = FileManager.default
                let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("NEXUS-Models", isDirectory: true)
                try fm.createDirectory(at: base, withIntermediateDirectories: true)
                let destination = base.appendingPathComponent(url.lastPathComponent)
                if fm.fileExists(atPath: destination.path) {
                    let srcSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
                    let dstSize = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -2
                    if srcSize != dstSize {
                        try fm.removeItem(at: destination)
                        try fm.copyItem(at: url, to: destination)
                    }
                } else { try fm.copyItem(at: url, to: destination) }
                return destination
            }.value
            progress = 0.86
            let bytes = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let sizeText = bytes >= 1_073_741_824 ? String(format: "~%.2f GB", Double(bytes) / 1_073_741_824.0) : "~\(max(1, bytes / 1_048_576)) MB"
            let id = "local:\(destination.lastPathComponent.lowercased())"
            let item = NexusPortableModel(id: id, name: destination.deletingPathExtension().lastPathComponent, path: destination.path, source: "Imported local GGUF", approximateSize: sizeText, enabledForEnsemble: models.filter { $0.enabledForEnsemble }.count < 2)
            if let idx = models.firstIndex(where: { $0.id == id }) { models[idx] = item } else { models.append(item) }
            persist()
            progress = 1
            status = "Model installed • tap Load"
        } catch {
            lastError = error.localizedDescription
            status = "Model import failed"
        }
    }

    func load(_ model: NexusPortableModel) async {
        guard !busy else { return }
        if !canSafelyAttemptLoad(model) {
            status = "\(model.name) is larger than the safe runtime budget for this device. It can stay downloaded, but loading it could trigger iOS memory termination."
            lastError = "Choose a smaller quantization/model or a device with more RAM."
            return
        }
        busy = true
        progress = 0.02
        status = "Preparing \(model.name)…"
        lastError = ""
        defer { busy = false; downloadingModelID = "" }
        do {
            let localPath = try await ensureLocalPath(for: model)
            releaseRuntime(clearSelection: true)
            status = "Loading \(model.name)…"
            progress = max(progress, 0.93)
            let runtimeModel = try await Model.load(modelPath: localPath, useGpu: true)
            let context = min(runtimeModel.maxCtx, recommendedContextSize(for: model))
            let session = try Chat(model: runtimeModel, systemPrompt: "You are a private on-device NEXUS reasoning model. Be concise, distinguish evidence from inference, and never invent personal facts.", contextSize: context, threadCount: nil)
            loadedModel = runtimeModel
            chat = session
            activeModelID = model.id
            UserDefaults.standard.set(model.id, forKey: activeKey)
            progress = 1
            status = "Loaded • \(model.name) • Metal/GGUF • \(context) token context"
        } catch {
            lastError = error.localizedDescription
            status = "Could not load \(model.name)"
            releaseRuntime(clearSelection: true)
        }
    }

    func unload() {
        releaseRuntime(clearSelection: true)
        status = "Portable model unloaded • memory released"
        progress = 0
    }

    func respond(_ prompt: String, systemContext: String = "") async -> String? {
        guard let chat else { return nil }
        do {
            try await chat.resetHistory()
            if !systemContext.isEmpty { try await chat.setSystemPrompt("You are a private NEXUS on-device reasoning model. Use only supplied evidence for personal claims. \(String(systemContext.prefix(5000)))") }
            return try await chat.ask(String(prompt.prefix(9000))).completed().trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func streamRespond(_ prompt: String,
                       systemContext: String = "",
                       onPartial: @escaping (String) -> Void) async -> String? {
        guard let chat else { return nil }
        do {
            try await chat.resetHistory()
            if !systemContext.isEmpty {
                try await chat.setSystemPrompt("You are a private NEXUS on-device reasoning model. Use only supplied evidence for personal claims. \(String(systemContext.prefix(5000)))")
            }
            let stream = chat.ask(String(prompt.prefix(9000)))
            var full = ""
            for try await token in stream {
                full += token
                onPartial(full)
            }
            return full.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func opinionFromModel(_ model: NexusPortableModel, question: String, context: String) async -> NexusModelOpinion? {
        guard model.enabledForEnsemble else { return nil }
        guard canSafelyAttemptLoad(model) else {
            return NexusModelOpinion(id: "portable:\(model.id)", model: model.name, role: "local GGUF generative interpretation", finding: "Skipped because this model exceeds the device's conservative memory budget.", confidence: 0.10, evidence: ["Memory-safety guard prevented a likely iOS jetsam termination."])
        }
        do {
            status = "Consulting \(model.name)…"
            let system = "You are one independent local analyst in an ensemble. Use only supplied evidence. Return a concise interpretation plus uncertainty. Do not infer protected/sensitive traits."
            let prompt = "QUESTION: \(question)\nEVIDENCE:\n\(String(context.prefix(5600)))\nGive one concise evidence-based opinion."
            let localChat: Chat
            if model.id == activeModelID, let loadedModel {
                let contextSize = min(loadedModel.maxCtx, min(recommendedContextSize(for: model), 2560))
                localChat = try Chat(model: loadedModel, systemPrompt: system, contextSize: contextSize, threadCount: nil)
            } else {
                if shouldReleaseActiveBeforeLoading(model) { releaseRuntime(clearSelection: true) }
                let localPath = try await ensureLocalPath(for: model)
                let runtimeModel = try await Model.load(modelPath: localPath, useGpu: true)
                let contextSize = min(runtimeModel.maxCtx, min(recommendedContextSize(for: model), 2560))
                localChat = try Chat(model: runtimeModel, systemPrompt: system, contextSize: contextSize, threadCount: nil)
            }
            let output = try await localChat.ask(prompt).completed()
            if activeModelID.isEmpty { status = "Ensemble pass complete • temporary model memory released" }
            return NexusModelOpinion(id: "portable:\(model.id)", model: model.name, role: "local GGUF generative interpretation", finding: output.trimmingCharacters(in: .whitespacesAndNewlines), confidence: 0.62, evidence: ["Local GGUF runtime • no API key", model.source])
        } catch {
            return NexusModelOpinion(id: "portable:\(model.id)", model: model.name, role: "local GGUF generative interpretation", finding: "This optional model could not complete its inference pass: \(error.localizedDescription)", confidence: 0.10, evidence: [])
        }
    }

    func ensembleModels() -> [NexusPortableModel] {
        var enabled = models.filter { $0.enabledForEnsemble }
        if let idx = enabled.firstIndex(where: { $0.id == activeModelID }), idx != 0 { let active = enabled.remove(at: idx); enabled.insert(active, at: 0) }
        return Array(enabled.prefix(2))
    }

    func toggleEnsemble(_ model: NexusPortableModel) {
        guard let idx = models.firstIndex(where: { $0.id == model.id }) else { return }
        if !models[idx].enabledForEnsemble && models.filter({ $0.enabledForEnsemble }).count >= 2 {
            status = "For memory safety, NEXUS uses at most two portable LLMs in one ensemble pass."
            return
        }
        models[idx].enabledForEnsemble.toggle()
        persist()
    }

    func removeDownloadedWeights(_ model: NexusPortableModel) {
        if activeModelID == model.id { releaseRuntime(clearSelection: true) }
        guard let path = installedPaths[model.id] else { return }
        do {
            if FileManager.default.fileExists(atPath: path) { try FileManager.default.removeItem(atPath: path) }
            installedPaths.removeValue(forKey: model.id)
            persistInstalledPaths()
            progress = 0
            downloadSnapshot = .zero
            status = "Removed downloaded weights for \(model.name)"
        } catch {
            lastError = error.localizedDescription
            status = "Could not remove downloaded weights"
        }
    }

    func delete(_ model: NexusPortableModel) {
        if activeModelID == model.id { releaseRuntime(clearSelection: true) }
        if model.isPreset { removeDownloadedWeights(model) } else { try? FileManager.default.removeItem(atPath: model.path) }
        models.removeAll { $0.id == model.id }
        persist()
        status = "Removed \(model.name) from NEXUS"
    }

    private func ensureLocalPath(for model: NexusPortableModel) async throws -> String {
        if !model.isPreset { return model.path }
        if let path = installedPaths[model.id], FileManager.default.fileExists(atPath: path) { return path }

        downloadingModelID = model.id
        status = "Downloading \(model.name) with parallel chunks…"
        let filename = model.path.split(separator: "/").last.map(String.init) ?? "\(model.id).gguf"
        let path = try await NexusParallelDownloader.download(modelPath: model.path,
                                                              destinationName: "\(model.id)-\(filename)",
                                                              estimatedBytes: model.estimatedBytes,
                                                              concurrency: 4) { snapshot in
            Task { @MainActor in
                self.downloadSnapshot = snapshot
                self.progress = snapshot.fraction * 0.90
                self.status = "Downloading \(model.name) • \(snapshot.detailText)"
            }
        }
        installedPaths[model.id] = path
        persistInstalledPaths()
        return path
    }

    private func recommendedContextSize(for model: NexusPortableModel) -> UInt32 {
        let ramGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
        let sizeGB = Double(effectiveModelBytes(model)) / 1_073_741_824.0
        if ramGB <= 4.5 { return sizeGB > 1.0 ? 1536 : 2048 }
        if ramGB <= 6.5 { return sizeGB > 2.0 ? 1536 : (sizeGB > 1.0 ? 2048 : 3072) }
        if ramGB <= 8.5 { return sizeGB > 3.5 ? 1536 : (sizeGB > 1.5 ? 2560 : 4096) }
        return sizeGB > 5.0 ? 2048 : 4096
    }

    private func effectiveModelBytes(_ model: NexusPortableModel) -> UInt64 {
        let path = installedPaths[model.id] ?? (!model.isPreset ? model.path : "")
        if !path.isEmpty, let n = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey]).fileSize, n > 0 { return UInt64(n) }
        return model.estimatedBytes
    }

    private func canSafelyAttemptLoad(_ model: NexusPortableModel) -> Bool {
        let bytes = effectiveModelBytes(model)
        guard bytes > 0 else { return true }
        let estimatedRuntime = Double(bytes) * 1.28 + 420_000_000
        return estimatedRuntime < Double(ProcessInfo.processInfo.physicalMemory) * 0.72
    }

    private func shouldReleaseActiveBeforeLoading(_ next: NexusPortableModel) -> Bool {
        guard !activeModelID.isEmpty, let active = models.first(where: { $0.id == activeModelID }), active.id != next.id else { return false }
        let combined = Double(effectiveModelBytes(active) + effectiveModelBytes(next)) * 1.30 + 650_000_000
        return combined > Double(ProcessInfo.processInfo.physicalMemory) * 0.50
    }

    private func releaseRuntime(clearSelection: Bool) {
        chat?.stopGeneration(); chat = nil; loadedModel = nil
        if clearSelection { activeModelID = ""; UserDefaults.standard.removeObject(forKey: activeKey) }
    }

    private func releaseForMemoryPressure() {
        guard chat != nil || loadedModel != nil else { return }
        releaseRuntime(clearSelection: true)
        progress = 0
        status = "iOS reported memory pressure • released local model RAM; downloaded weights remain installed"
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(models) { UserDefaults.standard.set(data, forKey: defaultsKey) }
        persistInstalledPaths()
    }
    private func persistInstalledPaths() {
        if let data = try? JSONEncoder().encode(installedPaths) { UserDefaults.standard.set(data, forKey: installedKey) }
    }
    private func loadCatalog() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey), let decoded = try? JSONDecoder().decode([NexusPortableModel].self, from: data) { models = decoded }
        if let data = UserDefaults.standard.data(forKey: installedKey), let decoded = try? JSONDecoder().decode([String:String].self, from: data) { installedPaths = decoded.filter { FileManager.default.fileExists(atPath: $0.value) } }
        activeModelID = ""
        UserDefaults.standard.removeObject(forKey: activeKey)
    }
}

struct NexusGGUFDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let type = UTType(filenameExtension: "gguf") ?? .data
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [type, .data], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: NexusGGUFDocumentPicker
        init(parent: NexusGGUFDocumentPicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { if let url = urls.first { parent.onPick(url) } }
    }
}

struct PortableModelsV7View: View {
    @ObservedObject private var store = NexusPortableModelStore.shared
    @State private var picker = false

    var body: some View {
        List {
            Section {
                Text("Additional LLMs run fully on-device through an iOS Swift runtime powered by llama.cpp. Model weights are optional and separate from the NEXUS IPA.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(store.memorySummary).font(.caption2).foregroundStyle(.secondary)
                if store.busy || store.progress > 0 {
                    ProgressView(value: store.progress) { Text(store.status).font(.caption) }
                    if store.downloadSnapshot.totalBytes > 0 { Text(store.downloadSnapshot.detailText).font(.caption2).monospacedDigit().foregroundStyle(.secondary) }
                } else { Text(store.status).font(.caption).foregroundStyle(.secondary) }
                if !store.lastError.isEmpty { Text(store.lastError).font(.caption).foregroundStyle(.red) }
            }

            Section("iPhone presets") {
                preset(NexusPortableModelStore.smolTinyPreset, note: "Smallest preset; useful as a fast second opinion.")
                preset(NexusPortableModelStore.qwenTinyPreset, note: "Better multilingual reasoning while still relatively compact.")
                preset(NexusPortableModelStore.qwenBalancedPreset, note: "Balanced local reasoning for devices with more free memory.")
                preset(NexusPortableModelStore.qwen4BPreset, note: "Large 4B model; NEXUS reduces context automatically on tighter devices.")
                preset(NexusPortableModelStore.qwen8BPreset, note: "Very large 8B model; downloadable on any device with storage, load is memory-gated for safety.")
            }

            Section("Your GGUF models") {
                Button { picker = true } label: { Label("Import any compatible GGUF", systemImage: "square.and.arrow.down") }
                ForEach(store.models) { model in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(model.name).font(.headline)
                                Text("\(model.approximateSize) • \(model.source)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.activeModelID == model.id { Label("Loaded", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green) }
                            else if store.isDownloaded(model) { Label("On device", systemImage: "internaldrive.fill").font(.caption2).foregroundStyle(.secondary) }
                        }
                        if store.downloadingModelID == model.id && store.downloadSnapshot.totalBytes > 0 {
                            ProgressView(value: store.downloadSnapshot.fraction)
                            Text(store.downloadSnapshot.detailText).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                        }
                        HStack {
                            if model.isPreset && !store.isDownloaded(model) { Button("Download") { Task { await store.download(model) } }.buttonStyle(.bordered).disabled(store.busy) }
                            Button(store.activeModelID == model.id ? "Reload" : "Load") { Task { await store.load(model) } }.buttonStyle(.borderedProminent).disabled(store.busy)
                            Button(model.enabledForEnsemble ? "In ensemble" : "Add to ensemble") { store.toggleEnsemble(model) }.buttonStyle(.bordered)
                        }
                        HStack {
                            if model.isPreset && store.isDownloaded(model) { Button(role: .destructive) { store.removeDownloadedWeights(model) } label: { Label("Remove weights", systemImage: "externaldrive.badge.minus") }.buttonStyle(.bordered) }
                            Button(role: .destructive) { store.delete(model) } label: { Label("Remove model", systemImage: "trash") }.buttonStyle(.bordered)
                        }
                    }.padding(.vertical, 4)
                }
            }

            Section("Download engine") {
                Text("Large model downloads use resumable 8 MB byte ranges with up to four concurrent network lanes when the host supports HTTP ranges. NEXUS keeps completed chunks on disk, resumes after interruption, merges them only after verification, and falls back to the runtime's normal downloader when range requests are unavailable.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Performance & memory policy") {
                Text("NEXUS downloads large weights without loading them into RAM. During inference it uses adaptive context sizes, reuses one loaded model for independent sessions, evaluates optional ensemble models sequentially, releases heavyweight runtime objects under iOS memory pressure, and blocks only loads that are likely to be terminated by iOS. All model choices, downloads, imports and ensemble features remain available.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Portable Local LLMs")
        .sheet(isPresented: $picker) { NexusGGUFDocumentPicker { url in picker = false; Task { await store.importGGUF(url) } } }
    }

    @ViewBuilder private func preset(_ model: NexusPortableModel, note: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "cpu.fill").foregroundStyle(.cyan).padding(.top, 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.name).font(.headline)
                Text("\(model.approximateSize) • \(note)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(store.models.contains(where: { $0.id == model.id }) ? "Added" : "Add") { store.addPreset(model) }.buttonStyle(.bordered).disabled(store.models.contains(where: { $0.id == model.id }))
        }
    }
}
