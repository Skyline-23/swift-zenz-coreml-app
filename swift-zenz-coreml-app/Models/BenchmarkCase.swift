import Foundation
import SwiftData

@Model
final class BenchmarkCase {
    var label: String
    var kanaPrompt: String
    var expectedKanaOutput: String
    var createdAt: Date

    init(
        label: String,
        kanaPrompt: String,
        expectedKanaOutput: String = "",
        createdAt: Date = .now
    ) {
        self.label = label
        self.kanaPrompt = kanaPrompt
        self.expectedKanaOutput = expectedKanaOutput
        self.createdAt = createdAt
    }
}
