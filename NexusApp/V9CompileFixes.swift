import Foundation

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
