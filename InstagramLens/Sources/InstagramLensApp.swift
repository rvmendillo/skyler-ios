import SwiftUI

@main
struct InstagramLensApp: App {
    @StateObject private var analytics = AnalyticsService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(analytics)
        }
    }
}
