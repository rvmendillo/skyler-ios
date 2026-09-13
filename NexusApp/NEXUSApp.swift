import SwiftUI

@main
struct NEXUSApp: App {
    @StateObject private var model = NexusModel()
    var body: some Scene {
        WindowGroup {
            RootV7View().environmentObject(model)
        }
    }
}
