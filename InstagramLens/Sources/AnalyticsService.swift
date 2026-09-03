import Foundation
import SwiftUI

@MainActor
final class AnalyticsService: ObservableObject {
    @Published var profile = AccountProfile()
    @Published var media: [MediaItem] = []
    @Published var probes: [ProbeResult] = []
    @Published var snapshots: [AccountSnapshot] = []
    @Published var isLoading = false
    @Published var lastError = ""

    var userID: String {
        get { UserDefaults.standard.string(forKey: "ig_user_id") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "ig_user_id") }
    }

    var baseURL: String {
        get { UserDefaults.standard.string(forKey: "ig_base_url") ?? "https://graph.instagram.com" }
        set { UserDefaults.standard.set(newValue, forKey: "ig_base_url") }
    }

    var accessToken: String {
        get { KeychainStore.get("instagram_access_token") }
        set { KeychainStore.set(newValue, for: "instagram_access_token") }
    }

    private let accountMetricCandidates = [
        "reach",
        "profile_views",
        "accounts_engaged",
        "total_interactions",
        "likes",
        "comments",
        "saves",
        "shares",
        "replies",
        "views",
        "impressions",
        "follows_and_unfollows",
        "profile_links_taps",
        "website_clicks",
        "email_contacts",
        "phone_call_clicks",
        "text_message_clicks",
        "get_directions_clicks"
    ]

    private let mediaMetricCandidates = [
        "views",
        "reach",
        "impressions",
        "likes",
        "comments",
        "saved",
        "shares",
        "total_interactions",
        "follows",
        "profile_activity",
        "plays",
        "replays",
        "ig_reels_avg_watch_time",
        "ig_reels_video_view_total_time",
        "clips_replays_count"
    ]

    init() {
        loadSnapshots()
    }

    func refreshAll() async {
        guard !accessToken.isEmpty, !userID.isEmpty else {
            lastError = "Add an Instagram access token and Instagram user ID in Settings."
            return
        }

        isLoading = true
        lastError = ""
        probes.removeAll()

        do {
            try await fetchProfile()
            try await fetchMedia()
            await probeAccountMetrics()

            if let first = media.first {
                await probeMediaMetrics(mediaID: first.id)
            }

            saveSnapshot()
        } catch {
            lastError = error.localizedDescription
        }

        isLoading = false
    }

    func fetchProfile() async throws {
        let fields = [
            "id", "username", "name", "account_type", "biography", "website",
            "followers_count", "follows_count", "media_count", "profile_picture_url"
        ].joined(separator: ",")

        let json = try await request(path: "/\(userID)", query: [
            URLQueryItem(name: "fields", value: fields)
        ])

        profile = AccountProfile(
            id: string(json["id"]),
            username: string(json["username"]),
            name: string(json["name"]),
            accountType: string(json["account_type"]),
            biography: string(json["biography"]),
            website: string(json["website"]),
            followers: int(json["followers_count"]),
            follows: int(json["follows_count"]),
            mediaCount: int(json["media_count"]),
            profilePictureURL: string(json["profile_picture_url"])
        )
    }

    func fetchMedia() async throws {
        let fields = [
            "id", "caption", "media_type", "media_url", "permalink", "thumbnail_url", "timestamp"
        ].joined(separator: ",")

        let json = try await request(path: "/\(userID)/media", query: [
            URLQueryItem(name: "fields", value: fields),
            URLQueryItem(name: "limit", value: "50")
        ])

        let rows = json["data"] as? [[String: Any]] ?? []
        media = rows.map {
            MediaItem(
                id: string($0["id"]),
                caption: string($0["caption"]),
                mediaType: string($0["media_type"]),
                mediaURL: string($0["media_url"]),
                permalink: string($0["permalink"]),
                thumbnailURL: string($0["thumbnail_url"]),
                timestamp: string($0["timestamp"])
            )
        }
    }

    func probeAccountMetrics() async {
        for metric in accountMetricCandidates {
            let result = await probe(
                scope: "Account",
                path: "/\(userID)/insights",
                metric: metric,
                extra: [URLQueryItem(name: "period", value: "day")]
            )
            probes.append(result)
            try? await Task.sleep(nanoseconds: 180_000_000)
        }
    }

    func probeMediaMetrics(mediaID: String) async {
        for metric in mediaMetricCandidates {
            let result = await probe(
                scope: "Latest Media",
                path: "/\(mediaID)/insights",
                metric: metric,
                extra: []
            )
            probes.append(result)
            try? await Task.sleep(nanoseconds: 180_000_000)
        }
    }

    private func probe(scope: String, path: String, metric: String, extra: [URLQueryItem]) async -> ProbeResult {
        do {
            var query = [URLQueryItem(name: "metric", value: metric)]
            query.append(contentsOf: extra)
            let json = try await request(path: path, query: query)

            let value = extractMetricValue(json)
            return ProbeResult(
                scope: scope,
                metric: metric,
                supported: true,
                value: value,
                detail: value.map { String(format: "%.2f", $0) } ?? "Supported; no numeric value returned"
            )
        } catch {
            return ProbeResult(
                scope: scope,
                metric: metric,
                supported: false,
                value: nil,
                detail: error.localizedDescription
            )
        }
    }

    private func request(path: String, query: [URLQueryItem]) async throws -> [String: Any] {
        guard var components = URLComponents(string: baseURL + path) else {
            throw URLError(.badURL)
        }

        var items = query
        items.append(URLQueryItem(name: "access_token", value: accessToken))
        components.queryItems = items

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        let object = try JSONSerialization.jsonObject(with: data)
        let json = object as? [String: Any] ?? [:]

        if status >= 400 || json["error"] != nil {
            let error = json["error"] as? [String: Any]
            let message = string(error?["message"])
            throw NSError(
                domain: "InstagramLens",
                code: status,
                userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? "Instagram API error \(status)" : message]
            )
        }

        return json
    }

    private func extractMetricValue(_ json: [String: Any]) -> Double? {
        guard let data = json["data"] as? [[String: Any]], let first = data.first else { return nil }

        if let total = first["total_value"] as? [String: Any] {
            if let v = total["value"] as? NSNumber { return v.doubleValue }
        }

        if let values = first["values"] as? [[String: Any]], let last = values.last {
            if let v = last["value"] as? NSNumber { return v.doubleValue }
        }

        if let v = first["value"] as? NSNumber { return v.doubleValue }
        return nil
    }

    private func saveSnapshot() {
        var metricMap: [String: Double] = [:]
        for item in probes {
            if item.supported, let value = item.value {
                metricMap["\(item.scope).\(item.metric)"] = value
            }
        }

        snapshots.insert(
            AccountSnapshot(
                followers: profile.followers,
                follows: profile.follows,
                mediaCount: profile.mediaCount,
                metrics: metricMap
            ),
            at: 0
        )

        snapshots = Array(snapshots.prefix(100))
        if let data = try? JSONEncoder().encode(snapshots) {
            UserDefaults.standard.set(data, forKey: "ig_snapshots")
        }
    }

    private func loadSnapshots() {
        guard let data = UserDefaults.standard.data(forKey: "ig_snapshots"),
              let decoded = try? JSONDecoder().decode([AccountSnapshot].self, from: data) else {
            return
        }
        snapshots = decoded
    }

    func followerDelta() -> Int {
        guard snapshots.count >= 2 else { return 0 }
        return snapshots[0].followers - snapshots[1].followers
    }

    private func string(_ any: Any?) -> String {
        if let value = any as? String { return value }
        if let value = any { return String(describing: value) }
        return ""
    }

    private func int(_ any: Any?) -> Int {
        if let value = any as? Int { return value }
        if let value = any as? NSNumber { return value.intValue }
        if let value = any as? String { return Int(value) ?? 0 }
        return 0
    }
}
