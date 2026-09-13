import Foundation
import UIKit

final class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
    static let shared = DownloadManager()

    @Published private(set) var items: [DownloadItem] = []
    @Published var segmentLimit: Int {
        didSet {
            let clamped = max(2, min(64, segmentLimit))
            if clamped != segmentLimit {
                segmentLimit = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: Self.segmentLimitKey)
        }
    }

    private static let segmentLimitKey = "reydl.segmentLimit"
    private static let sessionIdentifier = "com.rvmendillo.reydl.background.v2"

    private let ioQueue = DispatchQueue(label: "com.rvmendillo.reydl.io", qos: .utility)
    private let taskLock = NSLock()
    private var ignoredTaskIDs = Set<Int>()

    private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.waitsForConnectivity = true
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.httpMaximumConnectionsPerHost = 64
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60 * 60 * 24 * 7
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private override init() {
        let savedLimit = UserDefaults.standard.integer(forKey: Self.segmentLimitKey)
        segmentLimit = savedLimit == 0 ? 16 : savedLimit
        super.init()
        loadState()
        _ = backgroundSession
        restoreTaskStates()
    }

    // MARK: - Public API

    func add(url: URL, suggestedName: String? = nil) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }

        let fallback = url.lastPathComponent.isEmpty
            ? "download-\(Int(Date().timeIntervalSince1970)).bin"
            : url.lastPathComponent
        let name = Self.sanitizedFileName(suggestedName?.isEmpty == false ? suggestedName! : fallback)

        let item = DownloadItem(
            id: UUID(),
            urlString: url.absoluteString,
            fileName: name,
            state: .probing,
            mode: .unknown,
            createdAt: Date(),
            totalBytes: 0,
            receivedBytes: 0,
            segmentCount: 0,
            completedSegments: 0,
            errorMessage: nil,
            etag: nil,
            lastModified: nil
        )

        DispatchQueue.main.async {
            self.items.insert(item, at: 0)
            self.persistState()
            self.probe(item.id)
        }
    }

    func add(urlString: String) {
        let raw = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw) else { return }
        add(url: url)
    }

    func handleDeepLink(_ deepLink: URL) {
        guard deepLink.scheme?.lowercased() == "reydl", deepLink.host == "add" else { return }
        guard let components = URLComponents(url: deepLink, resolvingAgainstBaseURL: false),
              let raw = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let url = URL(string: raw) else { return }
        let name = components.queryItems?.first(where: { $0.name == "name" })?.value
        add(url: url, suggestedName: name)
    }

    func pause(_ id: UUID) {
        backgroundSession.getAllTasks { tasks in
            tasks.filter { Self.jobID(from: $0.taskDescription) == id }.forEach { $0.suspend() }
            DispatchQueue.main.async {
                self.update(id) { $0.state = .paused }
            }
        }
    }

    func resume(_ id: UUID) {
        backgroundSession.getAllTasks { tasks in
            let matching = tasks.filter { Self.jobID(from: $0.taskDescription) == id }
            if matching.isEmpty {
                DispatchQueue.main.async { self.restart(id) }
                return
            }
            matching.forEach { $0.resume() }
            DispatchQueue.main.async {
                self.update(id) {
                    $0.state = .downloading
                    $0.errorMessage = nil
                }
            }
        }
    }

    func retry(_ id: UUID) {
        restart(id)
    }

    func remove(_ id: UUID) {
        cancelTasks(for: id)
        ioQueue.async {
            try? FileManager.default.removeItem(at: self.partsDirectory(id))
            if let item = self.itemSnapshot(id), item.state == .completed {
                try? FileManager.default.removeItem(at: self.downloadsDirectory().appendingPathComponent(item.fileName))
            }
        }
        DispatchQueue.main.async {
            self.items.removeAll { $0.id == id }
            self.persistState()
        }
    }

    func completedURL(for item: DownloadItem) -> URL? {
        guard item.state == .completed else { return nil }
        let url = downloadsDirectory().appendingPathComponent(item.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Probing and scheduling

    private func restart(_ id: UUID) {
        guard let item = itemSnapshot(id), let url = URL(string: item.urlString) else { return }
        cancelTasks(for: id)
        ioQueue.async { try? FileManager.default.removeItem(at: self.partsDirectory(id)) }
        update(id) {
            $0.state = .probing
            $0.mode = .unknown
            $0.totalBytes = 0
            $0.receivedBytes = 0
            $0.segmentCount = 0
            $0.completedSegments = 0
            $0.errorMessage = nil
        }
        probe(id, overrideURL: url)
    }

    private func probe(_ id: UUID, overrideURL: URL? = nil) {
        guard let item = itemSnapshot(id), let url = overrideURL ?? URL(string: item.urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30

        URLSession.shared.dataTask(with: request) { _, response, error in
            guard let http = response as? HTTPURLResponse, error == nil else {
                DispatchQueue.main.async { self.startSingle(id: id, url: url) }
                return
            }

            let total = http.expectedContentLength
            let acceptsRanges = (http.value(forHTTPHeaderField: "Accept-Ranges") ?? "")
                .lowercased().contains("bytes")
            let suggestedName = response?.suggestedFilename.map { Self.sanitizedFileName($0) }
            let etag = http.value(forHTTPHeaderField: "ETag")
            let modified = http.value(forHTTPHeaderField: "Last-Modified")

            DispatchQueue.main.async {
                self.update(id) {
                    if let suggestedName, !suggestedName.isEmpty { $0.fileName = suggestedName }
                    if total > 0 { $0.totalBytes = total }
                    $0.etag = etag
                    $0.lastModified = modified
                }
                if acceptsRanges && total >= 2 * 1024 * 1024 {
                    self.startSegmented(id: id, url: url, total: total)
                } else {
                    self.startSingle(id: id, url: url)
                }
            }
        }.resume()
    }

    private func startSegmented(id: UUID, url: URL, total: Int64) {
        guard var item = itemSnapshot(id) else { return }

        let maxRanges = max(2, min(64, segmentLimit))
        let targetChunk: Int64 = 8 * 1024 * 1024
        let desiredRanges = max(2, Int((total + targetChunk - 1) / targetChunk))
        let count = min(maxRanges, desiredRanges)
        let chunkSize = (total + Int64(count) - 1) / Int64(count)

        item.state = .downloading
        item.mode = .segmented
        item.totalBytes = total
        item.receivedBytes = 0
        item.segmentCount = count
        item.completedSegments = 0
        item.errorMessage = nil
        set(item)

        ioQueue.sync {
            let directory = partsDirectory(id)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        for index in 0..<count {
            let start = Int64(index) * chunkSize
            let end = min(total - 1, start + chunkSize - 1)
            guard start <= end else { continue }

            var request = URLRequest(url: url)
            request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
            if let validator = item.etag ?? item.lastModified {
                request.setValue(validator, forHTTPHeaderField: "If-Range")
            }

            let task = backgroundSession.downloadTask(with: request)
            task.taskDescription = "\(id.uuidString)|segment|\(index)"
            task.resume()
        }
    }

    private func startSingle(id: UUID, url: URL) {
        update(id) {
            $0.state = .downloading
            $0.mode = .single
            $0.receivedBytes = 0
            $0.segmentCount = 1
            $0.completedSegments = 0
            $0.errorMessage = nil
        }
        let task = backgroundSession.downloadTask(with: url)
        task.taskDescription = "\(id.uuidString)|single|0"
        task.resume()
    }

    private func cancelTasks(for id: UUID) {
        backgroundSession.getAllTasks { tasks in
            for task in tasks where Self.jobID(from: task.taskDescription) == id {
                self.taskLock.lock()
                self.ignoredTaskIDs.insert(task.taskIdentifier)
                self.taskLock.unlock()
                task.cancel()
            }
        }
    }

    // MARK: - URLSession delegates

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let id = Self.jobID(from: downloadTask.taskDescription) else { return }
        DispatchQueue.main.async {
            self.update(id, persist: false) { item in
                if item.mode == .single {
                    item.receivedBytes = totalBytesWritten
                    if item.totalBytes <= 0, totalBytesExpectedToWrite > 0 {
                        item.totalBytes = totalBytesExpectedToWrite
                    }
                } else {
                    item.receivedBytes = min(item.totalBytes, max(0, item.receivedBytes + bytesWritten))
                }
                if item.state != .paused { item.state = .downloading }
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let descriptor = Self.parseDescription(downloadTask.taskDescription),
              let item = itemSnapshot(descriptor.id) else { return }

        if descriptor.kind == "segment" {
            guard item.mode == .segmented else { return }
            let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 206 else {
                DispatchQueue.main.async { self.fallbackToSingle(descriptor.id) }
                return
            }

            ioQueue.async {
                let directory = self.partsDirectory(descriptor.id)
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let destination = directory.appendingPathComponent(String(format: "part-%03d", descriptor.index))
                try? FileManager.default.removeItem(at: destination)
                do {
                    try FileManager.default.moveItem(at: location, to: destination)
                    DispatchQueue.main.async { self.segmentFinished(descriptor.id) }
                } catch {
                    DispatchQueue.main.async { self.fail(descriptor.id, error.localizedDescription) }
                }
            }
            return
        }

        ioQueue.async {
            let finalURL = self.uniqueFinalURL(for: item)
            do {
                try? FileManager.default.createDirectory(at: finalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: location, to: finalURL)
                let size = Self.fileSize(finalURL)
                DispatchQueue.main.async {
                    self.update(descriptor.id) {
                        $0.fileName = finalURL.lastPathComponent
                        $0.state = .completed
                        $0.completedSegments = 1
                        if $0.totalBytes <= 0 { $0.totalBytes = size }
                        $0.receivedBytes = $0.totalBytes > 0 ? $0.totalBytes : size
                    }
                }
            } catch {
                DispatchQueue.main.async { self.fail(descriptor.id, error.localizedDescription) }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let descriptor = Self.parseDescription(task.taskDescription) else { return }

        taskLock.lock()
        let ignored = ignoredTaskIDs.remove(task.taskIdentifier) != nil
        taskLock.unlock()
        if ignored { return }

        DispatchQueue.main.async {
            guard let current = self.itemSnapshot(descriptor.id) else { return }
            if current.state == .paused || current.state == .completed { return }
            if descriptor.kind == "segment" && current.mode != .segmented { return }
            self.fail(descriptor.id, error.localizedDescription)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            guard let delegate = UIApplication.shared.delegate as? AppDelegate else { return }
            let completion = delegate.backgroundCompletionHandler
            delegate.backgroundCompletionHandler = nil
            completion?()
        }
    }

    // MARK: - Segment completion

    private func fallbackToSingle(_ id: UUID) {
        guard let item = itemSnapshot(id), item.mode == .segmented, let url = URL(string: item.urlString) else { return }

        update(id) {
            $0.mode = .single
            $0.receivedBytes = 0
            $0.segmentCount = 1
            $0.completedSegments = 0
        }

        backgroundSession.getAllTasks { tasks in
            for task in tasks where Self.jobID(from: task.taskDescription) == id {
                self.taskLock.lock()
                self.ignoredTaskIDs.insert(task.taskIdentifier)
                self.taskLock.unlock()
                task.cancel()
            }
            self.ioQueue.async { try? FileManager.default.removeItem(at: self.partsDirectory(id)) }
            DispatchQueue.main.async { self.startSingle(id: id, url: url) }
        }
    }

    private func segmentFinished(_ id: UUID) {
        guard var item = itemSnapshot(id), item.mode == .segmented else { return }

        let directory = partsDirectory(id)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        let parts = files.filter { $0.lastPathComponent.hasPrefix("part-") }

        item.completedSegments = parts.count
        let stableBytes = parts.reduce(Int64(0)) { $0 + Self.fileSize($1) }
        item.receivedBytes = min(item.totalBytes, max(item.receivedBytes, stableBytes))
        set(item)

        guard parts.count == item.segmentCount else { return }
        assemble(id)
    }

    private func assemble(_ id: UUID) {
        guard let item = itemSnapshot(id) else { return }
        update(id) { $0.state = .assembling }

        ioQueue.async {
            let directory = self.partsDirectory(id)
            let finalURL = self.uniqueFinalURL(for: item)
            FileManager.default.createFile(atPath: finalURL.path, contents: nil)

            do {
                let output = try FileHandle(forWritingTo: finalURL)
                defer { try? output.close() }

                for index in 0..<item.segmentCount {
                    let partURL = directory.appendingPathComponent(String(format: "part-%03d", index))
                    let input = try FileHandle(forReadingFrom: partURL)
                    defer { try? input.close() }

                    while true {
                        let data = try input.read(upToCount: 4 * 1024 * 1024) ?? Data()
                        if data.isEmpty { break }
                        try output.write(contentsOf: data)
                    }
                }

                try? FileManager.default.removeItem(at: directory)
                let finalSize = Self.fileSize(finalURL)
                DispatchQueue.main.async {
                    self.update(id) {
                        $0.fileName = finalURL.lastPathComponent
                        $0.state = .completed
                        if $0.totalBytes <= 0 { $0.totalBytes = finalSize }
                        $0.receivedBytes = $0.totalBytes > 0 ? $0.totalBytes : finalSize
                        $0.completedSegments = $0.segmentCount
                    }
                }
            } catch {
                try? FileManager.default.removeItem(at: finalURL)
                DispatchQueue.main.async { self.fail(id, error.localizedDescription) }
            }
        }
    }

    private func fail(_ id: UUID, _ message: String) {
        update(id) {
            $0.state = .failed
            $0.errorMessage = message
        }
    }

    // MARK: - Persistence

    private func restoreTaskStates() {
        backgroundSession.getAllTasks { tasks in
            let activeIDs = Set(tasks.compactMap { Self.jobID(from: $0.taskDescription) })
            DispatchQueue.main.async {
                for index in self.items.indices where self.items[index].state != .completed {
                    self.items[index].state = activeIDs.contains(self.items[index].id) ? .downloading : .paused
                }
                self.persistState()
            }
        }
    }

    private func update(
        _ id: UUID,
        persist: Bool = true,
        _ change: @escaping (inout DownloadItem) -> Void
    ) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.update(id, persist: persist, change) }
            return
        }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
        if persist { persistState() }
    }

    private func set(_ item: DownloadItem) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.set(item) }
            return
        }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        persistState()
    }

    private func itemSnapshot(_ id: UUID) -> DownloadItem? {
        if Thread.isMainThread { return items.first(where: { $0.id == id }) }
        var result: DownloadItem?
        DispatchQueue.main.sync { result = self.items.first(where: { $0.id == id }) }
        return result
    }

    private func persistState() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.persistState() }
            return
        }
        let snapshot = items
        ioQueue.async {
            do {
                try? FileManager.default.createDirectory(at: self.supportDirectory(), withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: self.stateURL(), options: .atomic)
            } catch {
                // Downloads remain active even if a state snapshot cannot be written.
            }
        }
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: stateURL()),
              let decoded = try? JSONDecoder().decode([DownloadItem].self, from: data) else { return }
        items = decoded
    }

    // MARK: - Files

    private func supportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("REYDL", isDirectory: true)
    }

    private func downloadsDirectory() -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("REYDL Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func stateURL() -> URL {
        supportDirectory().appendingPathComponent("downloads.json")
    }

    private func partsDirectory(_ id: UUID) -> URL {
        supportDirectory().appendingPathComponent("parts/\(id.uuidString)", isDirectory: true)
    }

    private func uniqueFinalURL(for item: DownloadItem) -> URL {
        let directory = downloadsDirectory()
        let original = Self.sanitizedFileName(item.fileName)
        var candidate = directory.appendingPathComponent(original)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        let ext = candidate.pathExtension
        let stem = candidate.deletingPathExtension().lastPathComponent
        var suffix = 2
        repeat {
            let filename = ext.isEmpty ? "\(stem) \(suffix)" : "\(stem) \(suffix).\(ext)"
            candidate = directory.appendingPathComponent(filename)
            suffix += 1
        } while FileManager.default.fileExists(atPath: candidate.path)
        return candidate
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private static func sanitizedFileName(_ input: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        let cleaned = input.components(separatedBy: illegal).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "download.bin" : cleaned
    }

    private static func jobID(from description: String?) -> UUID? {
        guard let raw = description?.split(separator: "|").first else { return nil }
        return UUID(uuidString: String(raw))
    }

    private static func parseDescription(_ description: String?) -> (id: UUID, kind: String, index: Int)? {
        guard let description else { return nil }
        let parts = description.split(separator: "|")
        guard parts.count >= 3,
              let id = UUID(uuidString: String(parts[0])),
              let index = Int(parts[2]) else { return nil }
        return (id, String(parts[1]), index)
    }
}
