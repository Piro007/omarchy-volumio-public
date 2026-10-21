#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
source_dir=$PWD
plugin_id=delormous.volumio
destination="$HOME/.config/omarchy/plugins/$plugin_id"
if [[ -e "$destination" && "$source_dir" != "$destination" ]]; then
  echo "Already installed: use omarchy plugin update $plugin_id, then run the installed scripts/build.sh." >&2
  exit 1
fi
omarchy plugin validate .
if [[ "$source_dir" != "$destination" ]]; then
  if [[ -n $(git status --porcelain --untracked-files=normal) ]]; then
    echo "Commit source changes before installing; Omarchy clones committed files." >&2
    exit 1
  fi
  omarchy plugin add "$source_dir" --yes
fi
# Build the copy Omarchy will actually load, before enabling the plugin.
bash "$destination/scripts/build.sh"
omarchy-shell shell rescanPlugins
# The manifest selects the initial section. Preserve an existing placement.
omarchy plugin enable "$plugin_id"
echo "Volumio installed and enabled. Click its widget to configure the player."
