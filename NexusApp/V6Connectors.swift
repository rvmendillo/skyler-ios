import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Security

// MARK: - Extra import connectors

enum NexusExtraConnector: String, CaseIterable, Identifiable {
    case chatgpt = "ChatGPT Export"
    case google = "Google Takeout"
    case spotify = "Spotify History"
    case discord = "Discord Data Package"
    case linkedin = "LinkedIn Data Export"
    case browser = "Browser History / Bookmarks"
    case finance = "Finance CSV / JSON"
    case notes = "Notes / Text Archive"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .chatgpt: return "bubble.left.and.text.bubble.right.fill"
        case .google: return "g.circle.fill"
        case .spotify: return "music.note.list"
        case .discord: return "person.3.fill"
        case .linkedin: return "briefcase.fill"
        case .browser: return "safari.fill"
        case .finance: return "chart.line.uptrend.xyaxis"
        case .notes: return "note.text"
        }
    }
    var detail: String {
        switch self {
        case .chatgpt: return "Conversations and metadata from your official export"
        case .google: return "Takeout JSON/CSV/text files such as Search, YouTube, Maps or activity exports"
        case .spotify: return "Extended streaming history JSON and library exports"
        case .discord: return "Messages and account-data files from Discord's export"
        case .linkedin: return "Connections, messages and activity CSV files"
        case .browser: return "History/bookmark exports in JSON, CSV, HTML or text"
        case .finance: return "Bank/broker/wallet CSV or JSON exports; analyzed locally"
        case .notes: return "Plain-text, HTML, JSON and other text archives"
        }
    }
}

private struct NexusV6DocumentPicker: UIViewControllerRepresentable {
    let onPicked: ([URL]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.zip, .json, .plainText, .commaSeparatedText, .html, .xml, .data]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: NexusV6DocumentPicker
        init(parent: NexusV6DocumentPicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { parent.onPicked(urls) }
    }
}

// MARK: - GitHub device OAuth (no client secret)

struct NexusGitHubDeviceCode: Decodable {
    let device_code: String
    let user_code: String
    let verification_uri: String
    let expires_in: Int
    let interval: Int?
}

private struct NexusGitHubTokenResponse: Decodable {
    let access_token: String?
    let error: String?
    let error_description: String?
}

@MainActor
final class NexusGitHubConnector: ObservableObject {
    @Published var status = "Not connected"
    @Published var userCode = ""
    @Published var verificationURL: URL?
    @Published var busy = false
    @Published var lastError = ""

    private let keychainAccount = "github-access-token"

    var isConnected: Bool { KeychainBox.read(account: keychainAccount) != nil }

    func begin(clientID: String, model: NexusModel) async {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { lastError = "A GitHub OAuth App client ID is required. A client secret is not used by this device flow."; return }
        busy = true; lastError = ""; status = "Requesting device code…"
        defer { busy = false }
        do {
            let code = try await requestDeviceCode(clientID: id)
            userCode = code.user_code
            verificationURL = URL(string: code.verification_uri)
            status = "Open GitHub and enter \(code.user_code)"
            if let verificationURL { await MainActor.run { UIApplication.shared.open(verificationURL) } }
            let token = try await pollForToken(clientID: id, code: code)
            try KeychainBox.write(token, account: keychainAccount)
            status = "Connected • importing profile"
            let records = try await importGitHub(token: token)
            model.merge(records, sourceName: "GitHub")
            model.setStatus(id: "github", status: "Connected • \(records.count) records")
            status = "Connected • \(records.count) records"
        } catch {
            lastError = error.localizedDescription
            status = "Connection failed"
        }
    }

    func sync(model: NexusModel) async {
        guard let token = KeychainBox.read(account: keychainAccount) else { lastError = "Connect GitHub first."; return }
        busy = true; defer { busy = false }
        do {
            let records = try await importGitHub(token: token)
            model.merge(records, sourceName: "GitHub")
            status = "Synced • \(records.count) records"
        } catch { lastError = error.localizedDescription }
    }

    func disconnect(model: NexusModel) {
        KeychainBox.delete(account: keychainAccount)
        status = "Not connected"
        userCode = ""
        verificationURL = nil
        model.setStatus(id: "github", status: "Not connected")
    }

    private func requestDeviceCode(clientID: String) async throws -> NexusGitHubDeviceCode {
        var request = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "client_id=\(urlEncode(clientID))&scope=read%3Auser%20repo"
        request.httpBody = body.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        try requireSuccess(response, data: data)
        return try JSONDecoder().decode(NexusGitHubDeviceCode.self, from: data)
    }

    private func pollForToken(clientID: String, code: NexusGitHubDeviceCode) async throws -> String {
        let start = Date()
        var interval = max(5, code.interval ?? 5)
        while Date().timeIntervalSince(start) < Double(code.expires_in) {
            try await Task.sleep(for: .seconds(interval))
            var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = "client_id=\(urlEncode(clientID))&device_code=\(urlEncode(code.device_code))&grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code".data(using: .utf8)
            let (data, _) = try await URLSession.shared.data(for: request)
            let result = try JSONDecoder().decode(NexusGitHubTokenResponse.self, from: data)
            if let token = result.access_token { return token }
            switch result.error {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            case "expired_token": throw ConnectorError.message("GitHub device code expired. Start again.")
            case "access_denied": throw ConnectorError.message("GitHub authorization was denied.")
            default:
                if let error = result.error { throw ConnectorError.message(result.error_description ?? error) }
            }
        }
        throw ConnectorError.message("GitHub authorization timed out.")
    }

    private func importGitHub(token: String) async throws -> [KnowledgeRecord] {
        async let userData = githubGET("https://api.github.com/user", token: token)
        async let reposData = githubGET("https://api.github.com/user/repos?per_page=100&sort=updated&affiliation=owner,collaborator,organization_member", token: token)
        async let starredData = githubGET("https://api.github.com/user/starred?per_page=100", token: token)
        let (user, repos, starred) = try await (userData, reposData, starredData)
        var out: [KnowledgeRecord] = []
        if let obj = try JSONSerialization.jsonObject(with: user) as? [String:Any] {
            let login = obj["login"] as? String ?? "GitHub profile"
            let name = obj["name"] as? String ?? login
            let bio = obj["bio"] as? String ?? ""
            out.append(record(id: "github:user:\(obj["id"] ?? login)", kind: .profile, date: parseDate(obj["updated_at"]), title: name, text: bio, metadata: ["login": login]))
        }
        if let array = try JSONSerialization.jsonObject(with: repos) as? [[String:Any]] {
            for repo in array {
                let name = repo["full_name"] as? String ?? repo["name"] as? String ?? "Repository"
                let desc = repo["description"] as? String ?? ""
                var meta: [String:String] = [:]
                if let language = repo["language"] as? String { meta["language"] = language }
                if let stars = repo["stargazers_count"] { meta["stars"] = String(describing: stars) }
                if let fork = repo["fork"] { meta["fork"] = String(describing: fork) }
                out.append(record(id: "github:repo:\(repo["id"] ?? name)", kind: .activity, date: parseDate(repo["updated_at"]), title: name, text: desc, metadata: meta))
            }
        }
        if let array = try JSONSerialization.jsonObject(with: starred) as? [[String:Any]] {
            for repo in array {
                let name = repo["full_name"] as? String ?? "Starred repository"
                let desc = repo["description"] as? String ?? ""
                out.append(record(id: "github:star:\(repo["id"] ?? name)", kind: .saved, date: parseDate(repo["updated_at"]), title: name, text: desc, metadata: ["activity":"starred repository"]))
            }
        }
        return out
    }

    private func githubGET(_ value: String, token: String) async throws -> Data {
        var request = URLRequest(url: URL(string: value)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await URLSession.shared.data(for: request)
        try requireSuccess(response, data: data)
        return data
    }

    private func record(id: String, kind: KnowledgeRecord.Kind, date: Date?, title: String, text: String, metadata: [String:String]) -> KnowledgeRecord {
        KnowledgeRecord(id: id, source: "GitHub", kind: kind, timestamp: date, title: title, text: text, metadata: metadata)
    }

    private func parseDate(_ any: Any?) -> Date? {
        guard let string = any as? String else { return nil }
        return ISO8601DateFormatter().date(from: string)
    }

    private func requireSuccess(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Network request failed"
            throw ConnectorError.message(String(message.prefix(250)))
        }
    }

    private func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}

private enum ConnectorError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return "Connector error" }
}

private enum KeychainBox {
    private static let service = "com.rey.nexus.oauth"
    static func write(_ value: String, account: String) throws {
        delete(account: account)
        let data = Data(value.utf8)
        let query: [String:Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw ConnectorError.message("Keychain error \(status)") }
    }
    static func read(account: String) -> String? {
        let query: [String:Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func delete(account: String) {
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:account]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - UI

struct ConnectHubV6View: View {
    @EnvironmentObject var model: NexusModel
    @StateObject private var github = NexusGitHubConnector()
    @AppStorage("nexus.github.clientID") private var githubClientID = ""
    @State private var selectedImport: NexusExtraConnector?
    @State private var importing = false
    @State private var importMessage = ""

    var body: some View {
        List {
            Section("Core connectors") {
                NavigationLink { ConnectionsV4View() } label: {
                    connectorLink("Device + Meta imports", "Contacts, Calendar, Reminders, Photos, Health, Music, Instagram, Messenger and Files", "square.stack.3d.up.fill")
                }
            }

            Section("More data packs") {
                ForEach(NexusExtraConnector.allCases) { connector in
                    HStack(spacing: 12) {
                        Image(systemName: connector.symbol).frame(width: 28).foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 3) { Text(connector.rawValue).font(.headline); Text(connector.detail).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button("Import") { selectedImport = connector }.buttonStyle(.bordered).disabled(importing)
                    }.padding(.vertical, 3)
                }
                if importing { ProgressView(importMessage.isEmpty ? "Importing…" : importMessage) }
            }

            Section("GitHub OAuth • device flow") {
                TextField("GitHub OAuth App client ID", text: $githubClientID)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Text("Device authorization does not embed a client secret. The access token is stored in this device's Keychain.").font(.caption).foregroundStyle(.secondary)
                if !github.userCode.isEmpty { LabeledContent("Code", value: github.userCode).textSelection(.enabled) }
                if !github.status.isEmpty { Text(github.status).font(.caption).foregroundStyle(.secondary) }
                if !github.lastError.isEmpty { Text(github.lastError).font(.caption).foregroundStyle(.red) }
                HStack {
                    Button(github.isConnected ? "Reconnect" : "Connect GitHub") { Task { await github.begin(clientID: githubClientID, model: model) } }.disabled(github.busy)
                    if github.isConnected {
                        Button("Sync") { Task { await github.sync(model: model) } }.disabled(github.busy)
                        Button("Disconnect", role: .destructive) { github.disconnect(model: model) }
                    }
                }
            }

            Section("OAuth-ready providers") {
                provider("Google", "OAuth client registration is required by Google before native sign-in can be activated. Takeout import works now.", "g.circle")
                provider("Microsoft", "Public-client OAuth can be added with an Entra application client ID; no client secret belongs in the app.", "square.grid.2x2")
                provider("Spotify", "PKCE OAuth can be activated with a Spotify app client ID; extended-history import works now.", "music.note")
            }
        }
        .navigationTitle("Connections")
        .sheet(item: $selectedImport) { connector in
            NexusV6DocumentPicker { urls in
                selectedImport = nil
                importExtra(urls, connector: connector)
            }
        }
    }

    private func importExtra(_ urls: [URL], connector: NexusExtraConnector) {
        importing = true; importMessage = "Reading \(connector.rawValue)…"
        Task {
            let result = await NexusImportCoordinator.importURLs(urls, target: connector.rawValue)
            let remapped = result.records.map { r in
                KnowledgeRecord(id: "\(connector.id):\(r.id)", source: connector.rawValue, kind: r.kind, timestamp: r.timestamp, title: r.title, text: r.text, metadata: r.metadata)
            }
            if remapped.isEmpty {
                model.reportImportError(result.errors.first ?? "No supported records found in \(connector.rawValue).")
            } else { model.merge(remapped, sourceName: connector.rawValue) }
            importMessage = result.errors.isEmpty ? "Imported \(remapped.count) records" : "Imported with \(result.errors.count) warning(s)"
            importing = false
        }
    }

    private func connectorLink(_ title: String, _ subtitle: String, _ symbol: String) -> some View {
        HStack(spacing: 12) { Image(systemName: symbol).foregroundStyle(.cyan).frame(width: 28); VStack(alignment: .leading, spacing: 3) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary) } }
    }

    private func provider(_ title: String, _ detail: String, _ symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) { Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 28); VStack(alignment: .leading, spacing: 3) { Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(.secondary) } }
    }
}
