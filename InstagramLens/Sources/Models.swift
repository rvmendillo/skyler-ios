import Foundation

struct AccountProfile: Codable {
    var id: String = ""
    var username: String = ""
    var name: String = ""
    var accountType: String = ""
    var biography: String = ""
    var website: String = ""
    var followers: Int = 0
    var follows: Int = 0
    var mediaCount: Int = 0
    var profilePictureURL: String = ""
}

struct MediaItem: Identifiable, Codable {
    let id: String
    var caption: String?
    var mediaType: String?
    var mediaURL: String?
    var permalink: String?
    var thumbnailURL: String?
    var timestamp: String?
}

struct ProbeResult: Identifiable, Codable {
    let id: UUID
    let scope: String
    let metric: String
    let supported: Bool
    let value: Double?
    let detail: String

    init(scope: String, metric: String, supported: Bool, value: Double?, detail: String) {
        self.id = UUID()
        self.scope = scope
        self.metric = metric
        self.supported = supported
        self.value = value
        self.detail = detail
    }
}

struct AccountSnapshot: Identifiable, Codable {
    let id: UUID
    let date: Date
    let followers: Int
    let follows: Int
    let mediaCount: Int
    let metrics: [String: Double]

    init(date: Date = Date(), followers: Int, follows: Int, mediaCount: Int, metrics: [String: Double]) {
        self.id = UUID()
        self.date = date
        self.followers = followers
        self.follows = follows
        self.mediaCount = mediaCount
        self.metrics = metrics
    }
}
