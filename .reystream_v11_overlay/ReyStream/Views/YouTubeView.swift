import SwiftUI
import WebKit

struct YouTubeSearchResult: Identifiable, Hashable {
    let id: String
    let title: String
    let channelTitle: String
    let thumbnailURL: URL?
    let duration: String?
}

@MainActor
final class YouTubeSearchModel: ObservableObject {
    @Published var results: [YouTubeSearchResult] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var recentSearches: [String] = UserDefaults.standard.stringArray(forKey: "youtubeRecentSearches") ?? []

    private struct SearchResponse: Decodable {
        struct Item: Decodable {
            struct ID: Decodable { let videoId: String? }
            struct Snippet: Decodable {
                struct ThumbnailSet: Decodable {
                    struct Thumbnail: Decodable { let url: String }
                    let medium: Thumbnail?
                    let high: Thumbnail?
                    let `default`: Thumbnail?
                }
                let title: String
                let channelTitle: String
                let thumbnails: ThumbnailSet
            }
            let id: ID
            let snippet: Snippet
        }
        let items: [Item]
    }

    private struct VideosResponse: Decodable {
        struct Item: Decodable {
            struct ContentDetails: Decodable { let duration: String? }
            let id: String
            let contentDetails: ContentDetails
        }
        let items: [Item]
    }

    func search(_ rawQuery: String, apiKey: String) async {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Add a YouTube Data API key in Settings to use native search. Pasted YouTube URLs still work without a key."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            var c = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
            var items = [
                URLQueryItem(name: "part", value: "snippet"),
                URLQueryItem(name: "type", value: "video"),
                URLQueryItem(name: "maxResults", value: "25"),
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "videoEmbeddable", value: "true"),
                URLQueryItem(name: "videoSyndicated", value: "true"),
                URLQueryItem(name: "safeSearch", value: "moderate"),
                URLQueryItem(name: "key", value: apiKey)
            ]
            if let region = Locale.current.region?.identifier, region.count == 2 {
                items.append(URLQueryItem(name: "regionCode", value: region))
            }
            c.queryItems = items
            let (data, response) = try await URLSession.shared.data(from: c.url!)
            try Self.validate(response: response, data: data)
            let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
            let videoIDs = decoded.items.compactMap { $0.id.videoId }
            let durations = try await fetchDurations(videoIDs: videoIDs, apiKey: apiKey)
            results = decoded.items.compactMap { item in
                guard let videoID = item.id.videoId else { return nil }
                let thumb = item.snippet.thumbnails.high ?? item.snippet.thumbnails.medium ?? item.snippet.thumbnails.default
                return YouTubeSearchResult(
                    id: videoID,
                    title: Self.decodeHTMLEntities(item.snippet.title),
                    channelTitle: Self.decodeHTMLEntities(item.snippet.channelTitle),
                    thumbnailURL: thumb.flatMap { URL(string: $0.url) },
                    duration: durations[videoID]
                )
            }
            remember(query)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchDurations(videoIDs: [String], apiKey: String) async throws -> [String: String] {
        guard !videoIDs.isEmpty else { return [:] }
        var c = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
        c.queryItems = [
            URLQueryItem(name: "part", value: "contentDetails"),
            URLQueryItem(name: "id", value: videoIDs.joined(separator: ",")),
            URLQueryItem(name: "key", value: apiKey)
        ]
        let (data, response) = try await URLSession.shared.data(from: c.url!)
        try Self.validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(VideosResponse.self, from: data)
        return Dictionary(uniqueKeysWithValues: decoded.items.map { ($0.id, Self.displayDuration($0.contentDetails.duration)) })
    }

    private func remember(_ query: String) {
        recentSearches.removeAll { $0.caseInsensitiveCompare(query) == .orderedSame }
        recentSearches.insert(query, at: 0)
        recentSearches = Array(recentSearches.prefix(8))
        UserDefaults.standard.set(recentSearches, forKey: "youtubeRecentSearches")
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }
                .flatMap { $0["message"] as? String }
            throw NSError(domain: "YouTube", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: detail ?? "YouTube search request failed (HTTP \(http.statusCode))."])
        }
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        guard let data = text.data(using: .utf8) else { return text }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        return (try? NSAttributedString(data: data, options: options, documentAttributes: nil).string) ?? text
    }

    private static func displayDuration(_ iso: String?) -> String {
        guard let iso else { return "" }
        var hours = 0, minutes = 0, seconds = 0
        var number = ""
        for ch in iso.dropFirst() {
            if ch.isNumber { number.append(ch); continue }
            let value = Int(number) ?? 0
            number = ""
            switch ch {
            case "H": hours = value
            case "M": minutes = value
            case "S": seconds = value
            default: break
            }
        }
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct YouTubeView: View {
    @EnvironmentObject var library: LibraryStore
    @AppStorage("youtubeAPIKey") private var apiKey = ""
    @StateObject private var searchModel = YouTubeSearchModel()
    @State private var query = ""
    @State private var input: String
    @State private var activeID: String?
    @State private var activeTitle = "YouTube video"
    @State private var message: String?
    @State private var selectedMode = 0

    init(initialURL: String = "") {
        _input = State(initialValue: initialURL)
        _activeID = State(initialValue: YouTubeURL.videoID(from: initialURL))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $selectedMode) {
                Text("Search").tag(0)
                Text("URL").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            if let id = activeID {
                playerCard(id: id)
            }

            if selectedMode == 0 { searchPane } else { urlPane }
        }
        .navigationTitle("YouTube")
        .alert("ReyStream", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
        .onChange(of: searchModel.errorMessage) { _, value in if let value { message = value } }
    }

    @ViewBuilder
    private func playerCard(id: String) -> some View {
        VStack(spacing: 10) {
            YouTubeEmbed(videoID: id)
                .aspectRatio(16/9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            HStack {
                Button {
                    library.addYouTubeBookmark(title: activeTitle, url: canonicalURL(id).absoluteString)
                    message = "Bookmarked in Library."
                } label: { Label("Bookmark", systemImage: "bookmark") }
                Spacer()
                Link(destination: canonicalURL(id)) { Label("Open in YouTube", systemImage: "arrow.up.right.square") }
                ShareLink(item: canonicalURL(id)) { Image(systemName: "square.and.arrow.up") }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var searchPane: some View {
        List {
            Section {
                HStack {
                    TextField("Search YouTube", text: $query)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .onSubmit { performSearch() }
                    if searchModel.isLoading { ProgressView() }
                    else { Button { performSearch() } label: { Image(systemName: "magnifyingglass") } }
                }
                if apiKey.isEmpty {
                    Label("Native search needs a YouTube Data API key. Add it in Settings.", systemImage: "key")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            if !searchModel.recentSearches.isEmpty && searchModel.results.isEmpty {
                Section("Recent searches") {
                    ForEach(searchModel.recentSearches, id: \.self) { item in
                        Button(item) { query = item; performSearch() }
                    }
                }
            }

            if !searchModel.results.isEmpty {
                Section("Results") {
                    ForEach(searchModel.results) { result in
                        Button { play(result) } label: {
                            HStack(spacing: 12) {
                                AsyncImage(url: result.thumbnailURL) { phase in
                                    switch phase {
                                    case .success(let image): image.resizable().scaledToFill()
                                    default: Rectangle().fill(.secondary.opacity(0.18)).overlay(Image(systemName: "play.rectangle"))
                                    }
                                }
                                .frame(width: 128, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(result.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                                    HStack(spacing: 6) {
                                        Text(result.channelTitle).lineLimit(1)
                                        if let duration = result.duration, !duration.isEmpty {
                                            Text("•"); Text(duration)
                                        }
                                    }
                                    .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                Text("ReyStream contains no ad SDKs. YouTube playback uses YouTube's permitted player and does not remove YouTube-served ads or bypass access controls.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
    }

    private var urlPane: some View {
        Form {
            Section("Play a YouTube link") {
                TextField("YouTube URL or video ID", text: $input)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                Button("Play") {
                    guard let id = YouTubeURL.videoID(from: input) else { message = "Enter a valid YouTube video URL or ID."; return }
                    activeID = id
                    activeTitle = "YouTube video"
                }
            }
            Section {
                Text("If a creator disables embedding, use Open in YouTube. Search results are filtered for embeddable/syndicated videos when native search is configured.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func performSearch() {
        Task { await searchModel.search(query, apiKey: apiKey) }
    }

    private func play(_ result: YouTubeSearchResult) {
        activeID = result.id
        activeTitle = result.title
        input = canonicalURL(result.id).absoluteString
    }

    private func canonicalURL(_ id: String) -> URL { URL(string: "https://www.youtube.com/watch?v=\(id)")! }
}

struct YouTubeEmbed: UIViewRepresentable {
    let videoID: String

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedID: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.scrollView.isScrollEnabled = false
        web.isOpaque = false
        web.backgroundColor = .black
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        guard context.coordinator.loadedID != videoID else { return }
        context.coordinator.loadedID = videoID
        var components = URLComponents(string: "https://www.youtube.com/embed/\(videoID)")!
        components.queryItems = [
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "enablejsapi", value: "1"),
            URLQueryItem(name: "origin", value: "https://www.youtube.com")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        web.load(request)
    }
}
