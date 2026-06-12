#!/usr/bin/env bash
#
# Build the echoes-dungeon GDExtension for every shipping platform and stage the
# artifacts under dungeon/bin/<platform>/, where dungeon.gdextension expects them.
#
# Run from anywhere:  dungeon/build_all.sh
#
# Cross-compiling from macOS works because the project pins a vendored godot-bindings
# (see vendor/godot-bindings) that selects the prebuilt GDExtension interface bindings by
# the *target* OS instead of the host — upstream 0.4.5 picks by host and bakes in macOS
# bindings, which breaks Windows/Linux builds.
#
# Toolchain prerequisites (macOS host):
#   Windows : brew install mingw-w64   + rustup target add x86_64-pc-windows-gnu
#   Linux   : brew install cargo-zigbuild zig  (used as a self-contained cross linker)
#             + rustup target add x86_64-unknown-linux-gnu
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

BIN="$DIR/bin"
mkdir -p "$BIN/macos" "$BIN/windows" "$BIN/linux"

PROFILE_DIR="release"
COMMON_ARGS=(--release --features bridge)

echo "==> macOS (native)"
cargo build "${COMMON_ARGS[@]}"
cp "target/$PROFILE_DIR/libechoes_dungeon.dylib" "$BIN/macos/"

echo "==> Windows x86_64 (mingw cross)"
cargo build "${COMMON_ARGS[@]}" --target x86_64-pc-windows-gnu
cp "target/x86_64-pc-windows-gnu/$PROFILE_DIR/echoes_dungeon.dll" "$BIN/windows/"

echo "==> Linux x86_64"
if command -v cargo-zigbuild >/dev/null 2>&1; then
    cargo zigbuild "${COMMON_ARGS[@]}" --target x86_64-unknown-linux-gnu
    cp "target/x86_64-unknown-linux-gnu/$PROFILE_DIR/libechoes_dungeon.so" "$BIN/linux/"
else
    echo "   SKIPPED: cargo-zigbuild not found."
    echo "   Install with: brew install cargo-zigbuild zig && rustup target add x86_64-unknown-linux-gnu"
fi

echo
echo "==> Staged libraries:"
find "$BIN" -type f -exec ls -lah {} \;
echo
echo "Done. Restart Godot to reload the GDExtension."
