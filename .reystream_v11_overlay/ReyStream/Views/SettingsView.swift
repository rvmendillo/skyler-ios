import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var library: LibraryStore
    @AppStorage("autoResume") private var autoResume = true
    @AppStorage("youtubeAPIKey") private var youtubeAPIKey = ""
    @AppStorage("downloadConnections") private var downloadConnections = 4
    @AppStorage("simultaneousDownloads") private var simultaneousDownloads = 3
    @State private var playlistName = ""

    var body: some View {
        Form {
            Section("Playback") {
                Toggle("Resume playback position", isOn: $autoResume)
                Label("Picture in Picture", systemImage: "pip")
                Label("AirPlay / external playback", systemImage: "airplayvideo")
                Label("Background audio", systemImage: "headphones")
            }
            Section("Download Manager") {
                Stepper("Connections per file: \(downloadConnections)", value: $downloadConnections, in: 1...8)
                Stepper("Simultaneous files: \(simultaneousDownloads)", value: $simultaneousDownloads, in: 1...5)
                Text("When a server supports HTTP byte ranges, ReyStream splits authorized downloads into concurrent segments. Pause/resume state is persisted. Servers without range support use a single resumable connection.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("YouTube Search") {
                SecureField("YouTube Data API key", text: $youtubeAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !youtubeAPIKey.isEmpty {
                    Button("Clear API key", role: .destructive) { youtubeAPIKey = "" }
                }
                Text("The key is stored in this app's local preferences and is used only for YouTube Data API search requests. YouTube URL playback does not require it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Library") {
                HStack { Text("Storage used"); Spacer(); Text(ByteCountFormatter.string(fromByteCount: library.storageBytes(), countStyle: .file)).foregroundStyle(.secondary) }
                TextField("New playlist name", text: $playlistName)
                Button("Create playlist") { library.createPlaylist(name: playlistName); playlistName = "" }
                ForEach(library.playlists) { Text($0.name) }
            }
            Section("Privacy") {
                Label("No analytics SDK", systemImage: "checkmark.shield")
                Label("No ad SDK", systemImage: "checkmark.shield")
                Label("Library metadata stays on device", systemImage: "lock.iphone")
            }
            Section("Source policy") {
                Text("Downloads are enabled for direct media you are authorized to save. YouTube hosts are blocked at the downloader service layer and use permitted YouTube playback instead.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("About") {
                LabeledContent("App", value: "ReyStream")
                LabeledContent("Version", value: "1.1.0")
            }
        }
        .navigationTitle("Settings")
    }
}
