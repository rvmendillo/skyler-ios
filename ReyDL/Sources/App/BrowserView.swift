import SwiftUI
import WebKit

private enum REYDLDownloadURLDetector {
    static let fileExtensions: Set<String> = [
        "7z", "zip", "rar", "tar", "gz", "tgz", "bz2", "xz",
        "bin", "dmg", "pkg", "ipa", "apk", "exe", "msi",
        "pdf", "epub", "mobi", "txt", "rtf",
        "mp3", "m4a", "aac", "wav", "flac", "ogg",
        "mp4", "m4v", "mkv", "mov", "avi", "webm",
        "iso", "img", "csv", "tsv", "json", "xml",
        "doc", "docx", "xls", "xlsx", "ppt", "pptx",
        "pages", "numbers", "key"
    ]

    static func isLikelyDownload(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        if fileExtensions.contains(url.pathExtension.lowercased()) { return true }

        let path = url.path.lowercased()
        let hints = ["/download", "/downloads", "/attachment", "/attachments", "/export", "/file/", "/files/", "/archive", "/asset"]
        if hints.contains(where: path.contains) { return true }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        let queryNames = Set((components.queryItems ?? []).map { $0.name.lowercased() })
        return !queryNames.isDisjoint(with: ["download", "dl", "attachment", "export", "filename", "file"])
    }
}

struct BrowserScreen: View {
    @EnvironmentObject private var downloads: DownloadManager
    @State private var address = "https://www.google.com"
    @State private var requestedURL = URL(string: "https://www.google.com")!
    @State private var currentURL = URL(string: "https://www.google.com")!
    @State private var title = "Browser"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(.indigo.opacity(0.14))
                    Image(systemName: currentURL.scheme?.lowercased() == "https" ? "lock.fill" : "globe")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.indigo)
                }
                .frame(width: 28, height: 28)

                TextField("Address or direct file URL", text: $address)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { navigate() }

                Button(action: navigate) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3)
                }
            }
            .padding(10)
            .background(.thinMaterial)

            BrowserWebView(url: requestedURL, currentURL: $currentURL, pageTitle: $title, downloads: downloads)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    downloads.add(url: currentURL)
                } label: {
                    Label("Send to REYDL", systemImage: "bolt.fill")
                }
                Spacer()
                ShareLink(item: currentURL) { Image(systemName: "square.and.arrow.up") }
            }
        }
        .onChange(of: currentURL) { _, newValue in
            address = newValue.absoluteString
        }
    }

    private func navigate() {
        var raw = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.contains("://") { raw = "https://" + raw }
        guard var components = URLComponents(string: raw) else { return }
        if components.scheme?.lowercased() == "http" {
            components.scheme = "https"
        }
        guard let url = components.url else { return }

        // ADM/IDM-style direct URL behavior: obvious file URLs go straight to the
        // download engine instead of first asking WebKit to display binary data.
        if REYDLDownloadURLDetector.isLikelyDownload(url) {
            currentURL = url
            title = "Sent to Downloads"
            downloads.add(url: url)
            return
        }

        requestedURL = url
    }
}

struct BrowserWebView: UIViewRepresentable {
    let url: URL
    @Binding var currentURL: URL
    @Binding var pageTitle: String
    let downloads: DownloadManager

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "reydlDownload")
        controller.addUserScript(WKUserScript(source: Self.captureScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let view = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.webView = view
        context.coordinator.lastRequestedURL = url.absoluteString
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.isOpaque = true
        view.scrollView.isScrollEnabled = true
        view.scrollView.delaysContentTouches = false
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let requested = url.absoluteString
        guard context.coordinator.lastRequestedURL != requested else { return }
        context.coordinator.lastRequestedURL = requested
        webView.load(URLRequest(url: url))
    }

    static let captureScript = #"""
    (() => {
      const fileLike = /\.(7z|zip|rar|tar|gz|tgz|bz2|xz|bin|dmg|pkg|ipa|apk|exe|msi|pdf|epub|mobi|mp3|m4a|aac|wav|flac|ogg|mp4|m4v|mkv|mov|avi|webm|iso|img|csv|tsv|json|xml|txt|rtf|docx?|xlsx?|pptx?|pages|numbers|key)(?:$|[?#])/i;
      const downloadHint = /(?:^|[\/?&=_-])(download|downloads|attachment|attachments|export|file|files|archive|asset|dl)(?:$|[\/?&=_-])/i;
      const downloadQuery = /[?&](?:download|dl|attachment|export|filename|file)=/i;

      function shouldCapture(href, anchor) {
        if (!/^https?:/i.test(href || '')) return false;
        if (anchor && anchor.hasAttribute('download')) return true;
        if (fileLike.test(href) || downloadQuery.test(href)) return true;
        try { return downloadHint.test(new URL(href).pathname); } catch (_) { return false; }
      }

      document.addEventListener('click', (event) => {
        const a = event.target && event.target.closest ? event.target.closest('a[href], area[href]') : null;
        if (!a) return;
        const href = a.href;
        if (!shouldCapture(href, a)) return;
        event.preventDefault();
        event.stopImmediatePropagation();
        window.webkit.messageHandlers.reydlDownload.postMessage({url: href, name: a.getAttribute('download') || ''});
      }, true);

      const nativeAnchorClick = HTMLAnchorElement.prototype.click;
      HTMLAnchorElement.prototype.click = function(...args) {
        const href = this.href;
        if (shouldCapture(href, this)) {
          window.webkit.messageHandlers.reydlDownload.postMessage({url: href, name: this.getAttribute('download') || ''});
          return;
        }
        return nativeAnchorClick.apply(this, args);
      };
    })();
    """#

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let parent: BrowserWebView
        weak var webView: WKWebView?
        var lastRequestedURL: String?

        init(_ parent: BrowserWebView) { self.parent = parent }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "reydlDownload",
                  let body = message.body as? [String: Any],
                  let raw = body["url"] as? String,
                  let url = URL(string: raw) else { return }
            let name = body["name"] as? String
            parent.downloads.add(url: url, suggestedName: name?.isEmpty == false ? name : nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                if let url = webView.url { self.parent.currentURL = url }
                self.parent.pageTitle = webView.title?.isEmpty == false ? webView.title! : "Browser"
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                if let url = webView.url { self.parent.currentURL = url }
            }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                if REYDLDownloadURLDetector.isLikelyDownload(url) {
                    parent.downloads.add(url: url)
                } else {
                    webView.load(URLRequest(url: url))
                }
            }
            return nil
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url,
               (navigationAction.shouldPerformDownload || REYDLDownloadURLDetector.isLikelyDownload(url)) {
                parent.downloads.add(url: url)
                decisionHandler(.cancel)
                return
            }

            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            let response = navigationResponse.response
            let mime = response.mimeType?.lowercased() ?? ""

            if let http = response as? HTTPURLResponse,
               let disposition = http.value(forHTTPHeaderField: "Content-Disposition")?.lowercased(),
               disposition.contains("attachment"),
               let url = http.url {
                parent.downloads.add(url: url, suggestedName: response.suggestedFilename)
                decisionHandler(.cancel)
                return
            }

            if (mime == "application/octet-stream" || mime == "application/x-binary" || !navigationResponse.canShowMIMEType),
               let url = response.url {
                parent.downloads.add(url: url, suggestedName: response.suggestedFilename)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }
}
