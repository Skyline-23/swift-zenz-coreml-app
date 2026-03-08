# Swift-zenz-CoreML-APP

🇯🇵 Swiftで [Skyline23/zenz-coreml](https://huggingface.co/Skyline23/zenz-coreml) の Core ML アーティファクトをビルド時に取り込み、実機で推論性能をベンチマークするためのサンプルリポジトリです。  
🇰🇷 Swift에서 [Skyline23/zenz-coreml](https://huggingface.co/Skyline23/zenz-coreml) Hugging Face 리포지토리의 Core ML 아티팩트를 빌드 시점에 받아와 번들에 넣고, 실기기에서 추론 성능을 벤치마크하기 위한 샘플 리포지토리입니다.  
🇺🇸 Sample repository for pulling the Core ML artifacts from [Skyline23/zenz-coreml](https://huggingface.co/Skyline23/zenz-coreml) during the build and benchmarking them on real iOS devices.  

## Artifact Source

- Hugging Face model repo: [Skyline23/zenz-coreml](https://huggingface.co/Skyline23/zenz-coreml)
- Manifest: [hf_manifest.json](https://huggingface.co/Skyline23/zenz-coreml/blob/main/hf_manifest.json)
- Stateless FP16: [Artifacts/stateless/zenz-stateless-fp16.mlpackage](https://huggingface.co/Skyline23/zenz-coreml/tree/main/Artifacts/stateless/zenz-stateless-fp16.mlpackage)
- Stateless 8-bit: [Artifacts/stateless/zenz-stateless-8bit.mlpackage](https://huggingface.co/Skyline23/zenz-coreml/tree/main/Artifacts/stateless/zenz-stateless-8bit.mlpackage)
- Stateful: [Artifacts/stateful/zenz-stateful-fp16.mlpackage](https://huggingface.co/Skyline23/zenz-coreml/tree/main/Artifacts/stateful/zenz-stateful-fp16.mlpackage)

## Build-Time Bootstrap

The app no longer fetches model artifacts at runtime.

- The Xcode build phase hydrates `Resources/Artifacts`, `Resources/tokenizer`, and `Resources/hf_manifest.json` before compilation.
- If those files already exist, the bootstrap skips the network step.
- If the network is unavailable or the download fails, the build still continues.
- At runtime the app reads only from bundled `Resources`; if the artifacts are missing, the app reports that instead of trying to download them itself.
- Round 1 benchmark numbers remain valid as legacy bundled-model results; new benchmark rounds measure the single-stateful pipeline staged during the build.

## ベンチマーク (Core ML greedy decoding) / 벤치마크 (Core ML greedy decoding) / Benchmarks (Core ML greedy decoding)

Detailed benchmark material is organized as:

- Legacy Round 1 results: [iPhone 12 details](benchmarks/round1-iPhone12.md)
- Legacy Round 1 results: [iPhone Air details](benchmarks/round1-iPhoneAir.md)
- New HF-backed benchmark plan: [Round 2 single-stateful plan](benchmarks/round2-hf-prefill-decode.md)
