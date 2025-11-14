import Foundation
import SwiftUI
import MachO
import Darwin
import Combine

@MainActor
final class MemoryUsageMonitor: ObservableObject {
    @Published private(set) var samples: [MemorySample] = []
    @Published private(set) var currentMegabytes: Double?

    private var timer: Timer?
    private let sampleInterval: TimeInterval = 2.0
    private let maxSamples = 60

    func start() {
        guard timer == nil else { return }

        let newTimer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { [weak self] _ in
            self?.captureSample()
        }
        newTimer.tolerance = 0.4
        timer = newTimer
        captureSample()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func captureSample() {
        guard let sample = MemorySample.capture() else { return }
        currentMegabytes = sample.megabytes
        samples.append(sample)
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
    }
}

struct MemorySample: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let megabytes: Double

    static func capture() -> MemorySample? {
        guard let mb = MemoryFootprintReader.currentMegabytes() else { return nil }
        return MemorySample(timestamp: Date(), megabytes: mb)
    }
}

enum MemoryFootprintReader {
    static func currentMegabytes() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) { infoPointer in
            infoPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }
        let footprintBytes = info.phys_footprint
        return Double(footprintBytes) / 1_048_576.0
    }
}
