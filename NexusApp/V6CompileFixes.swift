import Foundation

extension NexusLifeFinding {
    init(id: String,
         kind: NexusLifeFinding.Kind,
         title: String,
         summary: String,
         confidence: Double,
         rationale: ArraySlice<String>,
         alternatives: [String]) {
        self.init(id: id,
                  kind: kind,
                  title: title,
                  summary: summary,
                  confidence: confidence,
                  rationale: Array(rationale),
                  alternatives: alternatives)
    }
}
