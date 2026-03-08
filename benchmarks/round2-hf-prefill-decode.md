# 第2回 HF Stateful ベンチマーク計画 / 2회차 HF Stateful 벤치마크 계획 / Round 2 HF Stateful Benchmark Plan

This round replaces the old GitHub-hosted artifact assumption with the Hugging Face model repo:

- Model repo: [Skyline23/zenz-coreml](https://huggingface.co/Skyline23/zenz-coreml)
- Manifest: [hf_manifest.json](https://huggingface.co/Skyline23/zenz-coreml/blob/main/hf_manifest.json)
- Base model: [Miwa-Keita/zenz-v3.1-small](https://huggingface.co/Miwa-Keita/zenz-v3.1-small)

## Goal

- Measure whether the HF single-stateful model improves real-device generation latency over the legacy bundled setup.
- Compare the single HF stateful path against the stateless FP16 and 8-bit baselines.
- Keep the existing Round 1 prompt families so longitudinal comparisons remain possible.
- Stage tokenizer and Core ML artifacts into `Resources/` during the Xcode build instead of relying on a git submodule.
- Keep runtime behavior bundle-only: if the staged files are missing, the app should report that state rather than downloading on launch.

## Artifact Matrix

| Model | Artifact |
|---|---|
| Stateless baseline (FP16) | `Artifacts/stateless/zenz-stateless-fp16.mlpackage` |
| Stateless baseline (8-bit) | `Artifacts/stateless/zenz-stateless-8bit.mlpackage` |
| Stateful cached | `Artifacts/stateful/zenz-stateful-fp16.mlpackage` |

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

| Device | OS | Stateless FP16 | Stateless 8-bit | Stateful | Notes |
|---|---|---:|---:|---:|---|
| Example: iPhone 12 | iOS xx.x | TBD | TBD | TBD | |

### Prompt Latency by Prompt Bucket

| Bucket | Tokens | Stateful cold (s) | Stateful warm (s) |
|---|---:|---:|---:|
| Short | TBD | TBD | TBD |
| Medium | TBD | TBD | TBD |
| Long | TBD | TBD | TBD |

### Decode Latency by Prompt Bucket

| Bucket | Tokens generated | Stateful first token (s) | Stateful steady token (s) |
|---|---:|---:|---:|
| Short | TBD | TBD | TBD |
| Medium | TBD | TBD | TBD |
| Long | TBD | TBD | TBD |

### Observations

- Which device benefits most from the single stateful cache path?
- Does 8-bit help latency, memory, or only package size?
- Is the single-model cached loop good enough for keyboard-like incremental usage?
- Does the old Round 1 “stateless sync” winner remain competitive against the single HF stateful model?
