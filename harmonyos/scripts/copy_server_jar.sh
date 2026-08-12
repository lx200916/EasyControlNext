#!/usr/bin/env bash
# Copy the Android Gradle server artifact into HarmonyOS rawfile (byte-for-byte).
# Does not build the server; run Gradle in ../easycontrolnext first.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_ROOT="$(cd "$ROOT/../easycontrolnext" && pwd)"
DEST_DIR="$ROOT/entry/src/main/resources/rawfile"
DEST_JAR="$DEST_DIR/easycontrolnext_server.jar"

# Common Gradle output candidates (first existing wins).
CANDIDATES=(
  "$ANDROID_ROOT/server/build/libs/easycontrolnext_server.jar"
  "$ANDROID_ROOT/server/build/outputs/jar/easycontrolnext_server.jar"
  "$ANDROID_ROOT/app/src/main/res/raw/easycontrolnext_server.jar"
  "$ANDROID_ROOT/app/src/main/res/raw/easycontrolnext_server"
)

SRC=""
for c in "${CANDIDATES[@]}"; do
  if [[ -f "$c" ]]; then
    SRC="$c"
    break
  fi
done

if [[ -z "$SRC" ]]; then
  echo "error: server jar not found. Build the Android server module first, e.g.:" >&2
  echo "  (cd \"$ANDROID_ROOT\" && ./gradlew :server:assemble)" >&2
  echo "Looked for:" >&2
  printf '  %s\n' "${CANDIDATES[@]}" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
cp -f "$SRC" "$DEST_JAR"

# Record provenance next to the jar (safe to commit or regenerate).
HASH="$(shasum -a 256 "$DEST_JAR" | awk '{print $1}')"
SIZE="$(wc -c <"$DEST_JAR" | tr -d ' ')"
cat >"$DEST_DIR/easycontrolnext_server.jar.sha256" <<EOF
sha256=$HASH
size=$SIZE
source=$SRC
copied_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

echo "==> copied $SRC"
echo "    -> $DEST_JAR"
echo "    sha256=$HASH size=$SIZE"
echo "note: prefer regenerating via this script over committing large binaries when possible"
