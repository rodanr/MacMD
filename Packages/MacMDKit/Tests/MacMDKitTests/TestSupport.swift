import Foundation

@testable import MacMDKit

extension Array where Element == StyleSpan {
    /// Substrings of `text` covered by spans of the given kind, in order.
    func substrings(of kind: StyleKind, in text: String) -> [String] {
        filter { $0.kind == kind }.map { (text as NSString).substring(with: $0.range) }
    }
}
