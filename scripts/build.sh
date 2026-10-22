#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
host=$(rustc -vV | sed -n 's/^host: //p')
# Always build the native executable in this checkout, even if Cargo target
# directory/target overrides are set in the invoking terminal.
cargo build --release --locked --target "$host" --target-dir "$PWD/target"
mkdir -p bin
# Atomic replacement also works while the previous executable is running.
install -m755 "target/$host/release/omarchy-volumio" bin/omarchy-volumio.new
mv bin/omarchy-volumio.new bin/omarchy-volumio
