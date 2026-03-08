# Swift-zenz-CoreML-APP

🇯🇵 Swiftで [Skyline23/zenz-coreml](https://huggingface.co/Skyline23/zenz-coreml) の Core ML アーティファクトを扱い、実機で推論性能をベンチマークするためのサンプルリポジトリです。  
🇰🇷 Swift에서 [Skyline23/zenz-coreml](https://huggingface.co/Skyline23/zenz-coreml) Hugging Face 리포지토리의 Core ML 아티팩트를 다루고, 실기기에서 추론 성능을 벤치마크하기 위한 샘플 리포지토리입니다.  
🇺🇸 Sample repository for working with the Core ML artifacts published at [Skyline23/zenz-coreml](https://huggingface.co/Skyline23/zenz-coreml) and benchmarking them on real iOS devices.  

## Artifact Source

- Hugging Face model repo: [Skyline23/zenz-coreml](https://huggingface.co/Skyline23/zenz-coreml)
- Manifest: [hf_manifest.json](https://huggingface.co/Skyline23/zenz-coreml/blob/main/hf_manifest.json)
- Stateless FP16: [Artifacts/stateless/zenz-stateless-fp16.mlpackage](https://huggingface.co/Skyline23/zenz-coreml/tree/main/Artifacts/stateless/zenz-stateless-fp16.mlpackage)
- Stateless 8-bit: [Artifacts/stateless/zenz-stateless-8bit.mlpackage](https://huggingface.co/Skyline23/zenz-coreml/tree/main/Artifacts/stateless/zenz-stateless-8bit.mlpackage)
- Stateful FP16: [Artifacts/stateful/zenz-stateful-fp16.mlpackage](https://huggingface.co/Skyline23/zenz-coreml/tree/main/Artifacts/stateful/zenz-stateful-fp16.mlpackage)
- Stateful 8-bit: [Artifacts/stateful/zenz-stateful-8bit.mlpackage](https://huggingface.co/Skyline23/zenz-coreml/tree/main/Artifacts/stateful/zenz-stateful-8bit.mlpackage)

## Runtime Fetch Direction

The app is being restructured away from the old `Resources` submodule flow.

- Tokenizers should come from `AutoTokenizer.from(pretrained: "Skyline23/zenz-coreml")` when local assets are unavailable.
- Core ML artifacts should be downloaded through the `Hub` module from `swift-transformers`, using the Hugging Face repo above as the single source of truth.
- A build-phase bootstrap now tries to hydrate `Resources/Artifacts`, `Resources/tokenizer`, and `Resources/hf_manifest.json` from the Hugging Face cache before each build.
- If cached resources already exist, the bootstrap skips network work.
- If the network is unavailable or the download fails, the build still continues and the app falls back to runtime error messaging when models are missing.
- Round 1 benchmark numbers remain valid as legacy bundled-model results; new benchmark rounds should measure the HF-backed single-stateful pipeline separately.

## ベンチマーク (Core ML greedy decoding) / 벤치마크 (Core ML greedy decoding) / Benchmarks (Core ML greedy decoding)

Detailed benchmark material is organized as:

- Legacy Round 1 results: [iPhone 12 details](benchmarks/round1-iPhone12.md)
- Legacy Round 1 results: [iPhone Air details](benchmarks/round1-iPhoneAir.md)
- New HF-backed benchmark plan: [Round 2 single-stateful plan](benchmarks/round2-hf-prefill-decode.md)
