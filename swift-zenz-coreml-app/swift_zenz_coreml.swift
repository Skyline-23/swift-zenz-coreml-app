//
//  swift_zenz_coreml.swift
//  swift-zenz-coreml-app
//
//  Created by Buseong Kim on 11/12/25.
//

import CoreML
import Tokenizers
import Foundation

struct BenchmarkResult {
    let label: String
    let duration: TimeInterval
    let input: String
    let output: String
}

// Helper to control verbosity of generation logs.
// 생성 과정에서 너무 많은 로그가 찍히지 않도록 제어하기 위한 헬퍼.
// 生成処理でログが出過ぎないように制御するヘルパー。
enum GenerationLogConfig {
    static var enableVerbose: Bool = false
}

func generationLog(_ message: @autoclosure () -> String) {
    guard GenerationLogConfig.enableVerbose else { return }
    print(message())
}
// Helper to group and sort benchmark results for a single sentence.
// 동일 문장에 대한 벤치마크 결과만 묶어서 정렬/출력하는 헬퍼.
// 同じ文に対するベンチマーク結果だけをまとめてソートして出力するヘルパー。
// Callback to capture benchmark log lines for UI/appending, settable by client/UI.
var onLog: ((String) -> Void)? = nil

/// Registers a UI logger to receive benchmark lines.
/// 한국어: 벤치마크 로그를 UI에서 받을 수 있도록 등록합니다.
/// 日本語: ベンチマークのログをUIで受け取れるように登録します。
public func setBenchmarkLogger(_ handler: @escaping (String) -> Void) {
    onLog = { line in
        // Always forward on the main thread for UI safety.
        if Thread.isMainThread {
            handler(line)
        } else {
            DispatchQueue.main.async { handler(line) }
        }
    }
}

func printBenchmarkRanking(for groupTag: String, benchmarks: [BenchmarkResult]) {
    let filtered = benchmarks.filter { $0.label.contains(groupTag) }
    guard !filtered.isEmpty else { return }
    var text = "===== Benchmark Ranking for \(groupTag) (fast → slow) =====\n"
    for (index, result) in filtered.sorted(by: { $0.duration < $1.duration }).enumerated() {
        text += "\(index + 1). \(result.label): \(result.duration) s \(result.input), \(result.output)\n"
    }
    print(text)
    if Thread.isMainThread {
        onLog?(text)
    } else {
        DispatchQueue.main.async { onLog?(text) }
    }
}

// Shared utility to efficiently compute argmax over logits[batch, time, vocab] for a single time step.
// logits[batch, time, vocab] 한 줄에서 argmax를 빠르게 계산하는 공용 유틸리티.
// logits[batch, time, vocab] の 1 行に対して高速に argmax を計算するユーティリティ。
func argmaxLogitsRow(_ logits: MLMultiArray, batch: Int, time: Int) -> Int {
    let batchSize = logits.shape[0].intValue
    let seqLen = logits.shape[1].intValue
    let vocabSize = logits.shape[2].intValue

    // 1) batch / time 기본 범위 체크
    guard batch >= 0, batch < batchSize, time >= 0, time < seqLen else {
        print("[argmaxLogitsRow] Invalid indices: batch=\(batch), time=\(time), shape=\(logits.shape)")
        return 0
    }

    let base = (batch * seqLen + time) * vocabSize
    let totalCount = logits.count

    // 2) 전체 버퍼 크기 기준으로도 한 번 더 체크
    guard base >= 0, base + vocabSize <= totalCount else {
        print("[argmaxLogitsRow] Out-of-bounds: base=\(base), vocabSize=\(vocabSize), totalCount=\(totalCount)")
        return 0
    }

    switch logits.dataType {
    case .float32:
        // Float32 포인터로 안전하게 캐스팅
        let ptr = logits.dataPointer.assumingMemoryBound(to: Float.self)
        var bestId = 0
        var bestScore = -Float.infinity
        for v in 0..<vocabSize {
            let score = ptr[base + v]
            if score > bestScore {
                bestScore = score
                bestId = v
            }
        }
        return bestId

    case .float16:
        // Float16 포인터로 안전하게 캐스팅
        let ptr = logits.dataPointer.assumingMemoryBound(to: Float16.self)
        var bestId = 0
        var bestScore = -Float.infinity
        for v in 0..<vocabSize {
            let score = Float(ptr[base + v])
            if score > bestScore {
                bestScore = score
                bestId = v
            }
        }
        return bestId

    default:
        // 지원하지 않는 타입이면 기존 안전하지만 느린 방식으로
        return (0..<vocabSize).max {
            logits[[batch, time, $0] as [NSNumber]].floatValue <
            logits[[batch, time, $1] as [NSNumber]].floatValue
        } ?? 0
    }
}

protocol ZenzStatelessPredicting: AnyObject {
    func logits(for inputIDs: MLMultiArray) throws -> MLMultiArray
    func logitsAsync(for inputIDs: MLMultiArray) async throws -> MLMultiArray
}

private final class GenericStatelessCoreMLModel: ZenzStatelessPredicting {
    let model: MLModel

    init(model: MLModel) {
        self.model = model
    }

    func logits(for inputIDs: MLMultiArray) throws -> MLMultiArray {
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIDs),
        ])
        let output = try model.prediction(from: input, options: MLPredictionOptions())
        return output.featureValue(for: "logits")!.multiArrayValue!
    }

    func logitsAsync(for inputIDs: MLMultiArray) async throws -> MLMultiArray {
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIDs),
        ])
        let output = try await model.prediction(from: input, options: MLPredictionOptions())
        return output.featureValue(for: "logits")!.multiArrayValue!
    }
}

private final class GenericStatefulCoreMLModel {
    let model: MLModel

    init(model: MLModel) {
        self.model = model
    }

    func makeState() -> MLState {
        model.makeState()
    }

    func logits(
        inputIDs: MLMultiArray,
        attentionMask: MLMultiArray,
        using state: MLState
    ) throws -> MLMultiArray {
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIDs),
            "attention_mask": MLFeatureValue(multiArray: attentionMask),
        ])
        let output = try model.prediction(from: input, using: state, options: MLPredictionOptions())
        return output.featureValue(for: "logits")!.multiArrayValue!
    }

    func logitsAsync(
        inputIDs: MLMultiArray,
        attentionMask: MLMultiArray,
        using state: MLState
    ) async throws -> MLMultiArray {
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIDs),
            "attention_mask": MLFeatureValue(multiArray: attentionMask),
        ])
        let output = try await model.prediction(from: input, using: state, options: MLPredictionOptions())
        return output.featureValue(for: "logits")!.multiArrayValue!
    }
}

protocol ZenzStatefulBenchmarkingModel {
    func warmup() async
    func greedyPredict(text: String, tokenizer: Tokenizer) -> String
    func greedyPredictAsync(text: String, tokenizer: Tokenizer) async -> String
}

private func makeInt32Matrix(tokens: [Int]) -> MLMultiArray? {
    guard let array = try? MLMultiArray(
        shape: [NSNumber(value: 1), NSNumber(value: tokens.count)],
        dataType: .int32
    ) else {
        return nil
    }

    for (index, token) in tokens.enumerated() {
        array[index] = NSNumber(value: token)
    }
    return array
}

private func makeAttentionMask(length: Int) -> MLMultiArray? {
    guard let array = try? MLMultiArray(
        shape: [NSNumber(value: 1), NSNumber(value: length)],
        dataType: .int32
    ) else {
        return nil
    }

    for index in 0..<length {
        array[index] = 1
    }
    return array
}

private final class StatefulRunner: ZenzStatefulBenchmarkingModel {
    private let model: GenericStatefulCoreMLModel
    private let eosTokenID: Int32 = 3
    private let maxSeqLength = 128

    init(model: GenericStatefulCoreMLModel) {
        self.model = model
    }

    func warmup() async {
        guard
            let input = makeInt32Matrix(tokens: [0]),
            let mask = makeAttentionMask(length: 1)
        else { return }
        let state = model.makeState()
        _ = try? await model.logitsAsync(inputIDs: input, attentionMask: mask, using: state)
    }

    func greedyPredict(text: String, tokenizer: Tokenizer) -> String {
        let state = model.makeState()
        var predictedTokenIDs = tokenizer.encode(text: text)
        guard
            let prefillInput = makeInt32Matrix(tokens: predictedTokenIDs),
            let prefillMask = makeAttentionMask(length: predictedTokenIDs.count),
            let prefillLogits = try? model.logits(inputIDs: prefillInput, attentionMask: prefillMask, using: state)
        else {
            return ""
        }

        var nextTokenID = argmaxLogitsRow(prefillLogits, batch: 0, time: prefillLogits.shape[1].intValue - 1)
        while predictedTokenIDs.count < maxSeqLength {
            if Int32(nextTokenID) == eosTokenID {
                break
            }
            predictedTokenIDs.append(nextTokenID)

            guard
                let decodeInput = makeInt32Matrix(tokens: [nextTokenID]),
                let decodeMask = makeAttentionMask(length: 1),
                let decodeLogits = try? model.logits(inputIDs: decodeInput, attentionMask: decodeMask, using: state)
            else {
                break
            }
            nextTokenID = argmaxLogitsRow(decodeLogits, batch: 0, time: decodeLogits.shape[1].intValue - 1)
        }
        return tokenizer.decode(tokens: predictedTokenIDs).replacingOccurrences(of: "[PAD]", with: "")
    }

    func greedyPredictAsync(text: String, tokenizer: Tokenizer) async -> String {
        let state = model.makeState()
        var predictedTokenIDs = tokenizer.encode(text: text)
        guard !predictedTokenIDs.isEmpty else { return "" }

        guard
            let prefillInput = makeInt32Matrix(tokens: predictedTokenIDs),
            let prefillMask = makeAttentionMask(length: predictedTokenIDs.count),
            let prefillLogits = try? await model.logitsAsync(inputIDs: prefillInput, attentionMask: prefillMask, using: state)
        else {
            return ""
        }

        var nextTokenID = argmaxLogitsRow(prefillLogits, batch: 0, time: prefillLogits.shape[1].intValue - 1)
        while predictedTokenIDs.count < maxSeqLength {
            if Int32(nextTokenID) == eosTokenID {
                break
            }
            predictedTokenIDs.append(nextTokenID)

            guard
                let decodeInput = makeInt32Matrix(tokens: [nextTokenID]),
                let decodeMask = makeAttentionMask(length: 1),
                let decodeLogits = try? await model.logitsAsync(inputIDs: decodeInput, attentionMask: decodeMask, using: state)
            else {
                break
            }
            nextTokenID = argmaxLogitsRow(decodeLogits, batch: 0, time: decodeLogits.shape[1].intValue - 1)
        }

        return tokenizer.decode(tokens: predictedTokenIDs).replacingOccurrences(of: "[PAD]", with: "")
    }
}

enum ZenzStatelessModelVariant: CaseIterable, Hashable {
    case standardFP16
    case compressed8Bit

    var labelSuffix: String {
        switch self {
        case .standardFP16:
            return " [FP16]"
        case .compressed8Bit:
            return " [8-bit]"
        }
    }

    var debugName: String {
        switch self {
        case .standardFP16:
            return "zenz_v3.1"
        case .compressed8Bit:
            return "zenz_v3.1-8bit"
        }
    }

    var uiTitle: String {
        switch self {
        case .standardFP16:
            return "zenz_3.1 (FP16 stateless)"
        case .compressed8Bit:
            return "zenz_3.1 (8-bit stateless)"
        }
    }

    var uiDescription: String {
        switch self {
        case .standardFP16:
            return "Highest fidelity logits with the largest memory footprint."
        case .compressed8Bit:
            return "Quantized for lower RAM/GPU demand at the cost of precision."
        }
    }
}

// MARK: - Asynchronous Core ML loading helpers

private func loadCoreMLModelAsync(
    from url: URL,
    configuration: MLModelConfiguration
) async throws -> MLModel {
    return try await MLModel.load(contentsOf: url, configuration: configuration)
}

private func loadBundledStatelessModel(resourceName: String) async -> (any ZenzStatelessPredicting)? {
    guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mlmodelc") else {
        print("[ModelLoad] Missing bundled stateless model: \(resourceName).mlmodelc")
        return nil
    }

    do {
        let config = MLModelConfiguration()
        let model = try await loadCoreMLModelAsync(from: url, configuration: config)
        return GenericStatelessCoreMLModel(model: model)
    } catch {
        print("[ModelLoad] Failed to load bundled stateless model \(resourceName): \(error)")
        return nil
    }
}

func resolveStatelessModel(
    variant: ZenzStatelessModelVariant,
    loadFP16: () -> (any ZenzStatelessPredicting)?,
    load8Bit: () -> (any ZenzStatelessPredicting)?
) -> (any ZenzStatelessPredicting)? {
    switch variant {
    case .standardFP16:
        if let model = loadFP16() {
            return model
        }
        return load8Bit()
    case .compressed8Bit:
        if let model = load8Bit() {
            return model
        }
        return loadFP16()
    }
}

func loadStatelessModel(variant: ZenzStatelessModelVariant = .standardFP16) -> (any ZenzStatelessPredicting)? {
    resolveStatelessModel(
        variant: variant,
        loadFP16: { nil },
        load8Bit: { nil }
    )
}

func resolveStatelessModelAsync(
    variant: ZenzStatelessModelVariant,
    loadFP16: @escaping () async -> (any ZenzStatelessPredicting)?,
    load8Bit: @escaping () async -> (any ZenzStatelessPredicting)?
) async -> (any ZenzStatelessPredicting)? {
    switch variant {
    case .standardFP16:
        if let model = await loadFP16() {
            return model
        }
        return await load8Bit()
    case .compressed8Bit:
        if let model = await load8Bit() {
            return model
        }
        return await loadFP16()
    }
}

func loadStatelessModelAsync(variant: ZenzStatelessModelVariant = .standardFP16) async -> (any ZenzStatelessPredicting)? {
    await resolveStatelessModelAsync(
        variant: variant,
        loadFP16: { await loadBundledStatelessModel(resourceName: "zenz_v3.1") },
        load8Bit: { await loadBundledStatelessModel(resourceName: "zenz_v3.1-8bit") }
    )
}
private func loadBundledStatefulRunner(resourceName: String) async -> StatefulRunner? {
    guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mlmodelc") else {
        print("[ModelLoad] Missing bundled model: \(resourceName).mlmodelc")
        return nil
    }

    do {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU
        let model = try await loadCoreMLModelAsync(from: url, configuration: config)
        return StatefulRunner(model: GenericStatefulCoreMLModel(model: model))
    } catch {
        print("[ModelLoad] Failed to load bundled stateful model \(resourceName): \(error)")
        return nil
    }
}

private func loadStatefulRunner(fp16: Bool) async -> StatefulRunner? {
    do {
        let statefulPath = fp16
            ? "Artifacts/stateful/zenz-stateful-fp16.mlpackage"
            : "Artifacts/stateful/zenz-stateful-8bit.mlpackage"

        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU

        guard let bundleRoot = Bundle.main.resourceURL else {
            print("[ModelLoad] Missing bundle resource URL for stateful model.")
            return nil
        }

        let stateful = try await loadCoreMLModelAsync(
            from: bundleRoot.appendingPathComponent(statefulPath),
            configuration: config
        )

        return StatefulRunner(model: GenericStatefulCoreMLModel(model: stateful))
    } catch {
        print("[ModelLoad] Failed to load bundled stateful runner: \(error)")
        return nil
    }
}

enum ZenzStatefulModelVariant: CaseIterable, Hashable {
    case statefulFP16
    case stateful8Bit

    var labelSuffix: String {
        switch self {
        case .statefulFP16:
            return " [Stateful FP16]"
        case .stateful8Bit:
            return " [Stateful 8-bit]"
        }
    }

    var debugName: String {
        switch self {
        case .statefulFP16:
            return "stateful_fp16"
        case .stateful8Bit:
            return "stateful_8bit"
        }
    }

    var uiTitle: String {
        switch self {
        case .statefulFP16:
            return "zenz_3.1 (FP16 stateful)"
        case .stateful8Bit:
            return "zenz_3.1 (8-bit stateful)"
        }
    }

    var uiDescription: String {
        switch self {
        case .statefulFP16:
            return "Single cached generation path with full-precision weights."
        case .stateful8Bit:
            return "Single cached generation path with smaller 8-bit weights."
        }
    }
}

func loadStatefulModelHandleAsync(
    variant: ZenzStatefulModelVariant = .statefulFP16
) async -> (any ZenzStatefulBenchmarkingModel)? {
    switch variant {
    case .statefulFP16:
        return await loadStatefulRunner(fp16: true)
    case .stateful8Bit:
        return await loadStatefulRunner(fp16: false)
    }
}

// Load the Tokenizer model.
// 토크나이저 모델을 로드합니다.
// トークナイザーモデルをロードします。
func loadTokenizer() async -> Tokenizer? {
    guard
        let modelFolder = Bundle.main.resourceURL,
        FileManager.default.fileExists(atPath: modelFolder.appendingPathComponent("tokenizer/tokenizer.json").path)
    else {
        print("[Tokenizer] tokenizer.json missing from bundle Resources.")
        return nil
    }

    do {
        return try await AutoTokenizer.from(modelFolder: modelFolder)
    } catch {
        print("[Tokenizer] Failed to load bundled tokenizer: \(error)")
        return nil
    }
}

// Perform prediction.
// 예측을 수행합니다.
// 予測を行います。
func predict(text: String, model: any ZenzStatelessPredicting, tokenizer: Tokenizer) -> [String] {
    // Encode the input text using the tokenizer.
    // 텍스트를 토크나이저를 사용하여 인코딩합니다.
    // トークナイザーを使って入力テキストをエンコードします。
    let inputIDs = tokenizer.encode(text: text)
    generationLog("[Stateless Predict][Sync] inputIDs: \(text) \(inputIDs)")
    
    // Create MLMultiArray for input.
    // 입력을 위한 MLMultiArray를 생성합니다.
    // 入力用のMLMultiArrayを作成します。
    let inputArray = try? MLMultiArray(shape: [1, 16], dataType: .float32)
    for (index, token) in inputIDs.enumerated() {
        inputArray?[index] = NSNumber(value: token)
    }
    
    guard let inputArray else { return [] }

    guard let logits = try? model.logits(for: inputArray) else {
        return []
    }
    
    // Extract predicted token IDs from logits.
    // logits에서 예측된 토큰 ID를 추출합니다.
    // logitsから予測されたトークンIDを抽出します。
    var predictedTokenIDs = [[Int]]()
    for batchID in 0..<logits.shape[0].intValue {
        predictedTokenIDs.append([])
        for i in 0..<logits.shape[1].intValue {
            let maxId = argmaxLogitsRow(logits, batch: batchID, time: i)
            predictedTokenIDs[batchID].append(maxId)
        }
    }
    
    // Decode the predicted token IDs back to text.
    // 예측된 토큰 ID를 다시 텍스트로 디코딩합니다.
    // 予測されたトークンIDをテキストにデコードします。
    generationLog("predictedTokenIDs (sync predict): \(predictedTokenIDs)")
    let predictedTexts = predictedTokenIDs.map { tokenizer.decode(tokens: $0) }
    
    // Print the result.
    // 결과를 출력합니다.
    // 結果を出力します。
    return predictedTexts
}

// Perform prediction.
// 예측을 수행합니다.
// 予測を行います。
func predict(text: String, model: any ZenzStatelessPredicting, tokenizer: Tokenizer) async -> [String] {
    // Encode the input text using the tokenizer.
    // 텍스트를 토크나이저를 사용하여 인코딩합니다.
    // トークナイザーを使って入力テキストをエンコードします。
    let inputIDs = tokenizer.encode(text: text)
    generationLog("[Stateless Predict][Async] inputIDs: \(text) \(inputIDs)")
    
    // Create MLMultiArray for input.
    // 입력을 위한 MLMultiArray를 생성합니다.
    // 入力用のMLMultiArrayを作成します。
    let inputArray = try? MLMultiArray(shape: [1, 16], dataType: .float32)
    for (index, token) in inputIDs.enumerated() {
        inputArray?[index] = NSNumber(value: token)
    }
    
    guard let inputArray else { return [] }

    guard let logits = try? await model.logitsAsync(for: inputArray) else {
        return []
    }
    
    // Extract predicted token IDs from logits.
    // logits에서 예측된 토큰 ID를 추출합니다.
    // logitsから予測されたトークンIDを抽出します。
    var predictedTokenIDs = [[Int]]()
    for batchID in 0..<logits.shape[0].intValue {
        predictedTokenIDs.append([])
        for i in 0..<logits.shape[1].intValue {
            let maxId = argmaxLogitsRow(logits, batch: batchID, time: i)
            predictedTokenIDs[batchID].append(maxId)
        }
    }
    
    // Decode the predicted token IDs back to text.
    // 예측된 토큰 ID를 다시 텍스트로 디코딩합니다.
    // 予測されたトークンIDをテキストにデコードします。
    generationLog("predictedTokenIDs (async predict): \(predictedTokenIDs)")
    let predictedTexts = predictedTokenIDs.map { tokenizer.decode(tokens: $0) }
    
    // Print the result.
    // 결과를 출력합니다.
    // 結果を出力します。
    return predictedTexts
}

// Perform greedy token-by-token generation using the stateful Core ML model and its KV cache.
// Stateful Core ML 모델과 KV 캐시를 사용해서 Greedy Search로 토큰을 한 단계씩 생성합니다.
// ステートフルな Core ML モデルと KV キャッシュを使い、Greedy サーチでトークンを一つずつ生成します。

// Perform prediction using Greedy search.
// Greedy search를 사용하여 예측을 수행합니다.
// Greedyサーチを使って予測を行います。
func greedyPredict(text: String, model: any ZenzStatelessPredicting, tokenizer: Tokenizer) -> String {
    var inputIDs = tokenizer.encode(text: text)
    generationLog("[Stateless Greedy][Sync] inputIDs: \(text) \(inputIDs)")

    let maxSeqLength = 128
    let batchSize = 1
    var predictedTokenIDs = inputIDs

    while true {
        guard
            let inputArray = try? MLMultiArray(
                shape: [NSNumber(value: batchSize), NSNumber(value: predictedTokenIDs.count)],
                dataType: .int32
            )
        else {
            return ""
        }

        for (index, token) in predictedTokenIDs.enumerated() {
            inputArray[index] = NSNumber(value: token)
        }

        guard let logits = try? model.logits(for: inputArray) else {
            return ""
        }

        let nextTokenID = argmaxLogitsRow(
            logits,
            batch: 0,
            time: predictedTokenIDs.count - 1
        )

        if nextTokenID == 3 {
            break
        }

        predictedTokenIDs.append(nextTokenID)

        if predictedTokenIDs.count >= maxSeqLength {
            break
        }
    }

    let predictedText = tokenizer.decode(tokens: predictedTokenIDs)
    return predictedText
}

// Perform prediction using Greedy search.
// Greedy search를 사용하여 예측을 수행합니다.
// Greedyサーチを使って予測を行います。
func greedyPredictAsync(text: String, model: any ZenzStatelessPredicting, tokenizer: Tokenizer) async -> String {
    var inputIDs = tokenizer.encode(text: text)
    generationLog("[Stateless Greedy][Async] inputIDs: \(text) \(inputIDs)")

    let maxSeqLength = 128
    let batchSize = 1
    var predictedTokenIDs = inputIDs

    while true {
        guard
            let inputArray = try? MLMultiArray(
                shape: [NSNumber(value: batchSize), NSNumber(value: predictedTokenIDs.count)],
                dataType: .int32
            )
        else {
            return ""
        }

        for (index, token) in predictedTokenIDs.enumerated() {
            inputArray[index] = NSNumber(value: token)
        }

        guard let logits = try? await model.logitsAsync(for: inputArray) else {
            return ""
        }

        let nextTokenID = argmaxLogitsRow(
            logits,
            batch: 0,
            time: predictedTokenIDs.count - 1
        )

        if nextTokenID == 3 {
            break
        }

        predictedTokenIDs.append(nextTokenID)

        if predictedTokenIDs.count >= maxSeqLength {
            break
        }
    }

    let predictedText = tokenizer.decode(tokens: predictedTokenIDs)
    return predictedText
}

/// Configuration describing which Core ML variants should be loaded.
/// 한국어: 로드할 Core ML 모델 종류를 정의하는 설정입니다.
/// 日本語: 読み込む Core ML モデルの種類を定義する設定です。
struct ModelLoadConfiguration: Equatable {
    let stateless: Set<ZenzStatelessModelVariant>
    let stateful: Set<ZenzStatefulModelVariant>

    static let empty = ModelLoadConfiguration(stateless: [], stateful: [])

    var isEmpty: Bool {
        stateless.isEmpty && stateful.isEmpty
    }

    var summaryDescription: String {
        let statelessNames = ZenzStatelessModelVariant.allCases
            .filter { stateless.contains($0) }
            .map { $0.uiTitle }
        let statefulNames = ZenzStatefulModelVariant.allCases
            .filter { stateful.contains($0) }
            .map { $0.uiTitle }

        func describe(_ name: String, items: [String]) -> String {
            if items.isEmpty {
                return "\(name): none"
            }
            return "\(name): \(items.joined(separator: ", "))"
        }

        return [
            describe("stateless", items: statelessNames),
            describe("stateful", items: statefulNames)
        ].joined(separator: " | ")
    }
}

// Shared benchmark environment (model + tokenizer) initialized once and reused.
// 벤치마크 공통 환경 (모델 + 토크나이저)을 한 번만 초기화해서 재사용하기 위한 구조체.
// ベンチマーク共通の環境（モデル + トークナイザー）を一度だけ初期化して再利用するための構造体。
struct BenchmarkEnvironment {
    let tokenizer: Tokenizer
    let statelessModels: [ZenzStatelessModelVariant: any ZenzStatelessPredicting]
    let statefulModels: [ZenzStatefulModelVariant: any ZenzStatefulBenchmarkingModel]
}

// Load the models and tokenizer for the requested configuration.
// 요청된 설정에 따라 모델과 토크나이저를 로드합니다.
// 指定された設定に従ってモデルとトークナイザーをロードします。
func makeBenchmarkEnvironment(config: ModelLoadConfiguration) async -> BenchmarkEnvironment? {
    guard !config.isEmpty else {
        print("[BenchmarkEnvironment] Skipped loading: empty configuration.")
        return nil
    }

    let tokenizer = await loadTokenizer()
    guard let tokenizer else { fatalError("tokenizer not found") }

    var stateless: [ZenzStatelessModelVariant: any ZenzStatelessPredicting] = [:]
    for variant in ZenzStatelessModelVariant.allCases where config.stateless.contains(variant) {
        guard let model = await loadStatelessModelAsync(variant: variant) else {
            print("[BenchmarkEnvironment] Missing stateless model \(variant.debugName).")
            continue
        }
        stateless[variant] = model
    }

    var stateful: [ZenzStatefulModelVariant: any ZenzStatefulBenchmarkingModel] = [:]
    for variant in ZenzStatefulModelVariant.allCases where config.stateful.contains(variant) {
        guard let handle = await loadStatefulModelHandleAsync(variant: variant) else {
            print("[BenchmarkEnvironment] Missing stateful model \(variant.debugName).")
            continue
        }
        stateful[variant] = handle
    }

    guard !stateless.isEmpty || !stateful.isEmpty else {
        print("[BenchmarkEnvironment] Failed to load any selected models.")
        return nil
    }

    return BenchmarkEnvironment(
        tokenizer: tokenizer,
        statelessModels: stateless,
        statefulModels: stateful
    )
}

struct BenchmarkPlanEntry {
    enum Kind {
        case stateless(ZenzStatelessModelVariant)
        case stateful(ZenzStatefulModelVariant)
    }

    let kind: Kind

    var labelSuffix: String {
        switch kind {
        case .stateless(let variant):
            return variant.labelSuffix
        case .stateful(let variant):
            return variant.labelSuffix
        }
    }

    static func defaultOrder() -> [BenchmarkPlanEntry] {
        [
            BenchmarkPlanEntry(kind: .stateless(.standardFP16)),
            BenchmarkPlanEntry(kind: .stateless(.compressed8Bit)),
            BenchmarkPlanEntry(kind: .stateful(.statefulFP16)),
            BenchmarkPlanEntry(kind: .stateful(.stateful8Bit))
        ]
    }
}

// For the given sentence (kana input), run both stateless and stateful benchmarks and print grouped rankings.
// 주어진 문장(카타카나 입력)에 대해 Stateless / Stateful 양쪽 벤치마크를 실행하고, 그룹별 랭킹을 출력합니다.
// 与えられた文（カタカナ入力）に対して Stateless / Stateful の両方のベンチマークを実行し、グループ別ランキングを出力します。
func runBenchmarksFor(
    groupTag: String,
    kanaInput: String,
    env: BenchmarkEnvironment,
    includeSync: Bool
) async {
    var benchmarks: [BenchmarkResult] = []
    let tokenizer = env.tokenizer

    let plan = BenchmarkPlanEntry.defaultOrder()
    let activePlan = plan.filter { entry in
        switch entry.kind {
        case .stateless(let variant):
            return env.statelessModels[variant] != nil
        case .stateful(let variant):
            return env.statefulModels[variant] != nil
        }
    }

    guard !activePlan.isEmpty else {
        print("[Benchmarks] Skipped: No Core ML models loaded for \(groupTag).")
        return
    }

    for entry in activePlan {
        switch entry.kind {
        case .stateless(let variant):
            guard let statelessModel = env.statelessModels[variant] else {
                print("[Stateless Greedy]\(variant.debugName) Skipped: model not loaded.")
                continue
            }

            let startAsync = Date()
            let predictedSentenceAsync = await greedyPredictAsync(text: kanaInput, model: statelessModel, tokenizer: tokenizer)
            let durationAsync = Date().timeIntervalSince(startAsync)
            benchmarks.append(
                BenchmarkResult(
                    label: "[Stateless Greedy][Async global]\(variant.labelSuffix)\(groupTag)",
                    duration: durationAsync,
                    input: kanaInput,
                    output: predictedSentenceAsync
                )
            )

            if includeSync {
                let startSync = Date()
                let predictedSentence = greedyPredict(text: kanaInput, model: statelessModel, tokenizer: tokenizer)
                let durationSync = Date().timeIntervalSince(startSync)
                benchmarks.append(
                    BenchmarkResult(
                        label: "[Stateless Greedy][Sync main]\(variant.labelSuffix)\(groupTag)",
                        duration: durationSync,
                        input: kanaInput,
                        output: predictedSentence
                    )
                )
            }

        case .stateful(let variant):
            guard let statefulHandle = env.statefulModels[variant] else {
                print("[Stateful Greedy]\(variant.debugName) Skipped: model not loaded.")
                continue
            }

            await statefulHandle.warmup()

            let startAsync = Date()
            let predictedSentenceAsync = await statefulHandle.greedyPredictAsync(text: kanaInput, tokenizer: tokenizer)
            let durationAsync = Date().timeIntervalSince(startAsync)
            benchmarks.append(
                BenchmarkResult(
                    label: "[Stateful Greedy][Async global]\(variant.labelSuffix)\(groupTag)",
                    duration: durationAsync,
                    input: kanaInput,
                    output: predictedSentenceAsync
                )
            )

            if includeSync {
                let startSync = Date()
                let predictedSentence = statefulHandle.greedyPredict(text: kanaInput, tokenizer: tokenizer)
                let durationSync = Date().timeIntervalSince(startSync)
                benchmarks.append(
                    BenchmarkResult(
                        label: "[Stateful Greedy][Sync main]\(variant.labelSuffix)\(groupTag)",
                        duration: durationSync,
                        input: kanaInput,
                        output: predictedSentence
                    )
                )
            }
        }
    }
    
    // Print benchmark ranking for this group (sentence).
    // 이 그룹(문장)에 대한 벤치마크 랭킹을 출력합니다.
    // このグループ（文）に対するベンチマークランキングを出力します。
    printBenchmarkRanking(for: groupTag, benchmarks: benchmarks)
}
