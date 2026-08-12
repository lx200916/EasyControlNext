#!/usr/bin/env bash
# Gate B helper: build adb_core for aarch64-unknown-linux-ohos.
# Prefers `ohrs` when installed; falls back to cargo + OHOS_NDK_HOME linker config.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE="$ROOT/native"
TARGET="${OHOS_TARGET:-aarch64-unknown-linux-ohos}"
NDK_HOME="${OHOS_NDK_HOME:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony}"

# Prefer workspace-local cargo home/target so CI does not require mutating ~/.cargo.
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$NATIVE/target}"
export CARGO_HOME="${CARGO_HOME:-$NATIVE/.cargo-home}"
mkdir -p "$CARGO_HOME"

if [[ ! -d "$NDK_HOME" ]]; then
  echo "error: OHOS_NDK_HOME not found: $NDK_HOME" >&2
  echo "Set OHOS_NDK_HOME to DevEco's openharmony SDK root (contains native/)." >&2
  exit 1
fi

export OHOS_NDK_HOME="$NDK_HOME"

if ! rustup target list --installed | grep -qx "$TARGET"; then
  echo "error: Rust target $TARGET not installed." >&2
  echo "Run: rustup target add $TARGET" >&2
  exit 1
fi

cd "$NATIVE"

if command -v ohrs >/dev/null 2>&1; then
  echo "==> ohrs build --arch aarch (package adb_core)"
  # ohrs discovers packages depending on napi-derive-ohos
  ohrs build --arch aarch -p adb_core
  echo "==> done (see native/adb_core/dist or ohrs output paths)"
  exit 0
fi

echo "warn: ohrs not installed; using cargo fallback" >&2
echo "hint: cargo install ohrs --locked" >&2

LLVM_BIN="$NDK_HOME/native/llvm/bin"
SYSROOT="$NDK_HOME/native/sysroot"
if [[ ! -x "$LLVM_BIN/clang" ]]; then
  echo "error: clang not found under $LLVM_BIN" >&2
  exit 1
fi

# ring / cc-rs need the OHOS clang + sysroot (host `cc` lacks assert.h for this target).
export CC_aarch64_unknown_linux_ohos="$LLVM_BIN/clang"
export AR_aarch64_unknown_linux_ohos="$LLVM_BIN/llvm-ar"
export CFLAGS_aarch64_unknown_linux_ohos="--target=$TARGET --sysroot=$SYSROOT"
export CXXFLAGS_aarch64_unknown_linux_ohos="--target=$TARGET --sysroot=$SYSROOT"

echo "==> cargo build -p adb_core --release --target $TARGET"
cargo build --manifest-path "$NATIVE/Cargo.toml" -p adb_core --release --target "$TARGET" \
  --config "target.$TARGET.linker=\"$LLVM_BIN/clang\"" \
  --config "target.$TARGET.ar=\"$LLVM_BIN/llvm-ar\"" \
  --config "target.$TARGET.rustflags=[\"-C\",\"link-arg=--target=$TARGET\",\"-C\",\"link-arg=--sysroot=$SYSROOT\"]"

OUT="$NATIVE/target/$TARGET/release/libadb_core.so"
if [[ -f "$OUT" ]]; then
  DEST_DIR="$ROOT/entry/libs/arm64-v8a"
  mkdir -p "$DEST_DIR"
  cp -f "$OUT" "$DEST_DIR/libadb_core.so"
  echo "==> copied $OUT -> $DEST_DIR/libadb_core.so"
else
  echo "error: expected artifact missing: $OUT" >&2
  exit 1
fi
