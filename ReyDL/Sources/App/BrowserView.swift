import SwiftUI
import WebKit

struct BrowserScreen: View {
    @EnvironmentObject private var downloads: DownloadManager
    @State private var address = "https://www.google.com"
    @State private var requestedURL = URL(string: "https://www.google.com")!
    @State private var currentURL = URL(string: "https://www.google.com")!
    @State private var title = "Browser"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                TextField("Address", text: $address)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { navigate() }
                Button(action: navigate) { Image(systemName: "arrow.right.circle.fill") }
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
                    Label("Download URL", systemImage: "arrow.down.circle")
                }
                Spacer()
                ShareLink(item: currentURL) { Image(systemName: "square.and.arrow.up") }
            }
        }
        .onChange(of: currentURL) { _, newValue in address = newValue.absoluteString }
    }

    private func navigate() {
        var raw = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.contains("://") { raw = "https://" + raw }
        if let url = URL(string: raw) { requestedURL = url }
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

        let view = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.webView = view
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url?.absoluteString != url.absoluteString else { return }
        webView.load(URLRequest(url: url))
    }

    static let captureScript = #"""
    (() => {
      const rx = /\.(7z|zip|rar|tar|gz|bz2|xz|dmg|pkg|ipa|apk|exe|msi|pdf|epub|mp3|m4a|wav|flac|mp4|m4v|mkv|mov|avi|webm|iso|img|csv|json|xml|docx?|xlsx?|pptx?)(?:$|[?#])/i;
      document.addEventListener('click', (event) => {
        const a = event.target && event.target.closest ? event.target.closest('a[href]') : null;
        if (!a) return;
        const href = a.href;
        if (!/^https?:/i.test(href)) return;
        if (a.hasAttribute('download') || rx.test(href)) {
          event.preventDefault();
          event.stopPropagation();
          window.webkit.messageHandlers.reydlDownload.postMessage({url: href, name: a.getAttribute('download') || ''});
        }
      }, true);
    })();
    """#

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let parent: BrowserWebView
        weak var webView: WKWebView?

        init(_ parent: BrowserWebView) { self.parent = parent }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "reydlDownload", let body = message.body as? [String: Any], let raw = body["url"] as? String, let url = URL(string: raw) else { return }
            let name = body["name"] as? String
            parent.downloads.add(url: url, suggestedName: name?.isEmpty == false ? name : nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                if let url = webView.url { self.parent.currentURL = url }
                self.parent.pageTitle = webView.title?.isEmpty == false ? webView.title! : "Browser"
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.shouldPerformDownload, let url = navigationAction.request.url {
                parent.downloads.add(url: url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let http = navigationResponse.response as? HTTPURLResponse,
               let disposition = http.value(forHTTPHeaderField: "Content-Disposition")?.lowercased(),
               disposition.contains("attachment"),
               let url = http.url {
                parent.downloads.add(url: url, suggestedName: navigationResponse.response.suggestedFilename)
                decisionHandler(.cancel)
                return
            }
            if !navigationResponse.canShowMIMEType, let url = navigationResponse.response.url {
                parent.downloads.add(url: url, suggestedName: navigationResponse.response.suggestedFilename)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
