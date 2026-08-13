#!/usr/bin/env bash
# Build adb_core for aarch64-unknown-linux-ohos and stage into entry/libs/.
#
# DevEco / hvigor Assemble does NOT compile this Rust cdylib. It only packages
# the prebuilt .so from entry/libs/arm64-v8a/ via default@ProcessLibs.
# entry/hvigorfile.ts runs this script before ProcessLibs so Assemble gets a
# fresh .so when native sources change.
#
# Prefers `ohrs` when installed; falls back to cargo + OHOS_NDK_HOME linker.
#
# Usage:
#   ./scripts/build_native_ohos.sh           # rebuild (cargo/ohrs decide incremental)
#   ./scripts/build_native_ohos.sh --force   # always rebuild
#   ./scripts/build_native_ohos.sh --if-needed  # skip when staged .so is newer than sources
#   SKIP_NATIVE_OHOS=1 ./scripts/build_native_ohos.sh  # no-op (Assemble escape hatch)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE="$ROOT/native"
TARGET="${OHOS_TARGET:-aarch64-unknown-linux-ohos}"
NDK_HOME="${OHOS_NDK_HOME:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony}"
DEST_DIR="$ROOT/entry/libs/arm64-v8a"
DEST_SO="$DEST_DIR/libadb_core.so"

FORCE=0
IF_NEEDED=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --if-needed) IF_NEEDED=1 ;;
    -h|--help)
      sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "error: unknown arg: $arg (use --force | --if-needed)" >&2
      exit 2
      ;;
  esac
done

if [[ "${SKIP_NATIVE_OHOS:-}" == "1" || "${SKIP_NATIVE_OHOS:-}" == "true" ]]; then
  echo "==> SKIP_NATIVE_OHOS set; not rebuilding libadb_core.so"
  if [[ ! -f "$DEST_SO" ]]; then
    echo "error: $DEST_SO missing; unset SKIP_NATIVE_OHOS or run without skip" >&2
    exit 1
  fi
  exit 0
fi

# Prefer workspace-local cargo home/target so CI does not require mutating ~/.cargo.
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$NATIVE/target}"
export CARGO_HOME="${CARGO_HOME:-$NATIVE/.cargo-home}"
mkdir -p "$CARGO_HOME"

stage_so() {
  local src="$1"
  if [[ ! -f "$src" ]]; then
    echo "error: expected artifact missing: $src" >&2
    exit 1
  fi
  mkdir -p "$DEST_DIR"
  cp -f "$src" "$DEST_SO"
  # Bust hvigor DoNativeStrip incremental cache when content changes but size matches.
  touch "$DEST_SO"
  echo "==> staged $src -> $DEST_SO"
  ls -la "$DEST_SO"
}

find_ohrs_so() {
  # ohrs layout varies by version; prefer package dist, then generic searches.
  local candidates=(
    "$NATIVE/adb_core/dist/arm64-v8a/libadb_core.so"
    "$NATIVE/adb_core/dist/$TARGET/release/libadb_core.so"
    "$NATIVE/adb_core/dist/libadb_core.so"
    "$CARGO_TARGET_DIR/$TARGET/release/libadb_core.so"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -f "$c" ]]; then
      echo "$c"
      return 0
    fi
  done
  # Last resort: newest libadb_core.so under adb_core/dist
  local found
  found="$(find "$NATIVE/adb_core/dist" -name 'libadb_core.so' -type f 2>/dev/null | head -n 1 || true)"
  if [[ -n "$found" ]]; then
    echo "$found"
    return 0
  fi
  return 1
}

sources_newer_than_staged() {
  [[ ! -f "$DEST_SO" ]] && return 0
  # Any Rust/Cargo change under native/ newer than staged .so → rebuild.
  local newer
  newer="$(find "$NATIVE" \
    \( -path "$NATIVE/target" -o -path "$NATIVE/.cargo-home" -o -path '*/dist' \) -prune -o \
    \( -name '*.rs' -o -name 'Cargo.toml' -o -name 'Cargo.lock' -o -name 'build.rs' \) -type f \
    -newer "$DEST_SO" -print -quit 2>/dev/null || true)"
  [[ -n "$newer" ]]
}

if [[ "$IF_NEEDED" -eq 1 && "$FORCE" -eq 0 ]]; then
  if ! sources_newer_than_staged; then
    echo "==> staged libadb_core.so is up to date ($DEST_SO); skip rebuild"
    ls -la "$DEST_SO"
    exit 0
  fi
  echo "==> native sources newer than staged .so; rebuilding"
fi

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
  ohrs build --arch aarch -p adb_core
  OHRS_SO="$(find_ohrs_so)" || {
    echo "error: ohrs finished but libadb_core.so not found under native/adb_core/dist or cargo target" >&2
    exit 1
  }
  stage_so "$OHRS_SO"
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

stage_so "$CARGO_TARGET_DIR/$TARGET/release/libadb_core.so"
