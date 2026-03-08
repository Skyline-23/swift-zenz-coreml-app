# 第2回 HF Stateful ベンチマーク計画 / 2회차 HF Stateful 벤치마크 계획 / Round 2 HF Stateful Benchmark Plan

This round replaces the old GitHub-hosted artifact assumption with the Hugging Face model repo:

- Model repo: [Skyline23/zenz-coreml](https://huggingface.co/Skyline23/zenz-coreml)
- Manifest: [hf_manifest.json](https://huggingface.co/Skyline23/zenz-coreml/blob/main/hf_manifest.json)
- Base model: [Miwa-Keita/zenz-v3.1-small](https://huggingface.co/Miwa-Keita/zenz-v3.1-small)

## Goal

- Measure whether the HF single-stateful model improves real-device generation latency over the legacy bundled setup.
- Compare FP16 and 8-bit variants separately.
- Keep the existing Round 1 prompt families so longitudinal comparisons remain possible.
- Download tokenizer and Core ML artifacts through `swift-transformers` (`AutoTokenizer` + `Hub`) instead of relying on a git submodule.
- Allow the Xcode build phase to prefill `Resources/` from the Hugging Face cache when available, while keeping runtime fetch as the fallback path.

## Artifact Matrix

| Model | FP16 | 8-bit |
|---|---|---|
| Stateless baseline | `Artifacts/stateless/zenz-stateless-fp16.mlpackage` | `Artifacts/stateless/zenz-stateless-8bit.mlpackage` |
| Stateful cached | `Artifacts/stateful/zenz-stateful-fp16.mlpackage` | `Artifacts/stateful/zenz-stateful-8bit.mlpackage` |

## Metrics To Record

| Metric | Description |
|---|---|
| Cold prompt latency | First prompt call after model load |
| Warm prompt latency | Prompt call after warmup |
| First-token latency | End-to-end from prompt submission through first generated token |
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

| Device | OS | Stateless FP16 | Stateless 8-bit | Stateful FP16 | Stateful 8-bit | Notes |
|---|---|---:|---:|---:|---:|---|
| Example: iPhone 12 | iOS xx.x | TBD | TBD | TBD | TBD | |

### Prompt Latency by Prompt Bucket

| Bucket | Tokens | Stateful FP16 cold (s) | Stateful FP16 warm (s) | Stateful 8-bit cold (s) | Stateful 8-bit warm (s) |
|---|---:|---:|---:|---:|---:|
| Short | TBD | TBD | TBD | TBD | TBD |
| Medium | TBD | TBD | TBD | TBD | TBD |
| Long | TBD | TBD | TBD | TBD | TBD |

### Decode Latency by Prompt Bucket

| Bucket | Tokens generated | Stateful FP16 first token (s) | Stateful FP16 steady token (s) | Stateful 8-bit first token (s) | Stateful 8-bit steady token (s) |
|---|---:|---:|---:|---:|---:|
| Short | TBD | TBD | TBD | TBD | TBD |
| Medium | TBD | TBD | TBD | TBD | TBD |
| Long | TBD | TBD | TBD | TBD | TBD |

### Observations

- Which device benefits most from the single stateful cache path?
- Does 8-bit help latency, memory, or only package size?
- Is the single-model cached loop good enough for keyboard-like incremental usage?
- Does the old Round 1 “stateless sync” winner remain competitive against the HF stateful model?
