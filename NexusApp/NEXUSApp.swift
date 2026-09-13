import SwiftUI

@main
struct NEXUSApp: App {
    @StateObject private var model = NexusModel()
    var body: some Scene {
        WindowGroup {
            RootV6View().environmentObject(model)
        }
    }
}
