//
//  swift_zenz_coreml_appTests.swift
//  swift-zenz-coreml-appTests
//
//  Created by Buseong Kim on 11/12/25.
//

import CoreML
import Testing
@testable import swift_zenz_coreml_app

struct swift_zenz_coreml_appTests {

    private final class DummyStatelessModel: ZenzStatelessPredicting {
        var syncCalls = 0
        var asyncCalls = 0

        func logits(for inputIDs: MLMultiArray) throws -> MLMultiArray {
            syncCalls += 1
            return inputIDs
        }

        func logitsAsync(for inputIDs: MLMultiArray) async throws -> MLMultiArray {
            asyncCalls += 1
            return inputIDs
        }
    }

    @Test func testResolveStatelessPrefersFP16Variant() {
        var fp16Loads = 0
        var bit8Loads = 0
        let expectedModel = DummyStatelessModel()

        let resolved = resolveStatelessModel(
            variant: .standardFP16,
            loadFP16: {
                fp16Loads += 1
                return expectedModel
            },
            load8Bit: {
                bit8Loads += 1
                return DummyStatelessModel()
            }
        )

        #expect(fp16Loads == 1)
        #expect(bit8Loads == 0)
        #expect(resolved is DummyStatelessModel)
    }

    @Test func testResolveStatelessFallsBackWhenCompressedMissing() {
        var fp16Loads = 0
        var bit8Loads = 0
        let fallbackModel = DummyStatelessModel()

        let resolved = resolveStatelessModel(
            variant: .compressed8Bit,
            loadFP16: {
                fp16Loads += 1
                return fallbackModel
            },
            load8Bit: {
                bit8Loads += 1
                return nil
            }
        )

        let resolvedModel = resolved as? DummyStatelessModel
        #expect(bit8Loads == 1)
        #expect(fp16Loads == 1)
        #expect(resolvedModel !== nil)
        #expect(resolvedModel === fallbackModel)
    }

    @Test func testBenchmarkPlanCyclesStatelessAndStateful() {
        let plan = BenchmarkPlanEntry.defaultOrder()
        #expect(plan.count == 4)

        guard plan.count == 4 else { return }
        if case .stateless(let first) = plan[0].kind {
            #expect(first == .standardFP16)
        } else {
            Issue.record("First plan entry must be stateless FP16.")
        }

        if case .stateless(let second) = plan[1].kind {
            #expect(second == .compressed8Bit)
        } else {
            Issue.record("Second plan entry must be stateless 8-bit.")
        }

        if case .stateful(let third) = plan[2].kind {
            #expect(third == .standardFP16)
        } else {
            Issue.record("Third plan entry must be stateful FP16.")
        }
        if case .stateful(let fourth) = plan[3].kind {
            #expect(fourth == .compressed8Bit)
        } else {
            Issue.record("Fourth plan entry must be stateful 8-bit.")
        }
    }
}
