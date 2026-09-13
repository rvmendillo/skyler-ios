import Foundation
import UIKit

final class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
    static let shared = DownloadManager()

    @Published private(set) var items: [DownloadItem] = []
    @Published var segmentLimit: Int {
        didSet {
            let value = max(2, min(64, segmentLimit))
            if value != segmentLimit { segmentLimit = value; return }
            UserDefaults.standard.set(value, forKey: Self.segmentLimitKey)
        }
    }

    private static let segmentLimitKey = "reydl.segmentLimit"
    private static let sessionIdentifier = "com.rvmendillo.reydl.background.v1"
    private let ioQueue = DispatchQueue(label: "com.rvmendillo.reydl.io", qos: .utility)
    private let stateLock = NSLock()
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
        let saved = UserDefaults.standard.integer(forKey: Self.segmentLimitKey)
        self.segmentLimit = saved == 0 ? 16 : saved
        super.init()
        loadState()
        _ = backgroundSession
        restoreTaskStates()
    }

    func add(url: URL, suggestedName: String? = nil) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }

        let name = Self.sanitizedFileName(suggestedName ?? url.lastPathComponent.nonEmpty ?? "download-\(Date().timeIntervalSince1970).bin")
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
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return }
        add(url: url)
    }

    func handleDeepLink(_ deepLink: URL) {
        guard deepLink.scheme?.lowercased() == "reydl" else { return }
        guard deepLink.host == "add" else { return }
        guard let components = URLComponents(url: deepLink, resolvingAgainstBaseURL: false),
              let raw = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let url = URL(string: raw) else { return }
        let name = components.queryItems?.first(where: { $0.name == "name" })?.value
        add(url: url, suggestedName: name)
    }

    func pause(_ id: UUID) {
        backgroundSession.getAllTasks { tasks in
            for task in tasks where Self.jobID(from: task.taskDescription) == id {
                task.suspend()
            }
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
        backgroundSession.getAllTasks { tasks in
            for task in tasks where Self.jobID(from: task.taskDescription) == id {
                self.stateLock.lock(); self.ignoredTaskIDs.insert(task.taskIdentifier); self.stateLock.unlock()
                task.cancel()
            }
        }
        ioQueue.async {
            try? FileManager.default.removeItem(at: self.partsDirectory(id))
            if let item = self.itemSnapshot(id), let output = self.completedURL(for: item) {
                try? FileManager.default.removeItem(at: output)
            }
        }
        DispatchQueue.main.async {
            self.items.removeAll { $0.id == id }
            self.persistState()
        }
    }

    func completedURL(for item: DownloadItem) -> URL? {
        guard item.state == .completed else { return nil }
        return downloadsDirectory().appendingPathComponent(item.fileName)
    }

    private func restart(_ id: UUID) {
        guard let item = itemSnapshot(id), let url = URL(string: item.urlString) else { return }
        backgroundSession.getAllTasks { tasks in
            for task in tasks where Self.jobID(from: task.taskDescription) == id {
                self.stateLock.lock(); self.ignoredTaskIDs.insert(task.taskIdentifier); self.stateLock.unlock()
                task.cancel()
            }
            self.ioQueue.async { try? FileManager.default.removeItem(at: self.partsDirectory(id)) }
            DispatchQueue.main.async {
                self.update(id) {
                    $0.state = .probing
                    $0.mode = .unknown
                    $0.totalBytes = 0
                    $0.receivedBytes = 0
                    $0.segmentCount = 0
                    $0.completedSegments = 0
                    $0.errorMessage = nil
                }
                self.probe(id, overrideURL: url)
            }
        }
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
            let acceptRanges = (http.value(forHTTPHeaderField: "Accept-Ranges") ?? "").lowercased().contains("bytes")
            let name = response?.suggestedFilename.map(Self.sanitizedFileName)
            let etag = http.value(forHTTPHeaderField: "ETag")
            let modified = http.value(forHTTPHeaderField: "Last-Modified")

            DispatchQueue.main.async {
                self.update(id) {
                    if let name, !name.isEmpty { $0.fileName = name }
                    if total > 0 { $0.totalBytes = total }
                    $0.etag = etag
                    $0.lastModified = modified
                }
                if acceptRanges && total >= 2 * 1024 * 1024 {
                    self.startSegmented(id: id, url: url, total: total)
                } else {
                    self.startSingle(id: id, url: url)
                }
            }
        }.resume()
    }

    private func startSegmented(id: UUID, url: URL, total: Int64) {
        guard var item = itemSnapshot(id) else { return }
        let limit = max(2, min(64, segmentLimit))
        let targetChunk: Int64 = 8 * 1024 * 1024
        let suggested = max(2, Int((total + targetChunk - 1) / targetChunk))
        let count = min(limit, suggested)
        let chunk = (total + Int64(count) - 1) / Int64(count)

        item.state = .downloading
        item.mode = .segmented
        item.totalBytes = total
        item.segmentCount = count
        item.completedSegments = 0
        item.receivedBytes = 0
        set(item)

        ioQueue.sync {
            let dir = partsDirectory(id)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        for index in 0..<count {
            let start = Int64(index) * chunk
            let end = min(total - 1, start + chunk - 1)
            guard start <= end else { continue }
            var request = URLRequest(url: url)
            request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
            if let validator = item.etag ?? item.lastModified {
                request.setValue(validator, forHTTPHeaderField: "If-Range")
            }
            let task = backgroundSession.downloadTask(with: request)
            task.taskDescription = "\(id.uuidString)|segment|\(index)|\(start)|\(end)"
            task.resume()
        }
    }

    private func startSingle(id: UUID, url: URL) {
        update(id) {
            $0.state = .downloading
            $0.mode = .single
            $0.segmentCount = 1
            $0.completedSegments = 0
            $0.errorMessage = nil
        }
        let task = backgroundSession.downloadTask(with: url)
        task.taskDescription = "\(id.uuidString)|single|0|0|0"
        task.resume()
    }

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
                item.receivedBytes = min(max(item.receivedBytes + bytesWritten, totalBytesWritten), max(item.totalBytes, totalBytesExpectedToWrite))
                if item.totalBytes <= 0 && totalBytesExpectedToWrite > 0 { item.totalBytes = totalBytesExpectedToWrite }
                if item.state != .paused { item.state = .downloading }
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let parsed = Self.parseDescription(downloadTask.taskDescription) else { return }
        guard let item = itemSnapshot(parsed.id) else { return }

        if parsed.kind == "segment" {
            guard item.mode == .segmented else { return }
            let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 206 else {
                DispatchQueue.main.async { self.fallbackToSingleAfterRangeFailure(parsed.id) }
                return
            }

            ioQueue.async {
                let dir = self.partsDirectory(parsed.id)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let destination = dir.appendingPathComponent(String(format: "part-%03d", parsed.index))
                try? FileManager.default.removeItem(at: destination)
                do {
                    try FileManager.default.moveItem(at: location, to: destination)
                } catch {
                    DispatchQueue.main.async { self.fail(parsed.id, error.localizedDescription) }
                    return
                }
                DispatchQueue.main.async { self.segmentFinished(parsed.id) }
            }
        } else {
            ioQueue.async {
                do {
                    let finalURL = self.uniqueFinalURL(for: item)
                    try? FileManager.default.createDirectory(at: finalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try FileManager.default.moveItem(at: location, to: finalURL)
                    DispatchQueue.main.async {
                        self.update(parsed.id) {
                            $0.fileName = finalURL.lastPathComponent
                            $0.state = .completed
                            $0.completedSegments = 1
                            if $0.totalBytes <= 0 {
                                $0.totalBytes = (try? finalURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? $0.receivedBytes
                            }
                            $0.receivedBytes = $0.totalBytes
                        }
                    }
                } catch {
                    DispatchQueue.main.async { self.fail(parsed.id, error.localizedDescription) }
                }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let parsed = Self.parseDescription(task.taskDescription) else { return }
        stateLock.lock()
        let ignored = ignoredTaskIDs.remove(task.taskIdentifier) != nil
        stateLock.unlock()
        if ignored { return }

        DispatchQueue.main.async {
            guard let current = self.itemSnapshot(parsed.id) else { return }
            if current.state == .paused || current.state == .completed { return }
            if parsed.kind == "segment" && current.mode != .segmented { return }
            self.fail(parsed.id, error.localizedDescription)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            if let delegate = UIApplication.shared.delegate as? AppDelegate {
                let completion = delegate.backgroundCompletionHandler
                delegate.backgroundCompletionHandler = nil
                completion?()
            }
        }
    }

    private func fallbackToSingleAfterRangeFailure(_ id: UUID) {
        guard let item = itemSnapshot(id), item.mode == .segmented, let url = URL(string: item.urlString) else { return }
        update(id) {
            $0.mode = .single
            $0.receivedBytes = 0
            $0.segmentCount = 1
            $0.completedSegments = 0
        }
        backgroundSession.getAllTasks { tasks in
            for task in tasks where Self.jobID(from: task.taskDescription) == id && Self.parseDescription(task.taskDescription)?.kind == "segment" {
                self.stateLock.lock(); self.ignoredTaskIDs.insert(task.taskIdentifier); self.stateLock.unlock()
                task.cancel()
            }
            self.ioQueue.async { try? FileManager.default.removeItem(at: self.partsDirectory(id)) }
            DispatchQueue.main.async { self.startSingle(id: id, url: url) }
        }
    }

    private func segmentFinished(_ id: UUID) {
        guard var item = itemSnapshot(id), item.mode == .segmented else { return }
        let dir = partsDirectory(id)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let parts = files.filter { $0.lastPathComponent.hasPrefix("part-") }
        item.completedSegments = parts.count
        let stableBytes = parts.reduce(Int64(0)) { result, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return result + Int64(size)
        }
        item.receivedBytes = min(item.totalBytes, max(item.receivedBytes, stableBytes))
        set(item)
        guard parts.count == item.segmentCount else { return }
        assemble(id)
    }

    private func assemble(_ id: UUID) {
        guard let item = itemSnapshot(id) else { return }
        update(id) { $0.state = .assembling }
        ioQueue.async {
            let dir = self.partsDirectory(id)
            let finalURL = self.uniqueFinalURL(for: item)
            FileManager.default.createFile(atPath: finalURL.path, contents: nil)
            guard let out = try? FileHandle(forWritingTo: finalURL) else {
                DispatchQueue.main.async { self.fail(id, "Could not create output file") }
                return
            }
            defer { try? out.close() }

            do {
                for index in 0..<item.segmentCount {
                    let part = dir.appendingPathComponent(String(format: "part-%03d", index))
                    let input = try FileHandle(forReadingFrom: part)
                    while autoreleasepool(invoking: {
                        let data = try? input.read(upToCount: 4 * 1024 * 1024)
                        guard let data, !data.isEmpty else { return false }
                        try? out.write(contentsOf: data)
                        return true
                    }) {}
                    try input.close()
                }
                try? FileManager.default.removeItem(at: dir)
                DispatchQueue.main.async {
                    self.update(id) {
                        $0.fileName = finalURL.lastPathComponent
                        $0.state = .completed
                        $0.receivedBytes = $0.totalBytes
                        $0.completedSegments = $0.segmentCount
                    }
                }
            } catch {
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

    private func restoreTaskStates() {
        backgroundSession.getAllTasks { tasks in
            let activeIDs = Set(tasks.compactMap { Self.jobID(from: $0.taskDescription) })
            DispatchQueue.main.async {
                for index in self.items.indices {
                    guard self.items[index].state != .completed else { continue }
                    self.items[index].state = activeIDs.contains(self.items[index].id) ? .downloading : .paused
                }
                self.persistState()
            }
        }
    }

    private func update(_ id: UUID, persist: Bool = true, _ change: (inout DownloadItem) -> Void) {
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
                let data = try JSONEncoder().encode(snapshot)
                try? FileManager.default.createDirectory(at: self.supportDirectory(), withIntermediateDirectories: true)
                try data.write(to: self.stateURL(), options: .atomic)
            } catch { }
        }
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: stateURL()),
              let decoded = try? JSONDecoder().decode([DownloadItem].self, from: data) else { return }
        items = decoded
    }

    private func supportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("REYDL", isDirectory: true)
    }

    private func downloadsDirectory() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("REYDL Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func stateURL() -> URL { supportDirectory().appendingPathComponent("downloads.json") }
    private func partsDirectory(_ id: UUID) -> URL { supportDirectory().appendingPathComponent("parts/\(id.uuidString)", isDirectory: true) }

    private func uniqueFinalURL(for item: DownloadItem) -> URL {
        let base = downloadsDirectory()
        let original = Self.sanitizedFileName(item.fileName)
        var candidate = base.appendingPathComponent(original)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }
        let ext = candidate.pathExtension
        let stem = candidate.deletingPathExtension().lastPathComponent
        var index = 2
        repeat {
            let name = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            candidate = base.appendingPathComponent(name)
            index += 1
        } while FileManager.default.fileExists(atPath: candidate.path)
        return candidate
    }

    private static func sanitizedFileName(_ input: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        let cleaned = input.components(separatedBy: illegal).joined(separator: "-")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "download.bin"
    }

    private static func jobID(from description: String?) -> UUID? {
        guard let first = description?.split(separator: "|").first else { return nil }
        return UUID(uuidString: String(first))
    }

    private static func parseDescription(_ description: String?) -> (id: UUID, kind: String, index: Int)? {
        guard let description else { return nil }
        let parts = description.split(separator: "|")
        guard parts.count >= 3, let id = UUID(uuidString: String(parts[0])), let index = Int(parts[2]) else { return nil }
        return (id, String(parts[1]), index)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
