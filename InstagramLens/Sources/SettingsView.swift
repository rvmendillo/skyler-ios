import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var analytics: AnalyticsService
    @State private var token = ""
    @State private var userID = ""
    @State private var baseURL = "https://graph.instagram.com"
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Meta / Instagram API") {
                    SecureField("Access token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Instagram user ID", text: $userID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Graph API base URL", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button("Save Securely") {
                        analytics.accessToken = token
                        analytics.userID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
                        analytics.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        saved = true
                    }

                    if saved {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Section("Safety") {
                    Label("No Instagram password is collected", systemImage: "lock.shield")
                    Label("Access token is stored in iOS Keychain", systemImage: "key")
                    Label("No private Instagram API endpoints", systemImage: "checkmark.shield")
                    Text("The app probes only the configured official Graph API. Unsupported metrics are reported rather than replaced with scraped/private data.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Profile visitors") {
                    Text("Instagram does not expose the identities of profile visitors. Profile-view counts may be available depending on account type, API version, permissions and Meta metric availability.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                token = analytics.accessToken
                userID = analytics.userID
                baseURL = analytics.baseURL
            }
        }
    }
}
