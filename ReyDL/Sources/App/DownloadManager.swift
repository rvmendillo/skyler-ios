import Foundation
import UIKit

final class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate, URLSessionTaskDelegate, URLSessionDataDelegate {
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
    @Published private var segmentProgressByJob: [UUID: [Int: Double]] = [:]

    private static let segmentLimitKey = "reydl.segmentLimit"
    private static let legacySessionIdentifier = "com.rvmendillo.reydl.background.v2"
    private static let userAgent = "REYDL/1.1.3 (iOS; Accelerated Download Manager)"

    private let ioQueue = DispatchQueue(label: "com.rvmendillo.reydl.io", qos: .utility)
    private let taskLock = NSLock()
    private var ignoredTasks = Set<ObjectIdentifier>()
    private var fallbackJobs = Set<UUID>()
    private var segmentBytesByJob: [UUID: [Int: Int64]] = [:]

    /// Primary transfer session. Live sessions start immediately in sideloaded builds.
    private lazy var liveSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.httpMaximumConnectionsPerHost = 64
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60 * 60 * 24 * 7
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = [
            "User-Agent": Self.userAgent,
            "Accept": "*/*",
            "Accept-Encoding": "identity"
        ]
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    /// Header-only range-capability probe. The body is cancelled as soon as response headers arrive.
    private lazy var probeSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = [
            "User-Agent": Self.userAgent,
            "Accept": "*/*",
            "Accept-Encoding": "identity"
        ]
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    /// Only retained to cancel tasks left behind by pre-1.1.1 builds.
    private lazy var legacyBackgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.legacySessionIdentifier)
        config.waitsForConnectivity = true
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private override init() {
        let savedLimit = UserDefaults.standard.integer(forKey: Self.segmentLimitKey)
        segmentLimit = savedLimit == 0 ? 16 : savedLimit
        super.init()
        loadState()
        _ = liveSession
        _ = probeSession
        _ = legacyBackgroundSession
        retireLegacyTasksAndRestoreState()
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
            self.probeRangeSupport(item.id)
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

    func segmentProgress(for item: DownloadItem) -> [Double] {
        guard item.mode == .segmented, item.segmentCount > 1 else { return [] }
        let snapshot = segmentProgressByJob[item.id] ?? [:]
        return (0..<item.segmentCount).map { index in
            min(1, max(0, snapshot[index] ?? 0))
        }
    }

    func pause(_ id: UUID) {
        probeSession.getAllTasks { tasks in
            tasks.filter { Self.jobID(from: $0.taskDescription) == id }.forEach { task in
                self.markIgnored(task)
                task.cancel()
            }
        }
        liveSession.getAllTasks { tasks in
            tasks.filter { Self.jobID(from: $0.taskDescription) == id }.forEach { $0.suspend() }
            DispatchQueue.main.async {
                self.update(id) { $0.state = .paused }
            }
        }
    }

    func resume(_ id: UUID) {
        liveSession.getAllTasks { tasks in
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
            self.segmentProgressByJob.removeValue(forKey: id)
            self.segmentBytesByJob.removeValue(forKey: id)
            self.items.removeAll { $0.id == id }
            self.persistState()
        }
    }

    func completedURL(for item: DownloadItem) -> URL? {
        guard item.state == .completed else { return nil }
        let url = downloadsDirectory().appendingPathComponent(item.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Range probe and scheduling

    private func restart(_ id: UUID) {
        guard let item = itemSnapshot(id), let url = URL(string: item.urlString) else { return }
        cancelTasks(for: id)
        ioQueue.async { try? FileManager.default.removeItem(at: self.partsDirectory(id)) }
        taskLock.lock()
        fallbackJobs.remove(id)
        taskLock.unlock()
        segmentProgressByJob.removeValue(forKey: id)
        segmentBytesByJob.removeValue(forKey: id)
        update(id) {
            $0.state = .probing
            $0.mode = .unknown
            $0.totalBytes = 0
            $0.receivedBytes = 0
            $0.segmentCount = 0
            $0.completedSegments = 0
            $0.errorMessage = nil
        }
        probeRangeSupport(id, overrideURL: url)
    }

    /// Sends a real one-byte Range GET and decides using the actual HTTP status.
    /// A 206 response proves that multiple independent byte-range connections are supported.
    /// The probe body is cancelled in didReceive response, so a server that ignores Range
    /// cannot accidentally stream the whole file into memory.
    private func probeRangeSupport(_ id: UUID, overrideURL: URL? = nil) {
        guard let item = itemSnapshot(id), let url = overrideURL ?? URL(string: item.urlString) else { return }

        var request = baseRequest(url: url)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.timeoutInterval = 15

        let task = probeSession.dataTask(with: request)
        task.taskDescription = "\(id.uuidString)|probe|0"
        task.resume()

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            guard let current = self.itemSnapshot(id), current.state == .probing else { return }
            self.cancelProbeTasks(for: id)
            if let currentURL = URL(string: current.urlString) {
                self.startSingle(id: id, url: currentURL, reason: "Range probe timed out")
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let descriptor = Self.parseDescription(dataTask.taskDescription), descriptor.kind == "probe" else {
            completionHandler(.allow)
            return
        }

        let http = response as? HTTPURLResponse
        let finalURL = response.url ?? dataTask.originalRequest?.url
        let status = http?.statusCode ?? 0
        let total = http.flatMap(Self.totalLengthFromProbe) ?? 0
        let suggestedName = response.suggestedFilename.map { Self.sanitizedFileName($0) }
        let etag = http?.value(forHTTPHeaderField: "ETag")
        let modified = http?.value(forHTTPHeaderField: "Last-Modified")

        completionHandler(.cancel)

        DispatchQueue.main.async {
            guard let current = self.itemSnapshot(descriptor.id), current.state == .probing,
                  let url = finalURL ?? URL(string: current.urlString) else { return }

            self.update(descriptor.id) {
                if let suggestedName, !suggestedName.isEmpty { $0.fileName = suggestedName }
                if total > 0 { $0.totalBytes = total }
                $0.etag = etag
                $0.lastModified = modified
            }

            if status == 206 && total >= 2 * 1024 * 1024 {
                self.startSegmented(id: descriptor.id, url: url, total: total)
            } else {
                let reason = status == 206
                    ? "File too small for Turbo splitting"
                    : "Server returned HTTP \(status) instead of 206 Partial Content"
                self.startSingle(id: descriptor.id, url: url, reason: reason)
            }
        }
    }

    private func startSegmented(id: UUID, url: URL, total: Int64) {
        guard var item = itemSnapshot(id), item.state == .probing else { return }

        let maxRanges = max(2, min(64, segmentLimit))
        let targetChunk: Int64 = 32 * 1024 * 1024
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
        segmentProgressByJob[id] = Dictionary(uniqueKeysWithValues: (0..<count).map { ($0, 0.0) })
        segmentBytesByJob[id] = Dictionary(uniqueKeysWithValues: (0..<count).map { ($0, Int64(0)) })
        set(item)

        ioQueue.sync {
            let directory = partsDirectory(id)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        for index in 0..<count {
            let start = Int64(index) * chunkSize
            let end = min(total - 1, start + chunkSize - 1)
            guard start <= end else { continue }

            var request = baseRequest(url: url)
            request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
            if let validator = item.etag ?? item.lastModified {
                request.setValue(validator, forHTTPHeaderField: "If-Range")
            }

            let task = liveSession.downloadTask(with: request)
            task.taskDescription = "\(id.uuidString)|segment|\(index)"
            task.resume()
        }
    }

    private func startSingle(id: UUID, url: URL, reason: String? = nil) {
        guard let current = itemSnapshot(id), current.state == .probing || current.mode == .segmented else { return }

        segmentProgressByJob.removeValue(forKey: id)
        segmentBytesByJob.removeValue(forKey: id)
        update(id) {
            $0.state = .downloading
            $0.mode = .single
            $0.receivedBytes = 0
            $0.segmentCount = 1
            $0.completedSegments = 0
            $0.errorMessage = reason
        }

        let task = liveSession.downloadTask(with: baseRequest(url: url))
        task.taskDescription = "\(id.uuidString)|single|0"
        task.resume()
    }

    private func baseRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        return request
    }

    private func cancelProbeTasks(for id: UUID) {
        probeSession.getAllTasks { tasks in
            for task in tasks where Self.jobID(from: task.taskDescription) == id {
                self.markIgnored(task)
                task.cancel()
            }
        }
    }

    private func cancelTasks(for id: UUID) {
        cancelProbeTasks(for: id)
        liveSession.getAllTasks { tasks in
            for task in tasks where Self.jobID(from: task.taskDescription) == id {
                self.markIgnored(task)
                task.cancel()
            }
        }
        legacyBackgroundSession.getAllTasks { tasks in
            for task in tasks where Self.jobID(from: task.taskDescription) == id {
                self.markIgnored(task)
                task.cancel()
            }
        }
    }

    private func markIgnored(_ task: URLSessionTask) {
        taskLock.lock()
        ignoredTasks.insert(ObjectIdentifier(task))
        taskLock.unlock()
    }

    // MARK: - Download delegates

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let descriptor = Self.parseDescription(downloadTask.taskDescription) else { return }

        if descriptor.kind == "segment",
           let http = downloadTask.response as? HTTPURLResponse,
           http.statusCode != 206 {
            DispatchQueue.main.async { self.fallbackToSingle(descriptor.id) }
            return
        }

        DispatchQueue.main.async {
            if descriptor.kind == "segment" {
                var byteValues = self.segmentBytesByJob[descriptor.id] ?? [:]
                byteValues[descriptor.index] = max(0, totalBytesWritten)
                self.segmentBytesByJob[descriptor.id] = byteValues

                var progressValues = self.segmentProgressByJob[descriptor.id] ?? [:]
                if totalBytesExpectedToWrite > 0 {
                    progressValues[descriptor.index] = min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
                }
                self.segmentProgressByJob[descriptor.id] = progressValues

                let sum = byteValues.values.reduce(Int64(0), +)
                self.update(descriptor.id, persist: false) { item in
                    item.receivedBytes = item.totalBytes > 0 ? min(item.totalBytes, sum) : sum
                    if item.state != .paused { item.state = .downloading }
                }
            } else {
                self.update(descriptor.id, persist: false) { item in
                    item.receivedBytes = max(0, totalBytesWritten)
                    if item.totalBytes <= 0, totalBytesExpectedToWrite > 0 {
                        item.totalBytes = totalBytesExpectedToWrite
                    }
                    if item.state != .paused { item.state = .downloading }
                }
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

            let directory = partsDirectory(descriptor.id)
            let destination = directory.appendingPathComponent(String(format: "part-%03d", descriptor.index))
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let size = try claimDownloadedFile(from: location, to: destination)
                guard size > 0 else { throw Self.emptyFileError() }
                DispatchQueue.main.async {
                    var progressValues = self.segmentProgressByJob[descriptor.id] ?? [:]
                    progressValues[descriptor.index] = 1
                    self.segmentProgressByJob[descriptor.id] = progressValues

                    var byteValues = self.segmentBytesByJob[descriptor.id] ?? [:]
                    byteValues[descriptor.index] = size
                    self.segmentBytesByJob[descriptor.id] = byteValues
                    self.segmentFinished(descriptor.id)
                }
            } catch {
                DispatchQueue.main.async {
                    self.fail(descriptor.id, "Could not save thread \(descriptor.index + 1): \(error.localizedDescription)")
                }
            }
            return
        }

        let finalURL = uniqueFinalURL(for: item)
        do {
            let size = try claimDownloadedFile(from: location, to: finalURL)
            guard size > 0 else { throw Self.emptyFileError() }
            DispatchQueue.main.async {
                self.segmentProgressByJob.removeValue(forKey: descriptor.id)
                self.segmentBytesByJob.removeValue(forKey: descriptor.id)
                self.update(descriptor.id) {
                    $0.fileName = finalURL.lastPathComponent
                    $0.state = .completed
                    $0.completedSegments = 1
                    $0.totalBytes = size
                    $0.receivedBytes = size
                    $0.errorMessage = nil
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.fail(descriptor.id, "Download finished, but REYDL could not persist the file: \(error.localizedDescription)")
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let descriptor = Self.parseDescription(task.taskDescription) else { return }

        taskLock.lock()
        let ignored = ignoredTasks.remove(ObjectIdentifier(task)) != nil
        taskLock.unlock()
        if ignored || descriptor.kind == "probe" { return }

        if (error as NSError).code == NSURLErrorCancelled { return }

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

    // MARK: - Segment completion / fallback

    private func fallbackToSingle(_ id: UUID) {
        guard let item = itemSnapshot(id), item.mode == .segmented, let url = URL(string: item.urlString) else { return }

        taskLock.lock()
        let alreadyFallingBack = fallbackJobs.contains(id)
        if !alreadyFallingBack { fallbackJobs.insert(id) }
        taskLock.unlock()
        guard !alreadyFallingBack else { return }

        segmentProgressByJob.removeValue(forKey: id)
        segmentBytesByJob.removeValue(forKey: id)
        update(id) {
            $0.mode = .single
            $0.receivedBytes = 0
            $0.segmentCount = 1
            $0.completedSegments = 0
            $0.errorMessage = "Server ignored one or more byte-range requests; switched to one direct stream."
        }

        liveSession.getAllTasks { tasks in
            for task in tasks where Self.jobID(from: task.taskDescription) == id {
                self.markIgnored(task)
                task.cancel()
            }
            self.ioQueue.async { try? FileManager.default.removeItem(at: self.partsDirectory(id)) }
            DispatchQueue.main.async {
                self.taskLock.lock()
                self.fallbackJobs.remove(id)
                self.taskLock.unlock()
                self.startSingleFromFallback(id: id, url: url)
            }
        }
    }

    private func startSingleFromFallback(id: UUID, url: URL) {
        segmentProgressByJob.removeValue(forKey: id)
        segmentBytesByJob.removeValue(forKey: id)
        update(id) {
            $0.state = .downloading
            $0.mode = .single
            $0.receivedBytes = 0
            $0.segmentCount = 1
            $0.completedSegments = 0
        }
        let task = liveSession.downloadTask(with: baseRequest(url: url))
        task.taskDescription = "\(id.uuidString)|single|0"
        task.resume()
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
        let liveBytes = segmentBytesByJob[id]?.values.reduce(Int64(0), +) ?? 0
        item.receivedBytes = min(item.totalBytes, max(stableBytes, liveBytes))
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
                for index in 0..<item.segmentCount {
                    let partURL = directory.appendingPathComponent(String(format: "part-%03d", index))
                    let input = try FileHandle(forReadingFrom: partURL)
                    while true {
                        let data = try input.read(upToCount: 4 * 1024 * 1024) ?? Data()
                        if data.isEmpty { break }
                        try output.write(contentsOf: data)
                    }
                    try input.close()
                }
                try output.synchronize()
                try output.close()

                let finalSize = Self.fileSize(finalURL)
                guard finalSize > 0 else { throw Self.emptyFileError() }
                if item.totalBytes > 0, finalSize != item.totalBytes {
                    throw NSError(
                        domain: "REYDL",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Joined file size \(finalSize) does not match expected size \(item.totalBytes). Parts were kept for safety."]
                    )
                }

                try? FileManager.default.removeItem(at: directory)
                DispatchQueue.main.async {
                    self.segmentProgressByJob.removeValue(forKey: id)
                    self.segmentBytesByJob.removeValue(forKey: id)
                    self.update(id) {
                        $0.fileName = finalURL.lastPathComponent
                        $0.state = .completed
                        $0.totalBytes = finalSize
                        $0.receivedBytes = finalSize
                        $0.completedSegments = $0.segmentCount
                        $0.errorMessage = nil
                    }
                }
            } catch {
                try? FileManager.default.removeItem(at: finalURL)
                DispatchQueue.main.async {
                    self.fail(id, "Could not assemble/save file: \(error.localizedDescription)")
                }
            }
        }
    }

    private func fail(_ id: UUID, _ message: String) {
        update(id) {
            $0.state = .failed
            $0.errorMessage = message
        }
    }

    // MARK: - Persistence / migration

    private func retireLegacyTasksAndRestoreState() {
        legacyBackgroundSession.getAllTasks { tasks in
            for task in tasks {
                self.markIgnored(task)
                task.cancel()
            }
            DispatchQueue.main.async {
                for index in self.items.indices where self.items[index].state != .completed {
                    self.items[index].state = .paused
                    if self.items[index].errorMessage == nil {
                        self.items[index].errorMessage = "Tap resume to restart with the current REYDL engine."
                    }
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
                // Active transfers continue even if persistence fails.
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

    /// URLSession's temporary download location is valid only during didFinishDownloadingTo.
    /// Claim it synchronously before returning from that delegate callback.
    private func claimDownloadedFile(from source: URL, to destination: URL) throws -> Int64 {
        let manager = FileManager.default
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: destination.path) {
            try manager.removeItem(at: destination)
        }

        do {
            try manager.moveItem(at: source, to: destination)
        } catch {
            if manager.fileExists(atPath: destination.path) {
                try? manager.removeItem(at: destination)
            }
            try manager.copyItem(at: source, to: destination)
            try? manager.removeItem(at: source)
        }

        guard manager.fileExists(atPath: destination.path) else {
            throw NSError(domain: "REYDL", code: 3, userInfo: [NSLocalizedDescriptionKey: "Saved file is missing after transfer."])
        }
        let size = Self.fileSize(destination)
        guard size > 0 else {
            try? manager.removeItem(at: destination)
            throw Self.emptyFileError()
        }
        return size
    }

    // MARK: - HTTP helpers

    private static func totalLengthFromProbe(_ response: HTTPURLResponse) -> Int64 {
        if let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
           let slash = contentRange.lastIndex(of: "/") {
            let suffix = contentRange[contentRange.index(after: slash)...]
            if suffix != "*", let total = Int64(suffix), total > 0 {
                return total
            }
        }
        return totalLength(from: response)
    }

    private static func totalLength(from response: HTTPURLResponse) -> Int64 {
        if let raw = response.value(forHTTPHeaderField: "Content-Length"), let value = Int64(raw), value > 0 {
            return value
        }
        return response.expectedContentLength > 0 ? response.expectedContentLength : 0
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private static func emptyFileError() -> NSError {
        NSError(domain: "REYDL", code: 1, userInfo: [NSLocalizedDescriptionKey: "The saved file is empty."])
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
