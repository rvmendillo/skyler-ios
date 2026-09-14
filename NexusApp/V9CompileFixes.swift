import Foundation
import SwiftUI

extension NexusV9AutomationRule.Trigger: Hashable {
    static func == (lhs: NexusV9AutomationRule.Trigger, rhs: NexusV9AutomationRule.Trigger) -> Bool {
        lhs.rawValue == rhs.rawValue
    }
    func hash(into hasher: inout Hasher) { hasher.combine(rawValue) }
}

extension NexusV9AutomationRule.Action: Hashable {
    static func == (lhs: NexusV9AutomationRule.Action, rhs: NexusV9AutomationRule.Action) -> Bool {
        lhs.rawValue == rhs.rawValue
    }
    func hash(into hasher: inout Hasher) { hasher.combine(rawValue) }
}

// Restore the V8 Explore hub that was accidentally dropped when the active
// Build 30 root navigation was updated to expose the whole-person Synthesis tab.
struct ExploreHubV8View: View {
    var body: some View {
        List {
            Section("Shared AI") {
                NavigationLink { FilesV8FastView() } label: {
                    row("Files + Multimodal AI", "View images, PDFs, text and CSV; analyze them with cached extraction and fast shared AI", "folder.fill.badge.gearshape", .cyan)
                }
                NavigationLink { NexusAnalyzedLibraryView() } label: {
                    row("Analyzed Library", "All imported files with persistent multimodal analysis and automatic refresh", "sparkles.rectangle.stack.fill", .purple)
                }
                NavigationLink { AskV8FastView() } label: {
                    row("NEXUS Chat", "Fast answers with compact retrieval, file attachments and optional Deep mode", "bolt.bubble.fill", .mint)
                }
                NavigationLink { SharedModelsV8EnhancedView() } label: {
                    row("Shared AI Models", "Manage shared language models, downloads, deletion and cross-checks", "cpu.fill", .yellow)
                }
                NavigationLink { MultimodalLabV8View() } label: {
                    row("Vision Model Manager", "Local vision for images and visual PDF/page analysis", "eye.fill", .cyan)
                }
            }

            Section("Immersive") {
                NavigationLink { StorybookV7View() } label: { row("Animated Storybook", "Cartoon scenes, narration, music and evidence", "play.square.stack.fill", .pink) }
                NavigationLink { TimelineV6View() } label: { row("Life Timeline", "Searchable chronological evidence", "clock.arrow.trianglehead.counterclockwise.rotate.90", .cyan) }
                NavigationLink { ConversationTwinV7View() } label: { row("Conversation Twin", "Style simulation from imported conversations", "person.2.wave.2.fill", .orange) }
            }

            Section("Reasoning labs") {
                NavigationLink { PersonalityLabV7View() } label: { row("Personality Lab", "Traits, behavior axes, contradictions, self-voice and confidence bands", "person.crop.circle.badge.checkmark", .purple) }
                NavigationLink { LifeAnalysisV6View() } label: { row("Life Compass", "Goals, strengths, weaknesses and direction", "location.north.circle.fill", .green) }
                NavigationLink { StandardizationLabV6View() } label: { row("Universal Patterns", "Patterns standardized across unrelated sources", "point.3.connected.trianglepath.dotted", .cyan) }
                NavigationLink { AIModelLabV6View() } label: { row("AI Ensemble", "Agreement and disagreement between local engines", "brain.head.profile", .purple) }
                NavigationLink { DecisionLabV6View() } label: { row("Decision Lab", "Stress-test choices against evidence", "scale.3d", .mint) }
                NavigationLink { DiscoverV4View() } label: { row("Deep Analysis", "Comprehensive evidence and uncertainty", "scope", .indigo) }
            }

            Section("Advanced") {
                NavigationLink { NexusAdvancedHubView() } label: {
                    row("Advanced NEXUS", "Imports, export, backup/restore and the strongest V9 intelligence, automation and system features", "square.grid.3x3.fill", .indigo)
                }
            }
        }
        .navigationTitle("Explore")
    }

    private func row(_ title: String, _ subtitle: String, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
