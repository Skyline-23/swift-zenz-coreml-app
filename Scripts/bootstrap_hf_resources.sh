#!/bin/sh
set -u

RESOURCE_DIR="${SRCROOT}/swift-zenz-coreml-app/Resources"
CACHE_DIR="${HOME}/Library/Caches/zenz-coreml-hf"
export RESOURCE_DIR
export CACHE_DIR

if [ "${SKIP_HF_RESOURCE_BOOTSTRAP:-0}" = "1" ]; then
  echo "Skipping HF resource bootstrap because SKIP_HF_RESOURCE_BOOTSTRAP=1"
  exit 0
fi

mkdir -p "${RESOURCE_DIR}"
mkdir -p "${CACHE_DIR}"

PYTHON_CANDIDATES="python3 python /opt/homebrew/bin/python3 /opt/homebrew/bin/python"
PYTHON_BIN=""

for candidate in $PYTHON_CANDIDATES; do
  if command -v "$candidate" >/dev/null 2>&1; then
    if "$candidate" - <<'PY' >/dev/null 2>&1
import huggingface_hub
PY
    then
      PYTHON_BIN="$candidate"
      break
    fi
  fi
done

if [ -z "$PYTHON_BIN" ]; then
  echo "warning: no Python interpreter with huggingface_hub found, skipping HF bootstrap"
  exit 0
fi

"$PYTHON_BIN" - <<'PY'
import os
import sys
from pathlib import Path

resource_dir = Path(os.environ["RESOURCE_DIR"])
cache_dir = Path(os.environ["CACHE_DIR"])
required = [
    resource_dir / "hf_manifest.json",
    resource_dir / "Artifacts" / "prefill" / "zenz-prefill-fp16.mlpackage",
    resource_dir / "Artifacts" / "decode" / "zenz-stateful-decode-fp16.mlpackage",
    resource_dir / "tokenizer" / "tokenizer.json",
]

if all(path.exists() for path in required):
    print("HF resources already present in Resources, skipping download.")
    sys.exit(0)

try:
    from huggingface_hub import snapshot_download
except Exception as exc:
    print(f"warning: huggingface_hub unavailable, skipping HF bootstrap: {exc}")
    sys.exit(0)

try:
    snapshot_download(
        repo_id="Skyline23/zenz-coreml",
        repo_type="model",
        local_dir=str(resource_dir),
        cache_dir=str(cache_dir),
        local_dir_use_symlinks=False,
        allow_patterns=[
            "Artifacts/*",
            "tokenizer/*",
            "hf_manifest.json",
        ],
    )
    print(f"HF resources are ready under {resource_dir}")
except Exception as exc:
    print(f"warning: failed to refresh HF resources, continuing build without them: {exc}")
    sys.exit(0)
PY
