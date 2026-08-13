#!/usr/bin/env bash
# Gate A + Phase 2 host tests (protocol + adb_client). No OHOS device required.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo not found; install Rust 1.88+ from https://rustup.rs" >&2
  exit 1
fi

export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/native/target}"
export CARGO_HOME="${CARGO_HOME:-$ROOT/native/.cargo-home}"
mkdir -p "$CARGO_HOME"

echo "==> rustc: $(rustc --version)"
echo "==> cargo test -p easycontrol-protocol -p easycontrol-adb-client"
cargo test --manifest-path "$ROOT/native/Cargo.toml" \
  -p easycontrol-protocol \
  -p easycontrol-adb-client \
  -- --nocapture
