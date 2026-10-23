#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
python3 scripts/check_versions.py
host=$(rustc -vV | sed -n 's/^host: //p')
cargo_args=(--locked --target "$host" --target-dir "$PWD/target")
# Test the binary built here, regardless of caller Cargo or binary overrides.
export VOLUMIO_BINARY="$PWD/target/$host/debug/omarchy-volumio"
cargo fmt --check
cargo clippy "${cargo_args[@]}" --all-targets -- -D warnings
cargo test "${cargo_args[@]}"
cargo build "${cargo_args[@]}"
python3 -m unittest discover -s tests -p 'test_support.py' -v
python3 tests/test_bridge.py
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_CONTROLS_STYLE=Basic \
  /usr/lib/qt6/bin/qmltestrunner -import tests/qml-imports -input tests/qml
omarchy plugin validate .
imports=$(mktemp -d)
trap 'rm -rf "$imports"' EXIT
ln -s "${OMARCHY_PATH:-/usr/share/omarchy}/shell" "$imports/qs"
# Shell facades and Style.font expose dynamic QObject members. Suppress only
# that category, while making syntax/import/type warnings fail the check.
/usr/lib/qt6/bin/qmllint --max-warnings 0 --missing-property disable \
  -I "$imports" Service.qml BarWidget.qml ControlPanel.qml AlbumBrowser.qml PlaylistBrowser.qml Oscilloscope.qml PlaybackTiming.qml ControlViewport.qml
