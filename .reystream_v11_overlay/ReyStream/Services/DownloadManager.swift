import Foundation

struct DownloadJob: Identifiable, Codable {
    enum Status: String, Codable { case queued, probing, downloading, paused, merging, complete, failed, cancelled }
    let id: UUID
    let url: URL
    var title: String
    var progress: Double
    var status: Status
    var localURL: URL?
    var error: String?
    var totalBytes: Int64?
    var downloadedBytes: Int64
    var connections: Int
    var supportsRanges: Bool?
    var speedBytesPerSecond: Double
    var createdAt: Date
}

enum DownloadError: LocalizedError {
    case invalidURL, youtubeNotDownloadable
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Use a valid HTTP or HTTPS media URL."
        case .youtubeNotDownloadable: return "YouTube links use the YouTube player and are not passed to the downloader."
        }
    }
}

private struct SegmentState: Codable {
    var index: Int
    var start: Int64
    var end: Int64
    var received: Int64
    var fileName: String
    var completed: Bool
    var expected: Int64 { end - start + 1 }
}

private struct StoredDownloadState: Codable {
    var jobs: [DownloadJob]
    var segments: [String: [SegmentState]]
}

private enum TaskReference {
    case segment(jobID: UUID, segmentIndex: Int)
    case single(jobID: UUID)
}

@MainActor
final class DownloadManager: NSObject, ObservableObject, URLSessionDataDelegate, URLSessionDownloadDelegate {
    @Published var jobs: [DownloadJob] = []
    private var segments: [UUID: [SegmentState]] = [:]
    private var taskRefs: [Int: TaskReference] = [:]
    private var segmentHandles: [Int: FileHandle] = [:]
    private var singleResumeData: [UUID: Data] = [:]
    private var lastSamples: [UUID: (date: Date, bytes: Int64)] = [:]
    private var fallingBackToSingle = Set<UUID>()

    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.default
        c.waitsForConnectivity = true
        c.allowsExpensiveNetworkAccess = true
        c.allowsConstrainedNetworkAccess = true
        c.httpMaximumConnectionsPerHost = 24
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 60 * 60 * 24
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }()

    private var stateURL: URL { LibraryPaths.documents.appendingPathComponent("reystream-downloads.json") }
    private var partsRoot: URL { LibraryPaths.documents.appendingPathComponent("DownloadParts", isDirectory: true) }
    private var connectionsPerDownload: Int { max(1, min(8, UserDefaults.standard.integer(forKey: "downloadConnections").nonZero(or: 4))) }
    private var maxActiveJobs: Int { max(1, min(5, UserDefaults.standard.integer(forKey: "simultaneousDownloads").nonZero(or: 3))) }

    override init() {
        super.init()
        LibraryPaths.prepare()
        try? FileManager.default.createDirectory(at: partsRoot, withIntermediateDirectories: true)
        loadState()
    }

    func enqueue(_ url: URL, title: String? = nil) throws {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { throw DownloadError.invalidURL }
        guard !YouTubeURL.isRestrictedDownloadHost(url) else { throw DownloadError.youtubeNotDownloadable }
        let defaultTitle = url.lastPathComponent.isEmpty ? (url.host ?? "Download") : url.lastPathComponent
        let job = DownloadJob(id: UUID(), url: url, title: title?.isEmpty == false ? title! : defaultTitle,
                              progress: 0, status: .queued, localURL: nil, error: nil, totalBytes: nil,
                              downloadedBytes: 0, connections: 1, supportsRanges: nil,
                              speedBytesPerSecond: 0, createdAt: Date())
        jobs.insert(job, at: 0)
        saveState()
        pumpQueue()
    }

    func pause(_ job: DownloadJob) {
        guard let i = index(job.id), [.downloading, .probing].contains(jobs[i].status) else { return }
        jobs[i].status = .paused
        jobs[i].speedBytesPerSecond = 0
        let taskIDs = taskRefs.compactMap { key, ref -> Int? in
            switch ref {
            case .segment(let id, _), .single(let id): return id == job.id ? key : nil
            }
        }
        session.getAllTasks { tasks in
            for task in tasks where taskIDs.contains(task.taskIdentifier) {
                if let downloadTask = task as? URLSessionDownloadTask {
                    downloadTask.cancel(byProducingResumeData: { data in
                        Task { @MainActor in
                            if let data {
                                self.singleResumeData[job.id] = data
                                self.writeResumeData(data, for: job.id)
                            }
                        }
                    })
                } else { task.cancel() }
            }
        }
        closeHandles(for: job.id)
        saveState()
        pumpQueue()
    }

    func resume(_ job: DownloadJob) {
        guard let i = index(job.id), [.paused, .failed, .cancelled].contains(jobs[i].status) else { return }
        jobs[i].error = nil
        jobs[i].status = .queued
        saveState()
        pumpQueue()
    }

    func cancel(_ job: DownloadJob) {
        guard let i = index(job.id) else { return }
        jobs[i].status = .cancelled
        jobs[i].speedBytesPerSecond = 0
        session.getAllTasks { tasks in
            for task in tasks {
                guard let ref = self.taskRefs[task.taskIdentifier] else { continue }
                switch ref {
                case .segment(let id, _), .single(let id): if id == job.id { task.cancel() }
                }
            }
        }
        closeHandles(for: job.id)
        cleanupParts(job.id)
        singleResumeData[job.id] = nil
        try? FileManager.default.removeItem(at: resumeDataURL(job.id))
        saveState()
        pumpQueue()
    }

    func remove(_ job: DownloadJob) {
        cancel(job)
        jobs.removeAll { $0.id == job.id }
        segments[job.id] = nil
        saveState()
    }

    func retry(_ job: DownloadJob) {
        cleanupParts(job.id)
        segments[job.id] = nil
        singleResumeData[job.id] = nil
        try? FileManager.default.removeItem(at: resumeDataURL(job.id))
        guard let i = index(job.id) else { return }
        jobs[i].downloadedBytes = 0
        jobs[i].progress = 0
        jobs[i].error = nil
        jobs[i].supportsRanges = nil
        jobs[i].status = .queued
        saveState()
        pumpQueue()
    }

    func clearFinished() {
        let removable = jobs.filter { [.complete, .cancelled].contains($0.status) }
        for job in removable { cleanupParts(job.id); try? FileManager.default.removeItem(at: resumeDataURL(job.id)) }
        jobs.removeAll { [.complete, .cancelled].contains($0.status) }
        saveState()
    }

    private func pumpQueue() {
        let active = jobs.filter { [.probing, .downloading, .merging].contains($0.status) }.count
        guard active < maxActiveJobs else { return }
        let slots = maxActiveJobs - active
        for job in jobs.filter({ $0.status == .queued }).prefix(slots) { start(job.id) }
    }

    private func start(_ jobID: UUID) {
        guard let i = index(jobID) else { return }
        if jobs[i].supportsRanges == true, segments[jobID] != nil { startSegmented(jobID); return }
        if jobs[i].supportsRanges == false, jobs[i].totalBytes != nil { startSingle(jobID); return }
        jobs[i].status = .probing
        saveState()
        Task { await probe(jobID) }
    }

    private func probe(_ jobID: UUID) async {
        guard let i = index(jobID) else { return }
        var req = URLRequest(url: jobs[i].url)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 30
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            let length = Self.contentLength(http)
            let ranges = (http.value(forHTTPHeaderField: "Accept-Ranges") ?? "").lowercased().contains("bytes")
            if let name = response.suggestedFilename, !name.isEmpty, let j = index(jobID), jobs[j].title == jobs[j].url.lastPathComponent { jobs[j].title = name }
            configureAfterProbe(jobID, length: length, supportsRanges: ranges)
        } catch {
            configureAfterProbe(jobID, length: nil, supportsRanges: false)
        }
    }

    private func configureAfterProbe(_ jobID: UUID, length: Int64?, supportsRanges: Bool) {
        guard let i = index(jobID), jobs[i].status == .probing else { return }
        jobs[i].totalBytes = length
        let useSegments = supportsRanges && (length ?? 0) >= 2_000_000 && connectionsPerDownload > 1
        jobs[i].supportsRanges = useSegments
        if useSegments, let length {
            prepareSegments(jobID, total: length, count: connectionsPerDownload)
            startSegmented(jobID)
        } else {
            jobs[i].connections = 1
            startSingle(jobID)
        }
    }

    private func prepareSegments(_ jobID: UUID, total: Int64, count: Int) {
        let actualCount = min(count, max(1, Int(total / 512_000)))
        let chunk = total / Int64(actualCount)
        var list: [SegmentState] = []
        for idx in 0..<actualCount {
            let start = Int64(idx) * chunk
            let end = idx == actualCount - 1 ? total - 1 : start + chunk - 1
            list.append(SegmentState(index: idx, start: start, end: end, received: 0, fileName: "part-\(idx)", completed: false))
        }
        segments[jobID] = list
        if let i = index(jobID) { jobs[i].connections = actualCount }
        saveState()
    }

    private func startSegmented(_ jobID: UUID) {
        guard let i = index(jobID), var list = segments[jobID] else { return }
        try? FileManager.default.createDirectory(at: partsDirectory(jobID), withIntermediateDirectories: true)
        jobs[i].status = .downloading
        jobs[i].error = nil
        fallingBackToSingle.remove(jobID)
        lastSamples[jobID] = (Date(), jobs[i].downloadedBytes)

        for idx in list.indices where !list[idx].completed {
            let fileURL = partsDirectory(jobID).appendingPathComponent(list[idx].fileName)
            let existing = ((try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size]) as? NSNumber)?.int64Value ?? 0
            list[idx].received = min(existing, list[idx].expected)
            if list[idx].received >= list[idx].expected { list[idx].completed = true; continue }
            if !FileManager.default.fileExists(atPath: fileURL.path) { FileManager.default.createFile(atPath: fileURL.path, contents: nil) }
            var req = URLRequest(url: jobs[i].url)
            req.setValue("bytes=\(list[idx].start + list[idx].received)-\(list[idx].end)", forHTTPHeaderField: "Range")
            req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            let task = session.dataTask(with: req)
            taskRefs[task.taskIdentifier] = .segment(jobID: jobID, segmentIndex: idx)
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                try? handle.seekToEnd()
                segmentHandles[task.taskIdentifier] = handle
            }
            task.resume()
        }
        segments[jobID] = list
        recalcProgress(jobID)
        saveState()
    }

    private func startSingle(_ jobID: UUID) {
        guard let i = index(jobID) else { return }
        jobs[i].status = .downloading
        jobs[i].connections = 1
        jobs[i].error = nil
        lastSamples[jobID] = (Date(), jobs[i].downloadedBytes)
        let resume = singleResumeData[jobID] ?? (try? Data(contentsOf: resumeDataURL(jobID)))
        let task = (resume?.isEmpty == false) ? session.downloadTask(withResumeData: resume!) : session.downloadTask(with: jobs[i].url)
        taskRefs[task.taskIdentifier] = .single(jobID: jobID)
        task.resume()
        saveState()
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        Task { @MainActor in
            guard let ref = self.taskRefs[dataTask.taskIdentifier] else { completionHandler(.cancel); return }
            guard case .segment(let jobID, _) = ref else { completionHandler(.allow); return }
            if let http = response as? HTTPURLResponse, http.statusCode != 206 {
                completionHandler(.cancel)
                self.fallbackToSingle(jobID)
            } else { completionHandler(.allow) }
        }
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task { @MainActor in
            guard case .segment(let jobID, let segmentIndex)? = self.taskRefs[dataTask.taskIdentifier],
                  var list = self.segments[jobID], list.indices.contains(segmentIndex),
                  let handle = self.segmentHandles[dataTask.taskIdentifier] else { return }
            do { try handle.write(contentsOf: data) } catch { self.fail(jobID, error.localizedDescription); return }
            list[segmentIndex].received = min(list[segmentIndex].received + Int64(data.count), list[segmentIndex].expected)
            self.segments[jobID] = list
            self.recalcProgress(jobID)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        Task { @MainActor in
            guard case .single(let jobID)? = self.taskRefs[downloadTask.taskIdentifier], let i = self.index(jobID) else { return }
            let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : (self.jobs[i].totalBytes ?? 0)
            self.jobs[i].downloadedBytes = totalBytesWritten
            if expected > 0 { self.jobs[i].totalBytes = expected; self.jobs[i].progress = min(1, Double(totalBytesWritten) / Double(expected)) }
            self.updateSpeed(jobID)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        Task { @MainActor in
            guard case .single(let jobID)? = self.taskRefs[downloadTask.taskIdentifier], let i = self.index(jobID) else { return }
            let dest = self.uniqueDestination(self.destinationName(jobID, suggested: downloadTask.response?.suggestedFilename))
            do {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: location, to: dest)
                self.jobs[i].localURL = dest
                self.jobs[i].downloadedBytes = ((try? FileManager.default.attributesOfItem(atPath: dest.path)[.size]) as? NSNumber)?.int64Value ?? self.jobs[i].downloadedBytes
                self.jobs[i].totalBytes = self.jobs[i].downloadedBytes
                self.jobs[i].progress = 1
                self.jobs[i].speedBytesPerSecond = 0
                self.jobs[i].status = .complete
                self.singleResumeData[jobID] = nil
                try? FileManager.default.removeItem(at: self.resumeDataURL(jobID))
                self.saveState(); self.pumpQueue()
            } catch { self.fail(jobID, error.localizedDescription) }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor in
            guard let ref = self.taskRefs.removeValue(forKey: task.taskIdentifier) else { return }
            if let handle = self.segmentHandles.removeValue(forKey: task.taskIdentifier) { try? handle.close() }
            switch ref {
            case .segment(let jobID, let segmentIndex):
                guard !self.fallingBackToSingle.contains(jobID), let i = self.index(jobID) else { return }
                if self.jobs[i].status == .paused || self.jobs[i].status == .cancelled { self.saveState(); return }
                if let error {
                    if (error as NSError).code != NSURLErrorCancelled { self.fail(jobID, error.localizedDescription) }
                    return
                }
                guard var list = self.segments[jobID], list.indices.contains(segmentIndex) else { return }
                list[segmentIndex].received = list[segmentIndex].expected
                list[segmentIndex].completed = true
                self.segments[jobID] = list
                self.recalcProgress(jobID)
                if list.allSatisfy({ $0.completed }) { self.merge(jobID) } else { self.saveState() }
            case .single(let jobID):
                guard let i = self.index(jobID) else { return }
                if self.jobs[i].status == .paused || self.jobs[i].status == .cancelled { self.saveState(); return }
                if let error, (error as NSError).code != NSURLErrorCancelled { self.fail(jobID, error.localizedDescription) }
            }
        }
    }

    private func fallbackToSingle(_ jobID: UUID) {
        guard !fallingBackToSingle.contains(jobID), let i = index(jobID) else { return }
        fallingBackToSingle.insert(jobID)
        jobs[i].supportsRanges = false
        jobs[i].connections = 1
        jobs[i].downloadedBytes = 0
        jobs[i].progress = 0
        session.getAllTasks { tasks in
            for task in tasks {
                guard let ref = self.taskRefs[task.taskIdentifier] else { continue }
                if case .segment(let id, _) = ref, id == jobID { task.cancel() }
            }
            Task { @MainActor in
                self.closeHandles(for: jobID)
                self.cleanupParts(jobID)
                self.segments[jobID] = nil
                self.fallingBackToSingle.remove(jobID)
                if let j = self.index(jobID), self.jobs[j].status != .paused && self.jobs[j].status != .cancelled { self.startSingle(jobID) }
                self.saveState()
            }
        }
    }

    private func merge(_ jobID: UUID) {
        guard let i = index(jobID), let list = segments[jobID] else { return }
        jobs[i].status = .merging
        jobs[i].progress = 1
        jobs[i].speedBytesPerSecond = 0
        let output = uniqueDestination(destinationName(jobID, suggested: nil))
        let ordered = list.sorted { $0.index < $1.index }.map { partsDirectory(jobID).appendingPathComponent($0.fileName) }
        Task.detached(priority: .utility) {
            do {
                FileManager.default.createFile(atPath: output.path, contents: nil)
                let out = try FileHandle(forWritingTo: output)
                defer { try? out.close() }
                for part in ordered {
                    let input = try FileHandle(forReadingFrom: part)
                    while true {
                        let data = try input.read(upToCount: 1024 * 1024) ?? Data()
                        if data.isEmpty { break }
                        try out.write(contentsOf: data)
                    }
                    try? input.close()
                }
                await MainActor.run {
                    guard let j = self.index(jobID) else { return }
                    self.jobs[j].localURL = output
                    self.jobs[j].status = .complete
                    self.jobs[j].progress = 1
                    self.jobs[j].downloadedBytes = self.jobs[j].totalBytes ?? self.jobs[j].downloadedBytes
                    self.cleanupParts(jobID)
                    self.saveState(); self.pumpQueue()
                }
            } catch { await MainActor.run { self.fail(jobID, error.localizedDescription) } }
        }
    }

    private func recalcProgress(_ jobID: UUID) {
        guard let i = index(jobID), let list = segments[jobID] else { return }
        let bytes = list.reduce(Int64(0)) { $0 + min($1.received, $1.expected) }
        jobs[i].downloadedBytes = bytes
        if let total = jobs[i].totalBytes, total > 0 { jobs[i].progress = min(1, Double(bytes) / Double(total)) }
        updateSpeed(jobID)
    }

    private func updateSpeed(_ jobID: UUID) {
        guard let i = index(jobID) else { return }
        let now = Date(), bytes = jobs[i].downloadedBytes
        if let sample = lastSamples[jobID] {
            let dt = now.timeIntervalSince(sample.date)
            if dt >= 0.6 {
                jobs[i].speedBytesPerSecond = max(0, Double(bytes - sample.bytes) / dt)
                lastSamples[jobID] = (now, bytes)
                saveState()
            }
        } else { lastSamples[jobID] = (now, bytes) }
    }

    private func fail(_ jobID: UUID, _ message: String) {
        guard let i = index(jobID) else { return }
        jobs[i].status = .failed
        jobs[i].speedBytesPerSecond = 0
        jobs[i].error = message
        closeHandles(for: jobID)
        saveState(); pumpQueue()
    }

    private func destinationName(_ jobID: UUID, suggested: String?) -> String {
        guard let i = index(jobID) else { return "download-\(jobID.uuidString)" }
        if let suggested, !suggested.isEmpty { return Self.safeFileName(suggested) }
        let fromURL = jobs[i].url.lastPathComponent
        if !fromURL.isEmpty { return Self.safeFileName(fromURL) }
        return Self.safeFileName(jobs[i].title.isEmpty ? "download-\(jobID.uuidString).mp4" : jobs[i].title)
    }

    private func uniqueDestination(_ fileName: String) -> URL {
        let src = URL(fileURLWithPath: fileName), base = src.deletingPathExtension().lastPathComponent, ext = src.pathExtension
        var dest = LibraryPaths.mediaDirectory.appendingPathComponent(fileName), n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = LibraryPaths.mediaDirectory.appendingPathComponent("\(base)-\(n)\(ext.isEmpty ? "" : ".\(ext)")")
            n += 1
        }
        return dest
    }

    private func partsDirectory(_ id: UUID) -> URL { partsRoot.appendingPathComponent(id.uuidString, isDirectory: true) }
    private func resumeDataURL(_ id: UUID) -> URL { partsDirectory(id).appendingPathComponent("resume.data") }
    private func writeResumeData(_ data: Data, for id: UUID) {
        try? FileManager.default.createDirectory(at: partsDirectory(id), withIntermediateDirectories: true)
        try? data.write(to: resumeDataURL(id), options: .atomic)
    }
    private func cleanupParts(_ id: UUID) { try? FileManager.default.removeItem(at: partsDirectory(id)) }
    private func index(_ id: UUID) -> Int? { jobs.firstIndex { $0.id == id } }

    private func closeHandles(for jobID: UUID) {
        let ids = taskRefs.compactMap { key, ref -> Int? in
            if case .segment(let id, _) = ref, id == jobID { return key }
            return nil
        }
        for taskID in ids { if let h = segmentHandles.removeValue(forKey: taskID) { try? h.close() } }
    }

    private func saveState() {
        let encodedSegments = Dictionary(uniqueKeysWithValues: segments.map { ($0.key.uuidString, $0.value) })
        if let data = try? JSONEncoder().encode(StoredDownloadState(jobs: jobs, segments: encodedSegments)) { try? data.write(to: stateURL, options: .atomic) }
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: stateURL), let state = try? JSONDecoder().decode(StoredDownloadState.self, from: data) else { return }
        jobs = state.jobs.map { old in
            var j = old
            if [.downloading, .probing, .merging].contains(j.status) { j.status = .paused; j.speedBytesPerSecond = 0 }
            return j
        }
        for (key, value) in state.segments { if let id = UUID(uuidString: key) { segments[id] = value } }
        for job in jobs { if let data = try? Data(contentsOf: resumeDataURL(job.id)) { singleResumeData[job.id] = data } }
    }

    private static func contentLength(_ response: HTTPURLResponse) -> Int64? {
        if response.expectedContentLength > 0 { return response.expectedContentLength }
        if let raw = response.value(forHTTPHeaderField: "Content-Length"), let n = Int64(raw), n > 0 { return n }
        return nil
    }

    private static func safeFileName(_ value: String) -> String {
        value.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|")).joined(separator: "_")
    }
}

private extension Int {
    func nonZero(or fallback: Int) -> Int { self == 0 ? fallback : self }
}
