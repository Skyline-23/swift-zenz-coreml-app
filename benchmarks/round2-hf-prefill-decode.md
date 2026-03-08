# 第2回 HF Prefill/Decode ベンチマーク計画 / 2회차 HF Prefill/Decode 벤치마크 계획 / Round 2 HF Prefill/Decode Benchmark Plan

This round replaces the old GitHub-hosted artifact assumption with the Hugging Face model repo:

- Model repo: [Skyline23/zenz-coreml](https://huggingface.co/Skyline23/zenz-coreml)
- Manifest: [hf_manifest.json](https://huggingface.co/Skyline23/zenz-coreml/blob/main/hf_manifest.json)
- Base model: [Miwa-Keita/zenz-v3.1-small](https://huggingface.co/Miwa-Keita/zenz-v3.1-small)

## Goal

- Measure whether the new `prefill + decode` split improves real-device generation latency over the legacy single-model setup.
- Compare FP16 and 8-bit variants separately for both stages.
- Keep the existing Round 1 prompt families so longitudinal comparisons remain possible.
- Download tokenizer and Core ML artifacts at runtime through `swift-transformers` (`AutoTokenizer` + `Hub`) instead of relying on a git submodule or a manual sync script.
- Allow the Xcode build phase to prefill `Resources/` from the Hugging Face cache when available, while keeping runtime fetch as the fallback path.

## Artifact Matrix

| Stage | FP16 | 8-bit |
|---|---|---|
| Prefill | `Artifacts/prefill/zenz-prefill-fp16.mlpackage` | `Artifacts/prefill/zenz-prefill-8bit.mlpackage` |
| Decode | `Artifacts/decode/zenz-stateful-decode-fp16.mlpackage` | `Artifacts/decode/zenz-stateful-decode-8bit.mlpackage` |

## Metrics To Record

| Metric | Description |
|---|---|
| Cold prefill latency | First prompt-chunk call after model load |
| Warm prefill latency | Prompt-chunk call after warmup |
| First-token latency | End-to-end from prompt submission through first decode step |
| Steady-state decode latency | Average time per generated token after the first token |
| Tokens/sec | `generated_tokens / total_decode_time` |
| Peak memory note | Manual note from Xcode / Instruments if memory behavior differs |

## Prompt Buckets

Use the existing Round 1 prompts, grouped the same way:

- Short: `ニホンゴ`, `ゲンキデスカ`, `オハヨウゴザイマス`
- Medium: `キョウハトテモアツイデスネ`, `アシタノゴゴサンジニエキデアイマショウ`
- Long: `LongJP`, `LongJP2`, `LongJP3`, `LongJP4`, `LongJPKeyboard`

## Reporting Template

### Device Summary

| Device | OS | Prefill FP16 | Prefill 8-bit | Decode FP16 | Decode 8-bit | Notes |
|---|---|---:|---:|---:|---:|---|
| Example: iPhone 12 | iOS xx.x | TBD | TBD | TBD | TBD | |

### Prefill Latency by Prompt Bucket

| Bucket | Tokens | FP16 cold (s) | FP16 warm (s) | 8-bit cold (s) | 8-bit warm (s) |
|---|---:|---:|---:|---:|---:|
| Short | TBD | TBD | TBD | TBD | TBD |
| Medium | TBD | TBD | TBD | TBD | TBD |
| Long | TBD | TBD | TBD | TBD | TBD |

### Decode Latency by Prompt Bucket

| Bucket | Tokens generated | FP16 first token (s) | FP16 steady token (s) | 8-bit first token (s) | 8-bit steady token (s) |
|---|---:|---:|---:|---:|---:|
| Short | TBD | TBD | TBD | TBD | TBD |
| Medium | TBD | TBD | TBD | TBD | TBD |
| Long | TBD | TBD | TBD | TBD | TBD |

### Observations

- Which device benefits most from the split prefill/decode pipeline?
- Does 8-bit help latency, memory, or only package size?
- Is warm prefill fast enough to matter for keyboard-like incremental usage?
- Does the old Round 1 “stateless sync” winner remain competitive against the new decode model?
