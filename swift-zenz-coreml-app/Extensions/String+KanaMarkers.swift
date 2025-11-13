import Foundation

extension String {
    /// Removes the custom kana sentinel markers (\u{EE00}, \u{EE01}) used by tokenizer I/O wrappers.
    func removingKanaMarkers() -> String {
        replacingOccurrences(of: "\u{EE00}", with: "")
            .replacingOccurrences(of: "\u{EE01}", with: "")
    }
}
