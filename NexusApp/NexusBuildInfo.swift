import Foundation
import SwiftUI

enum NexusBuildInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    static var versionLabel: String {
        version.isEmpty ? "Current" : "v\(version)"
    }

    static var fullLabel: String {
        if version.isEmpty { return "Current build" }
        return build.isEmpty ? "v\(version)" : "v\(version) (\(build))"
    }

    static var productSubtitle: String { "PERSONAL INTELLIGENCE OS" }
}

struct NexusVersionBadge: View {
    var body: some View {
        Text(NexusBuildInfo.fullLabel)
            .font(.caption.bold())
            .foregroundStyle(.cyan)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.cyan.opacity(0.12), in: Capsule())
            .accessibilityLabel("NEXUS version \(NexusBuildInfo.fullLabel)")
    }
}
