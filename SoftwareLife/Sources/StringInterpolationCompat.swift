import Foundation

extension String.StringInterpolation {
    mutating func appendInterpolation(_ value: Double, specifier: String) {
        appendLiteral(String(format: specifier, value))
    }
}
