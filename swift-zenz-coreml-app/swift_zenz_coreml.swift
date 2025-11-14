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

extension zenz_v1: ZenzStatelessPredicting {
    func logits(for inputIDs: MLMultiArray) throws -> MLMultiArray {
        let input = zenz_v1Input(input_ids: inputIDs)
        return try prediction(input: input).logits
    }
    func logitsAsync(for inputIDs: MLMultiArray) async throws -> MLMultiArray {
        let input = zenz_v1Input(input_ids: inputIDs)
        return try await prediction(input: input).logits
    }
}

extension zenz_v1_8bit: ZenzStatelessPredicting {
    func logits(for inputIDs: MLMultiArray) throws -> MLMultiArray {
        let input = zenz_v1_8bitInput(input_ids: inputIDs)
        return try prediction(input: input).logits
    }
    func logitsAsync(for inputIDs: MLMultiArray) async throws -> MLMultiArray {
        let input = zenz_v1_8bitInput(input_ids: inputIDs)
        return try await prediction(input: input).logits
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
            return "zenz_v1"
        case .compressed8Bit:
            return "zenz_v1-8bit"
        }
    }

    var uiTitle: String {
        switch self {
        case .standardFP16:
            return "zenz_v1 (FP16 stateless)"
        case .compressed8Bit:
            return "zenz_v1 (8-bit stateless)"
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
    try await withCheckedThrowingContinuation { continuation in
        MLModel.load(contentsOf: url, configuration: configuration) { result in
            switch result {
            case .success(let model):
                continuation.resume(returning: model)
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }
}

// Load the CoreML model.
// CoreML 모델을 로드합니다.
// CoreMLモデルをロードします。
func loadModel() -> zenz_v1? {
    let config = MLModelConfiguration()
    return try? zenz_v1(configuration: config)
}

func loadModelAsync() async -> zenz_v1? {
    do {
        let config = MLModelConfiguration()
        let base = try await loadCoreMLModelAsync(
            from: zenz_v1.urlOfModelInThisBundle,
            configuration: config
        )
        return try zenz_v1(model: base)
    } catch {
        print("[ModelLoad] Failed to async load zenz_v1: \(error)")
        return nil
    }
}

// Load the compressed 8-bit CoreML model.
// 8-bit로 압축된 CoreML 모델을 로드합니다.
// 8-bit に圧縮された Core ML モデルを読み込みます。
func loadModel8Bit() -> zenz_v1_8bit? {
    let config = MLModelConfiguration()
    return try? zenz_v1_8bit(configuration: config)
}

func loadModel8BitAsync() async -> zenz_v1_8bit? {
    do {
        let config = MLModelConfiguration()
        let base = try await loadCoreMLModelAsync(
            from: zenz_v1_8bit.urlOfModelInThisBundle,
            configuration: config
        )
        return try zenz_v1_8bit(model: base)
    } catch {
        print("[ModelLoad] Failed to async load zenz_v1_8bit: \(error)")
        return nil
    }
}

func resolveStatelessModel(
    variant: ZenzStatelessModelVariant,
    loadFP16: () -> (any ZenzStatelessPredicting)? = { loadModel() },
    load8Bit: () -> (any ZenzStatelessPredicting)? = { loadModel8Bit() }
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
    resolveStatelessModel(variant: variant)
}

func resolveStatelessModelAsync(
    variant: ZenzStatelessModelVariant,
    loadFP16: @escaping () async -> (any ZenzStatelessPredicting)? = { await loadModelAsync() },
    load8Bit: @escaping () async -> (any ZenzStatelessPredicting)? = { await loadModel8BitAsync() }
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
    await resolveStatelessModelAsync(variant: variant)
}
func loadStatefulModel() -> zenz_v1_stateful? {
    do {
        let config = MLModelConfiguration()
        // Load the stateful Core ML model and enable ANE/GPU/CPU (automatic).
        // 상태를 가지는 Core ML 모델을 로드하고 ANE/GPU/CPU 자동 선택을 활성화합니다.
        // ステートフルな Core ML モデルを読み込み、ANE/GPU/CPU の自動選択を有効にします。
        config.computeUnits = .cpuAndGPU
        return try zenz_v1_stateful(configuration: config)
    } catch let error {
        print(error)
        return nil
    }
}

func loadStatefulModelAsync() async -> zenz_v1_stateful? {
    do {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU
        let base = try await loadCoreMLModelAsync(
            from: zenz_v1_stateful.urlOfModelInThisBundle,
            configuration: config
        )
        return try zenz_v1_stateful(model: base)
    } catch {
        print("[ModelLoad] Failed to async load zenz_v1_stateful: \(error)")
        return nil
    }
}
func loadStatefulModel8Bit() -> zenz_v1_stateful_8bit? {
    do {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU
        return try zenz_v1_stateful_8bit(configuration: config)
    } catch let error {
        print(error)
        return nil
    }
}

func loadStatefulModel8BitAsync() async -> zenz_v1_stateful_8bit? {
    do {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU
        let base = try await loadCoreMLModelAsync(
            from: zenz_v1_stateful_8bit.urlOfModelInThisBundle,
            configuration: config
        )
        return try zenz_v1_stateful_8bit(model: base)
    } catch {
        print("[ModelLoad] Failed to async load zenz_v1_stateful_8bit: \(error)")
        return nil
    }
}

enum ZenzStatefulModelVariant: CaseIterable, Hashable {
    case standardFP16
    case compressed8Bit

    var labelSuffix: String {
        switch self {
        case .standardFP16:
            return " [Stateful FP16]"
        case .compressed8Bit:
            return " [Stateful 8-bit]"
        }
    }

    var debugName: String {
        switch self {
        case .standardFP16:
            return "zenz_v1_stateful"
        case .compressed8Bit:
            return "zenz_v1_stateful-8bit"
        }
    }

    var uiTitle: String {
        switch self {
        case .standardFP16:
            return "zenz_v1_stateful (FP16)"
        case .compressed8Bit:
            return "zenz_v1_stateful (8-bit)"
        }
    }

    var uiDescription: String {
        switch self {
        case .standardFP16:
            return "Streaming Core ML graph with full precision states."
        case .compressed8Bit:
            return "Smaller recurrent weights for lower-latency streaming."
        }
    }
}

enum ZenzStatefulModelHandle {
    case fp16(zenz_v1_stateful)
    case compressed8Bit(zenz_v1_stateful_8bit)
}

private extension ZenzStatefulModelHandle {
    func withModel<Result>(
        fp16: (zenz_v1_stateful) -> Result,
        bit8: (zenz_v1_stateful_8bit) -> Result
    ) -> Result {
        switch self {
        case .fp16(let model):
            return fp16(model)
        case .compressed8Bit(let model):
            return bit8(model)
        }
    }

    func withModel<Result>(
        fp16: (zenz_v1_stateful) async -> Result,
        bit8: (zenz_v1_stateful_8bit) async -> Result
    ) async -> Result {
        switch self {
        case .fp16(let model):
            return await fp16(model)
        case .compressed8Bit(let model):
            return await bit8(model)
        }
    }
}
func resolveStatefulModel(
    variant: ZenzStatefulModelVariant,
    loadFP16: () -> zenz_v1_stateful? = { loadStatefulModel() },
    load8Bit: () -> zenz_v1_stateful_8bit? = { loadStatefulModel8Bit() }
) -> ZenzStatefulModelHandle? {
    switch variant {
    case .standardFP16:
        if let model = loadFP16() {
            return .fp16(model)
        }
        if let model = load8Bit() {
            return .compressed8Bit(model)
        }
        return nil
    case .compressed8Bit:
        if let model = load8Bit() {
            return .compressed8Bit(model)
        }
        if let model = loadFP16() {
            return .fp16(model)
        }
        return nil
    }
}

func resolveStatefulModelAsync(
    variant: ZenzStatefulModelVariant,
    loadFP16: @escaping () async -> zenz_v1_stateful? = { await loadStatefulModelAsync() },
    load8Bit: @escaping () async -> zenz_v1_stateful_8bit? = { await loadStatefulModel8BitAsync() }
) async -> ZenzStatefulModelHandle? {
    switch variant {
    case .standardFP16:
        if let model = await loadFP16() {
            return .fp16(model)
        }
        if let fallback = await load8Bit() {
            return .compressed8Bit(fallback)
        }
        return nil
    case .compressed8Bit:
        if let model = await load8Bit() {
            return .compressed8Bit(model)
        }
        if let fallback = await loadFP16() {
            return .fp16(fallback)
        }
        return nil
    }
}

func loadStatefulModelHandleAsync(variant: ZenzStatefulModelVariant = .standardFP16) async -> ZenzStatefulModelHandle? {
    await resolveStatefulModelAsync(variant: variant)
}
private func warmupStatefulModel(_ model: zenz_v1_stateful) async {
    if
        let warmupInputIDs = try? MLMultiArray(shape: [1, 1], dataType: .int32),
        let warmupMask = try? MLMultiArray(shape: [1, 1], dataType: .int32)
    {
        warmupInputIDs[0] = 0
        warmupMask[0] = 1

        let warmupInput = zenz_v1_statefulInput(
            input_ids: warmupInputIDs,
            attention_mask: warmupMask
        )

        _ = try? await model.prediction(
            input: warmupInput,
            using: model.makeState()
        )
    } else {
        print("[Stateful Warmup] Skipped: failed to allocate MLMultiArray.")
    }
}
private func warmupStatefulModel(_ model: zenz_v1_stateful_8bit) async {
    if
        let warmupInputIDs = try? MLMultiArray(shape: [1, 1], dataType: .int32),
        let warmupMask = try? MLMultiArray(shape: [1, 1], dataType: .int32)
    {
        warmupInputIDs[0] = 0
        warmupMask[0] = 1

        let warmupInput = zenz_v1_stateful_8bitInput(
            input_ids: warmupInputIDs,
            attention_mask: warmupMask
        )

        _ = try? await model.prediction(
            input: warmupInput,
            using: model.makeState()
        )
    } else {
        print("[Stateful Warmup][8-bit] Skipped: failed to allocate MLMultiArray.")
    }
}

// Load the Tokenizer model.
// 토크나이저 모델을 로드합니다.
// トークナイザーモデルをロードします。
func loadTokenizer() async -> Tokenizer? {
    guard let modelFolder = Bundle.main.resourceURL else {
        print("Model Folder was not found")
        return nil
    }
    do {
        return try await AutoTokenizer.from(modelFolder: modelFolder)
    } catch {
        fatalError(error.localizedDescription)
    }
}
func predictStateful(text: String, model: zenz_v1_stateful, tokenizer: Tokenizer) -> [String] {
    let state = model.makeState()
    
    // Encode the input text using the tokenizer.
    // 텍스트를 토크나이저를 사용하여 인코딩합니다.
    // トークナイザーを使って入力テキストをエンコードします。
    let inputIDs = tokenizer.encode(text: text)
    generationLog("[Stateful Predict] inputIDs: \(text) \(inputIDs)")
    
    // Create MLMultiArray for input (Int32).
    // 입력을 위한 MLMultiArray를 생성합니다 (Int32).
    // 入力用のMLMultiArrayを作成します（Int32）。
    let seqLen = inputIDs.count
    guard
        let inputArray = try? MLMultiArray(
            shape: [NSNumber(value: 1), NSNumber(value: seqLen)],
            dataType: .int32
        ),
        let attentionMask = try? MLMultiArray(
            shape: [NSNumber(value: 1), NSNumber(value: seqLen)],
            dataType: .int32
        )
    else {
        return []
    }
    
    for (index, token) in inputIDs.enumerated() {
        inputArray[index] = NSNumber(value: token)
        attentionMask[index] = 1
    }
    
    // Use Core ML stateful input type.
    // Core ML stateful 입력 타입을 사용합니다.
    // Core MLのステートフル入力タイプを使用します。
    let input = zenz_v1_statefulInput(input_ids: inputArray, attention_mask: attentionMask)
    
    // Perform stateful prediction.
    // 상태를 가지는 예측을 수행합니다.
    // ステートフルな予測を行います。
    let output = try? model.prediction(input: input, using: state)
    
    // Decode logits (output → logits).
    // 출력 logits을 디코딩합니다 (output → logits).
    // 出力logitsをデコードします（output → logits）。
    let logits = output?.logits
    
    guard let logits else { return [] }
    
    var predictedTokenIDs = [[Int]]()
    for batchID in 0..<logits.shape[0].intValue {
        predictedTokenIDs.append([])
        for i in 0..<logits.shape[1].intValue {
            let maxId = argmaxLogitsRow(logits, batch: batchID, time: i)
            predictedTokenIDs[batchID].append(maxId)
        }
    }
    
    generationLog("predictedTokenIDs: \(predictedTokenIDs)")
    let predictedTexts = predictedTokenIDs.map { tokenizer.decode(tokens: $0) }
    return predictedTexts
}
func predictStateful(text: String, model: zenz_v1_stateful_8bit, tokenizer: Tokenizer) -> [String] {
    let state = model.makeState()

    let inputIDs = tokenizer.encode(text: text)
    generationLog("[Stateful Predict][8-bit] inputIDs: \(text) \(inputIDs)")

    let seqLen = inputIDs.count
    guard
        let inputArray = try? MLMultiArray(
            shape: [NSNumber(value: 1), NSNumber(value: seqLen)],
            dataType: .int32
        ),
        let attentionMask = try? MLMultiArray(
            shape: [NSNumber(value: 1), NSNumber(value: seqLen)],
            dataType: .int32
        )
    else {
        return []
    }

    for (index, token) in inputIDs.enumerated() {
        inputArray[index] = NSNumber(value: token)
        attentionMask[index] = 1
    }

    let input = zenz_v1_stateful_8bitInput(input_ids: inputArray, attention_mask: attentionMask)

    let output = try? model.prediction(input: input, using: state)
    let logits = output?.logits

    guard let logits else { return [] }

    var predictedTokenIDs = [[Int]]()
    for batchID in 0..<logits.shape[0].intValue {
        predictedTokenIDs.append([])
        for i in 0..<logits.shape[1].intValue {
            let maxId = argmaxLogitsRow(logits, batch: batchID, time: i)
            predictedTokenIDs[batchID].append(maxId)
        }
    }

    generationLog("[Stateful Predict][8-bit] predictedTokenIDs: \(predictedTokenIDs)")
    let predictedTexts = predictedTokenIDs.map { tokenizer.decode(tokens: $0) }
    return predictedTexts
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
func greedyPredictStateful(text: String, model: zenz_v1_stateful, tokenizer: Tokenizer) -> String {
    let state = model.makeState()
    var predictedTokenIDs = tokenizer.encode(text: text)
    generationLog("[Stateful Greedy] inputIDs: \(text) \(predictedTokenIDs)")

    let batchSize = 1
    let maxSeqLength = 128
    let eosTokenID: Int32 = 3

    while predictedTokenIDs.count < maxSeqLength {
        let seqLen = predictedTokenIDs.count

        guard
            let inputArray = try? MLMultiArray(
                shape: [NSNumber(value: batchSize), NSNumber(value: seqLen)],
                dataType: .int32
            ),
            let attentionMask = try? MLMultiArray(
                shape: [NSNumber(value: batchSize), NSNumber(value: seqLen)],
                dataType: .int32
            )
        else {
            print("[Stateful Greedy] Failed to allocate MLMultiArray")
            break
        }

        for (index, token) in predictedTokenIDs.enumerated() {
            inputArray[index] = NSNumber(value: token)
            attentionMask[index] = 1
        }

        let input = zenz_v1_statefulInput(input_ids: inputArray, attention_mask: attentionMask)
        guard let output = try? model.prediction(input: input, using: state) else {
            print("[Stateful Greedy] Prediction failed")
            break
        }

        let logits = output.logits
        // stateful 모델은 보통 마지막 토큰에 대해서만 logits를 내보내서 time 차원이 1이다.
        let lastTimeIndex = logits.shape[1].intValue - 1  // 보통 0

        let nextTokenID = argmaxLogitsRow(logits, batch: 0, time: lastTimeIndex)
        generationLog("[Stateful Greedy] step seqLen=\(seqLen), nextTokenID=\(nextTokenID), tokenText=\(tokenizer.decode(tokens: [nextTokenID]))")

        if Int32(nextTokenID) == eosTokenID {
            break
        }

        predictedTokenIDs.append(nextTokenID)
    }

    let predictedText = tokenizer.decode(tokens: predictedTokenIDs)
    return predictedText.replacingOccurrences(of: "[PAD]", with: "")
}
func greedyPredictStateful(text: String, model: zenz_v1_stateful_8bit, tokenizer: Tokenizer) -> String {
    let state = model.makeState()
    var predictedTokenIDs = tokenizer.encode(text: text)
    generationLog("[Stateful Greedy][8-bit] inputIDs: \(text) \(predictedTokenIDs)")

    let batchSize = 1
    let maxSeqLength = 128
    let eosTokenID: Int32 = 3

    while predictedTokenIDs.count < maxSeqLength {
        let seqLen = predictedTokenIDs.count

        guard
            let inputArray = try? MLMultiArray(
                shape: [NSNumber(value: batchSize), NSNumber(value: seqLen)],
                dataType: .int32
            ),
            let attentionMask = try? MLMultiArray(
                shape: [NSNumber(value: batchSize), NSNumber(value: seqLen)],
                dataType: .int32
            )
        else {
            print("[Stateful Greedy][8-bit] Failed to allocate MLMultiArray")
            break
        }

        for (index, token) in predictedTokenIDs.enumerated() {
            inputArray[index] = NSNumber(value: token)
            attentionMask[index] = 1
        }

        let input = zenz_v1_stateful_8bitInput(input_ids: inputArray, attention_mask: attentionMask)
        guard let output = try? model.prediction(input: input, using: state) else {
            print("[Stateful Greedy][8-bit] Prediction failed")
            break
        }

        let logits = output.logits
        let lastTimeIndex = logits.shape[1].intValue - 1

        let nextTokenID = argmaxLogitsRow(logits, batch: 0, time: lastTimeIndex)
        generationLog("[Stateful Greedy][8-bit] step seqLen=\(seqLen), nextTokenID=\(nextTokenID), tokenText=\(tokenizer.decode(tokens: [nextTokenID]))")

        if Int32(nextTokenID) == eosTokenID {
            break
        }

        predictedTokenIDs.append(nextTokenID)
    }

    let predictedText = tokenizer.decode(tokens: predictedTokenIDs)
    return predictedText.replacingOccurrences(of: "[PAD]", with: "")
}
func greedyPredictStatefulAsync(text: String, model: zenz_v1_stateful, tokenizer: Tokenizer) async -> String {
    let state = model.makeState()
    var predictedTokenIDs = tokenizer.encode(text: text)
    generationLog("[Stateful Greedy] inputIDs: \(text) \(predictedTokenIDs)")

    let batchSize = 1
    let maxSeqLength = 128
    let eosTokenID: Int32 = 3

    while predictedTokenIDs.count < maxSeqLength {
        let seqLen = predictedTokenIDs.count

        guard
            let inputArray = try? MLMultiArray(
                shape: [NSNumber(value: batchSize), NSNumber(value: seqLen)],
                dataType: .int32
            ),
            let attentionMask = try? MLMultiArray(
                shape: [NSNumber(value: batchSize), NSNumber(value: seqLen)],
                dataType: .int32
            )
        else {
            print("[Stateful Greedy] Failed to allocate MLMultiArray")
            break
        }

        for (index, token) in predictedTokenIDs.enumerated() {
            inputArray[index] = NSNumber(value: token)
            attentionMask[index] = 1
        }

        let input = zenz_v1_statefulInput(input_ids: inputArray, attention_mask: attentionMask)
        guard let output = try? await model.prediction(input: input, using: state) else {
            print("[Stateful Greedy] Prediction failed")
            break
        }

        let logits = output.logits
        let lastTimeIndex = logits.shape[1].intValue - 1

        let nextTokenID = argmaxLogitsRow(logits, batch: 0, time: lastTimeIndex)
        generationLog("[Stateful Greedy] step seqLen=\(seqLen), nextTokenID=\(nextTokenID), tokenText=\(tokenizer.decode(tokens: [nextTokenID]))")

        if Int32(nextTokenID) == eosTokenID {
            break
        }

        predictedTokenIDs.append(nextTokenID)
    }

    let predictedText = tokenizer.decode(tokens: predictedTokenIDs)
    return predictedText.replacingOccurrences(of: "[PAD]", with: "")
}
func greedyPredictStatefulAsync(text: String, model: zenz_v1_stateful_8bit, tokenizer: Tokenizer) async -> String {
    let state = model.makeState()
    var predictedTokenIDs = tokenizer.encode(text: text)
    generationLog("[Stateful Greedy][8-bit Async] inputIDs: \(text) \(predictedTokenIDs)")

    let batchSize = 1
    let maxSeqLength = 128
    let eosTokenID: Int32 = 3

    while predictedTokenIDs.count < maxSeqLength {
        let seqLen = predictedTokenIDs.count

        guard
            let inputArray = try? MLMultiArray(
                shape: [NSNumber(value: batchSize), NSNumber(value: seqLen)],
                dataType: .int32
            ),
            let attentionMask = try? MLMultiArray(
                shape: [NSNumber(value: batchSize), NSNumber(value: seqLen)],
                dataType: .int32
            )
        else {
            print("[Stateful Greedy][8-bit Async] Failed to allocate MLMultiArray")
            break
        }

        for (index, token) in predictedTokenIDs.enumerated() {
            inputArray[index] = NSNumber(value: token)
            attentionMask[index] = 1
        }

        let input = zenz_v1_stateful_8bitInput(input_ids: inputArray, attention_mask: attentionMask)
        guard let output = try? await model.prediction(input: input, using: state) else {
            print("[Stateful Greedy][8-bit Async] Prediction failed")
            break
        }

        let logits = output.logits
        let lastTimeIndex = logits.shape[1].intValue - 1

        let nextTokenID = argmaxLogitsRow(logits, batch: 0, time: lastTimeIndex)
        generationLog("[Stateful Greedy][8-bit Async] step seqLen=\(seqLen), nextTokenID=\(nextTokenID), tokenText=\(tokenizer.decode(tokens: [nextTokenID]))")

        if Int32(nextTokenID) == eosTokenID {
            break
        }

        predictedTokenIDs.append(nextTokenID)
    }

    let predictedText = tokenizer.decode(tokens: predictedTokenIDs)
    return predictedText.replacingOccurrences(of: "[PAD]", with: "")
}

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
    let statefulModels: [ZenzStatefulModelVariant: ZenzStatefulModelHandle]
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

    var stateful: [ZenzStatefulModelVariant: ZenzStatefulModelHandle] = [:]
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
            BenchmarkPlanEntry(kind: .stateful(.standardFP16)),
            BenchmarkPlanEntry(kind: .stateful(.compressed8Bit))
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

            await statefulHandle.withModel(
                fp16: { await warmupStatefulModel($0) },
                bit8: { await warmupStatefulModel($0) }
            )

            let startAsync = Date()
            let predictedSentenceAsync = await statefulHandle.withModel(
                fp16: { await greedyPredictStatefulAsync(text: kanaInput, model: $0, tokenizer: tokenizer) },
                bit8: { await greedyPredictStatefulAsync(text: kanaInput, model: $0, tokenizer: tokenizer) }
            )
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
                let predictedSentence = statefulHandle.withModel(
                    fp16: { greedyPredictStateful(text: kanaInput, model: $0, tokenizer: tokenizer) },
                    bit8: { greedyPredictStateful(text: kanaInput, model: $0, tokenizer: tokenizer) }
                )
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
