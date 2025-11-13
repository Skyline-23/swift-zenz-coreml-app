import Foundation
import SwiftData

@Model
final class BenchmarkCase {
    var label: String
    var kanaPrompt: String
    var createdAt: Date

    init(label: String, kanaPrompt: String, createdAt: Date = .now) {
        self.label = label
        self.kanaPrompt = kanaPrompt
        self.createdAt = createdAt
    }
}
