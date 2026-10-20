#!/bin/sh
# Builds the opaque-bridge client library with cargo and copies the static library to the build directory.
#   build-opaque.sh <crate dir> <output file> <target dir>
set -e

crate_dir="$1"
output="$2"
target_dir="$3"

cargo build --release --offline --no-default-features --features client \
    --manifest-path "$crate_dir/Cargo.toml" --target-dir "$target_dir"

cp "$target_dir/release/libopaque_bridge.a" "$output"
