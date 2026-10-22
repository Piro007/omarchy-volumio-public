#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
bash scripts/build.sh
version=$(python3 -c 'import json; print(json.load(open("manifest.json"))["version"])')
machine=$(rustc -vV | sed -n 's/^host: //p')
name="omarchy-volumio-$version-$machine"
mkdir -p dist
stage=$(mktemp -d "$PWD/dist/.package.XXXXXX")
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/$name/bin"
cp manifest.json Service.qml BarWidget.qml ControlPanel.qml AlbumBrowser.qml PlaylistBrowser.qml Oscilloscope.qml Model.js README.md LICENSE "$stage/$name/"
cp bin/omarchy-volumio "$stage/$name/bin/"
cp -r docs "$stage/$name/"
tar -C "$stage" -czf "dist/$name.tar.gz" "$name"
(cd dist && sha256sum "$name.tar.gz" > "$name.tar.gz.sha256")
echo "dist/$name.tar.gz"
