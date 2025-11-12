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

// Load the CoreML model.
// CoreML 모델을 로드합니다.
// CoreMLモデルをロードします。
func loadModel() -> zenz_v1? {
    let config = MLModelConfiguration()
    return try? zenz_v1(configuration: config)
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
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

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
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

// Perform prediction.
// 예측을 수행합니다.
// 予測を行います。
func predict(text: String, model: zenz_v1, tokenizer: Tokenizer) -> [String] {
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
    // Create model input (only input_ids, no attention_mask).
    // 모델 입력을 생성합니다 (attention_mask 없이 input_ids만 전달).
    // モデル入力を作成します（attention_maskなしでinput_idsのみ渡します）。
    let input = zenz_v1Input(input_ids: inputArray)
    
    // Perform prediction.
    // 예측을 수행합니다.
    // 予測を行います。
    let output = try? model.prediction(input: input)
    
    // Decode the output logits.
    // 출력 logits을 디코딩합니다.
    // 出力logitsをデコードします。
    let logits = output?.logits
    
    guard let logits else { return [] }
    
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
@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
func predict(text: String, model: zenz_v1, tokenizer: Tokenizer) async -> [String] {
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
    // Create model input (only input_ids, no attention_mask).
    // 모델 입력을 생성합니다 (attention_mask 없이 input_ids만 전달).
    // モデル入力を作成します（attention_maskなしでinput_idsのみ渡します）。
    let input = zenz_v1Input(input_ids: inputArray)
    
    // Perform prediction.
    // 예측을 수행합니다.
    // 予測を行います。
    let output = try? await model.prediction(input: input)
    
    // Decode the output logits.
    // 출력 logits을 디코딩합니다.
    // 出力logitsをデコードします。
    let logits = output?.logits
    
    guard let logits else { return [] }
    
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

@available(macOS, deprecated: 10.14, message: "Use newer API predict(text:model:tokenizer) async")
@available(iOS, deprecated: 16.0, message: "Use newer API predict(text:model:tokenizer) async")
@available(tvOS, deprecated: 16.0, message: "Use newer API predict(text:model:tokenizer) async")
@available(watchOS, deprecated: 9.0, message: "Use newer API predict(text:model:tokenizer) async")
func predictDispatch(text: String, model: zenz_v1, tokenizer: Tokenizer, qos: DispatchQoS) async -> [String] {
    // Avoid capturing non-Sendable CoreML model/tokenizer directly in the @Sendable continuation
    let modelPtr = Unmanaged.passUnretained(model).toOpaque()

    // Tokenizer는 프로토콜(existential)이라서 바로 Unmanaged에 못 넣으니 AnyObject로 올려 태운다
    let tokenizerObject = tokenizer as AnyObject
    let tokenizerPtr = Unmanaged.passUnretained(tokenizerObject).toOpaque()

    return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: qos.qosClass).async {
            // Reconstruct references inside the non-@Sendable Dispatch closure
            let model = Unmanaged<zenz_v1>.fromOpaque(modelPtr).takeUnretainedValue()
            let tokenizerObject = Unmanaged<AnyObject>.fromOpaque(tokenizerPtr).takeUnretainedValue()
            guard let tokenizer = tokenizerObject as? Tokenizer else {
                fatalError("Stored tokenizer does not conform to Tokenizer")
            }

            let result = predict(text: text, model: model, tokenizer: tokenizer)
            continuation.resume(returning: result)
        }
    }
}

// Perform greedy token-by-token generation using the stateful Core ML model and its KV cache.
// Stateful Core ML 모델과 KV 캐시를 사용해서 Greedy Search로 토큰을 한 단계씩 생성합니다.
// ステートフルな Core ML モデルと KV キャッシュを使い、Greedy サーチでトークンを一つずつ生成します。
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
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

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
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

// Perform prediction using Greedy search.
// Greedy search를 사용하여 예측을 수행합니다.
// Greedyサーチを使って予測を行います。
func greedyPredict(text: String, model: zenz_v1, tokenizer: Tokenizer) -> String {
    // Encode the input text using the tokenizer.
    // 텍스트를 토크나이저를 사용하여 인코딩합니다.
    // トークナイザーを使って入力テキストをエンコードします。
    var inputIDs = tokenizer.encode(text: text)
    generationLog("[Stateless Greedy][Sync] inputIDs: \(text) \(inputIDs)")
    
    // Set the maximum sequence length.
    // 최대 시퀀스 길이를 설정합니다.
    // 最大シーケンス長を設定します。
    let maxSeqLength = 128
    let batchSize = 1
    
    // Array to store predicted token IDs.
    // 예측된 토큰 ID를 저장할 배열입니다.
    // 予測されたトークンIDを保存する配列です。
    var predictedTokenIDs = inputIDs
    
    while true {
        // Create MLMultiArray for input.
        // 입력을 위한 MLMultiArray를 생성합니다.
        // 入力用のMLMultiArrayを作成します。
        let inputArray = try? MLMultiArray(shape: [NSNumber(value: batchSize), NSNumber(value: predictedTokenIDs.count)], dataType: .int32)
        for (index, token) in predictedTokenIDs.enumerated() {
            inputArray?[index] = NSNumber(value: token)
        }
        
        guard let inputArray else { return "" }
        
        // Create model input (only input_ids, no attention_mask).
        // 모델 입력을 생성합니다 (attention_mask 없이 input_ids만 전달).
        // モデル入力を作成します（attention_maskなしでinput_idsのみ渡します）。
        let input = zenz_v1Input(input_ids: inputArray)
        
        // Perform prediction.
        // 예측을 수행합니다.
        // 予測を行います。
        guard let output = try? model.prediction(input: input) else { return "" }
        
        // Decode the output logits.
        // 출력 logits을 디코딩합니다.
        // 出力logitsをデコードします。
        let logits = output.logits
        
        // Extract predicted token ID from logits.
        // logits에서 예측된 토큰 ID를 추출합니다.
        // logitsから予測されたトークンIDを抽出します。
        let nextTokenID = argmaxLogitsRow(
            logits,
            batch: 0,
            time: predictedTokenIDs.count - 1
        )
        
        // Check for end token (e.g., <EOS> token ID).
        // 종료 토큰(예: <EOS> 토큰 ID)을 확인합니다.
        // 終了トークン（例：<EOS>トークンID）を確認します。
        if nextTokenID == 3 {
            break
        }
        
        // Add the predicted token ID.
        // 예측된 토큰 ID를 추가합니다.
        // 予測されたトークンIDを追加します。
        predictedTokenIDs.append(nextTokenID)
        
        // Exit if the maximum sequence length is reached.
        // 최대 시퀀스 길이에 도달하면 종료합니다.
        // 最大シーケンス長に到達したら終了します。
        if predictedTokenIDs.count >= maxSeqLength {
            break
        }
    }
    
    // Decode the predicted token IDs back to text.
    // 예측된 토큰 ID를 다시 텍스트로 디코딩합니다.
    // 予測されたトークンIDをテキストにデコードします。
    let predictedText = tokenizer.decode(tokens: predictedTokenIDs)
    
    // Print the result.
    // 결과를 출력합니다.
    // 結果を出力します。
    return predictedText
}

// Perform prediction using Greedy search.
// Greedy search를 사용하여 예측을 수행합니다.
// Greedyサーチを使って予測を行います。
@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
func greedyPredictAsync(text: String, model: zenz_v1, tokenizer: Tokenizer) async -> String {
    // Encode the input text using the tokenizer.
    // 텍스트를 토크나이저를 사용하여 인코딩합니다.
    // トークナイザーを使って入力テキストをエンコードします。
    var inputIDs = tokenizer.encode(text: text)
    generationLog("[Stateless Greedy][Async] inputIDs: \(text) \(inputIDs)")
    
    // Set the maximum sequence length.
    // 최대 시퀀스 길이를 설정합니다.
    // 最大シーケンス長を設定します。
    let maxSeqLength = 128
    let batchSize = 1
    
    // Array to store predicted token IDs.
    // 예측된 토큰 ID를 저장할 배열입니다.
    // 予測されたトークンIDを保存する配列です。
    var predictedTokenIDs = inputIDs
    
    while true {
        // Create MLMultiArray for input.
        // 입력을 위한 MLMultiArray를 생성합니다.
        // 入力用のMLMultiArrayを作成します。
        let inputArray = try? MLMultiArray(shape: [NSNumber(value: batchSize), NSNumber(value: predictedTokenIDs.count)], dataType: .int32)
        for (index, token) in predictedTokenIDs.enumerated() {
            inputArray?[index] = NSNumber(value: token)
        }
        
        guard let inputArray else { return "" }
        
        // Create model input (only input_ids, no attention_mask).
        // 모델 입력을 생성합니다 (attention_mask 없이 input_ids만 전달).
        // モデル入力を作成します（attention_maskなしでinput_idsのみ渡します）。
        let input = zenz_v1Input(input_ids: inputArray)
        
        // Perform prediction.
        // 예측을 수행합니다.
        // 予測を行います。
        guard let output = try? await model.prediction(input: input) else { return "" }
        
        // Decode the output logits.
        // 출력 logits을 디코딩합니다.
        // 出力logitsをデコードします。
        let logits = output.logits
        
        // Extract predicted token ID from logits.
        // logits에서 예측된 토큰 ID를 추출합니다.
        // logitsから予測されたトークンIDを抽出します。
        let nextTokenID = argmaxLogitsRow(
            logits,
            batch: 0,
            time: predictedTokenIDs.count - 1
        )
        
        // Check for end token (e.g., <EOS> token ID).
        // 종료 토큰(예: <EOS> 토큰 ID)을 확인합니다.
        // 終了トークン（例：<EOS>トークンID）を確認します。
        if nextTokenID == 3 {
            break
        }
        
        // Add the predicted token ID.
        // 예측된 토큰 ID를 추가합니다.
        // 予測されたトークンIDを追加します。
        predictedTokenIDs.append(nextTokenID)
        
        // Exit if the maximum sequence length is reached.
        // 최대 시퀀스 길이에 도달하면 종료합니다.
        // 最大シーケンス長に到達したら終了します。
        if predictedTokenIDs.count >= maxSeqLength {
            break
        }
    }
    
    // Decode the predicted token IDs back to text.
    // 예측된 토큰 ID를 다시 텍스트로 디코딩합니다.
    // 予測されたトークンIDをテキストにデコードします。
    let predictedText = tokenizer.decode(tokens: predictedTokenIDs)
    
    // Print the result.
    // 결과를 출력합니다.
    // 結果を出力します。
    return predictedText
}

@available(macOS, deprecated: 10.14, message: "Use newer API greedyPredict(text:model:tokenizer) async")
@available(iOS, deprecated: 16.0, message: "Use newer API greedyPredict(text:model:tokenizer) async")
@available(tvOS, deprecated: 16.0, message: "Use newer API greedyPredict(text:model:tokenizer) async")
@available(watchOS, deprecated: 9.0, message: "Use newer API greedyPredict(text:model:tokenizer) async")
func greedyPredictDispatch(text: String, model: zenz_v1, tokenizer: Tokenizer, qos: DispatchQoS) async -> String {
    // Avoid capturing non-Sendable CoreML model/tokenizer directly in the @Sendable continuation
    let modelPtr = Unmanaged.passUnretained(model).toOpaque()

    let tokenizerObject = tokenizer as AnyObject
    let tokenizerPtr = Unmanaged.passUnretained(tokenizerObject).toOpaque()

    return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: qos.qosClass).async {
            let model = Unmanaged<zenz_v1>.fromOpaque(modelPtr).takeUnretainedValue()
            let tokenizerObject = Unmanaged<AnyObject>.fromOpaque(tokenizerPtr).takeUnretainedValue()
            guard let tokenizer = tokenizerObject as? Tokenizer else {
                fatalError("Stored tokenizer does not conform to Tokenizer")
            }

            let result = greedyPredict(text: text, model: model, tokenizer: tokenizer)
            continuation.resume(returning: result)
        }
    }
}

// Shared benchmark environment (model + tokenizer) initialized once and reused.
// 벤치마크 공통 환경 (모델 + 토크나이저)을 한 번만 초기화해서 재사용하기 위한 구조체.
// ベンチマーク共通の環境（モデル + トークナイザー）を一度だけ初期化して再利用するための構造体。
struct BenchmarkEnvironment {
    let model: zenz_v1
    let tokenizer: Tokenizer
}

// Load the model and tokenizer and build a BenchmarkEnvironment.
// 모델과 토크나이저를 로드하여 BenchmarkEnvironment를 구성합니다.
// モデルとトークナイザーを読み込んで BenchmarkEnvironment を構築します。
func makeBenchmarkEnvironment() async -> BenchmarkEnvironment {
    let model = loadModel()
    guard let model else { fatalError("model not found") }
    
    let tokenizer = await loadTokenizer()
    guard let tokenizer else { fatalError("tokenizer not found") }
    
    return BenchmarkEnvironment(model: model, tokenizer: tokenizer)
}

// For the given sentence (kana input), run both stateless and stateful benchmarks and print grouped rankings.
// 주어진 문장(카타카나 입력)에 대해 Stateless / Stateful 양쪽 벤치마크를 실행하고, 그룹별 랭킹을 출력합니다.
// 与えられた文（カタカナ入力）に対して Stateless / Stateful の両方のベンチマークを実行し、グループ別ランキングを出力します。
func runBenchmarksFor(groupTag: String, kanaInput: String, env: BenchmarkEnvironment) async {
    var benchmarks: [BenchmarkResult] = []
    let model = env.model
    let tokenizer = env.tokenizer
    
    // MARK: - Stateless (Async)
    if #available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *) {
        let startAsync = Date()
        let predictedSentenceAsync = await greedyPredictAsync(text: kanaInput, model: model, tokenizer: tokenizer)
        let durationAsync = Date().timeIntervalSince(startAsync)
        benchmarks.append(
            BenchmarkResult(
                label: "[Stateless Greedy][Async global]\(groupTag)",
                duration: durationAsync,
                input: kanaInput,
                output: predictedSentenceAsync
            )
        )
    } else {
        let startAsync = Date()
        let predictedSentenceAsync = await greedyPredictDispatch(text: kanaInput, model: model, tokenizer: tokenizer, qos: .userInitiated)
        let durationAsync = Date().timeIntervalSince(startAsync)
        benchmarks.append(
            BenchmarkResult(
                label: "[Stateless Greedy][Async dispatch]\(groupTag)",
                duration: durationAsync,
                input: kanaInput,
                output: predictedSentenceAsync
            )
        )
    }
    
    // MARK: - Stateless (Sync)
    do {
        let start = Date()
        let predictedSentence = greedyPredict(text: kanaInput, model: model, tokenizer: tokenizer)
        let durationSync = Date().timeIntervalSince(start)
        benchmarks.append(
            BenchmarkResult(
                label: "[Stateless Greedy][Sync main]\(groupTag)",
                duration: durationSync,
                input: kanaInput,
                output: predictedSentence
            )
        )
    }
    
    // MARK: - Stateful (Async & Sync)
    if #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) {
        let statefulModel = loadStatefulModel()
        guard let statefulModel else {
            print("[Stateful Greedy]\(groupTag) Skipped: stateful model not found")
            printBenchmarkRanking(for: groupTag, benchmarks: benchmarks)
            return
        }
        
        // Run the stateful model once before benchmarking so that compile/plan-build time is excluded.
        // Stateful 모델을 벤치마크 전에 한 번만 실행해서, 컴파일/플랜 빌드 시간을 측정에서 제외합니다.
        // ステートフルモデルをベンチマーク前に一度だけ実行し、コンパイル/プラン構築時間を測定から除外します。
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
            
            _ = try? await statefulModel.prediction(
                input: warmupInput,
                using: statefulModel.makeState()
            )
        } else {
            print("[Stateful Warmup]\(groupTag) Skipped: failed to allocate MLMultiArray.")
        }
        
        // Stateful Async
        do {
            let startAsync = Date()
            let predictedSentenceAsync = await greedyPredictStatefulAsync(text: kanaInput, model: statefulModel, tokenizer: tokenizer)
            let durationAsync = Date().timeIntervalSince(startAsync)
            benchmarks.append(
                BenchmarkResult(
                    label: "[Stateful Greedy][Async global]\(groupTag)",
                    duration: durationAsync,
                    input: kanaInput,
                    output: predictedSentenceAsync
                )
            )
        }
        
        // Stateful Sync
        do {
            let start = Date()
            let predictedSentence = greedyPredictStateful(text: kanaInput, model: statefulModel, tokenizer: tokenizer)
            let durationStateful = Date().timeIntervalSince(start)
            benchmarks.append(
                BenchmarkResult(
                    label: "[Stateful Greedy][Sync main]\(groupTag)",
                    duration: durationStateful,
                    input: kanaInput,
                    output: predictedSentence
                )
            )
        }
    } else {
        print("[Stateful Greedy]\(groupTag) Skipped: stateful model not available on this OS.")
    }
    
    // Print benchmark ranking for this group (sentence).
    // 이 그룹(문장)에 대한 벤치마크 랭킹을 출력합니다.
    // このグループ（文）に対するベンチマークランキングを出力します。
    printBenchmarkRanking(for: groupTag, benchmarks: benchmarks)
}
