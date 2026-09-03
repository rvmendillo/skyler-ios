import SwiftUI

@main
struct MaiChartMakerApp: App {
    @StateObject private var model = ChartMakerModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
    }
}
