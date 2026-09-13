import SwiftUI
import WebKit

@MainActor
final class YouTubeBrowserModel: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var title = "YouTube"
    @Published var currentURL: URL?

    let webView: WKWebView

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.keyboardDismissMode = .onDrag
    }

    func loadHome() {
        load(URL(string: "https://www.youtube.com/")!)
    }

    func search(_ rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        var c = URLComponents(string: "https://www.youtube.com/results")!
        c.queryItems = [URLQueryItem(name: "search_query", value: query)]
        if let url = c.url { load(url) }
    }

    func playURL(_ raw: String) -> Bool {
        guard let id = YouTubeURL.videoID(from: raw),
              let url = URL(string: "https://www.youtube.com/watch?v=\(id)") else { return false }
        load(url)
        return true
    }

    func goBack() { if webView.canGoBack { webView.goBack() } }
    func goForward() { if webView.canGoForward { webView.goForward() } }
    func reload() { webView.reload() }

    private func load(_ url: URL) {
        var request = URLRequest(url: url)
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        webView.load(request)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { update(webView, loading: true) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { update(webView, loading: false) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { update(webView, loading: false) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { update(webView, loading: false) }

    private func update(_ webView: WKWebView, loading: Bool) {
        isLoading = loading
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        currentURL = webView.url
        title = webView.title ?? "YouTube"
    }
}

struct YouTubeBrowserWebView: UIViewRepresentable {
    @ObservedObject var model: YouTubeBrowserModel
    func makeUIView(context: Context) -> WKWebView { model.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct YouTubeView: View {
    @EnvironmentObject var library: LibraryStore
    @StateObject private var browser = YouTubeBrowserModel()
    @State private var query = ""
    @State private var urlInput: String
    @State private var message: String?

    init(initialURL: String = "") {
        _urlInput = State(initialValue: initialURL)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search YouTube", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { browser.search(query) }
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) } }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                Button("Search") { browser.search(query) }
            }
            .padding(.horizontal).padding(.vertical, 8)

            HStack(spacing: 18) {
                Button { browser.goBack() } label: { Image(systemName: "chevron.backward") }.disabled(!browser.canGoBack)
                Button { browser.goForward() } label: { Image(systemName: "chevron.forward") }.disabled(!browser.canGoForward)
                Button { browser.reload() } label: { Image(systemName: "arrow.clockwise") }
                Button { browser.loadHome() } label: { Image(systemName: "house") }
                if browser.isLoading { ProgressView().controlSize(.small) }
                Spacer()
                if let u = browser.currentURL {
                    Button {
                        library.addYouTubeBookmark(title: browser.title, url: u.absoluteString)
                        message = "Bookmarked in Library."
                    } label: { Image(systemName: "bookmark") }
                    ShareLink(item: u) { Image(systemName: "square.and.arrow.up") }
                    Link(destination: u) { Image(systemName: "arrow.up.right.square") }
                }
            }
            .padding(.horizontal).padding(.bottom, 8)

            YouTubeBrowserWebView(model: browser)
                .background(Color.black)

            HStack {
                TextField("Paste YouTube URL or video ID", text: $urlInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("Open") {
                    if !browser.playURL(urlInput) { message = "Enter a valid YouTube URL or video ID." }
                }
            }
            .padding()
            .background(.thinMaterial)
        }
        .navigationTitle("YouTube")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !urlInput.isEmpty, browser.playURL(urlInput) { return }
            browser.loadHome()
        }
        .alert("ReyStream", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
        .safeAreaInset(edge: .bottom) {
            Text("Built-in search uses YouTube's official website. ReyStream itself contains no ad SDKs; it does not remove YouTube-served ads or bypass YouTube restrictions.")
                .font(.caption2).foregroundStyle(.secondary)
                .padding(.horizontal).padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
        }
    }
}
