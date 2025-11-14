import Foundation

struct BenchmarkAverage: Identifiable {
    let id = UUID()
    let variant: String
    let average: Double
    let samples: Int
}
