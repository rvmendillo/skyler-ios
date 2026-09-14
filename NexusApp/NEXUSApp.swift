import SwiftUI

@main
struct NEXUSApp: App {
    @StateObject private var model = NexusModel()

    var body: some Scene {
        WindowGroup {
            RootV8View()
                .environmentObject(model)
                .task {
                    let intelligence = NexusV9IntelligenceStore.shared
                    await intelligence.index(records: model.records, files: NexusV8FileLibrary.shared.files)
                    if intelligence.performanceMode != .battery {
                        await intelligence.warmBestLocalModel()
                    }
                    await NexusPreanalysisStore.shared.analyzePending(NexusV8FileLibrary.shared.files)
                }
                .onOpenURL { url in
                    NexusV9DeepLink.shared.handle(url, model: model)
                }
        }
    }
}
