# Development and testing

## Build

Rust 1.99.1 is pinned in `rust-toolchain.toml`; `Cargo.lock` pins dependencies.
Rustup may download the toolchain on first use. No script installs system
packages. Run from a checkout, or invoke a script using its absolute path:

```sh
bash scripts/build.sh       # native executable in this checkout's bin/
bash scripts/check.sh       # formatting, Clippy, unit/integration/QML checks
bash scripts/package.sh     # native archive and SHA-256 in dist/
```

The build script selects the host target explicitly and keeps Cargo output
under the script's checkout, overriding external target-directory/target
settings. It atomically replaces `bin/omarchy-volumio`. Restart the shell to
load updated QML and the new executable. For an installed plugin, always
invoke its installed script; building another checkout does not deploy it.

## Automated checks

Python 3 suffices for HTTP tests; no pip packages are required. Qt tools are
expected under `/usr/lib/qt6/bin`, and shell imports under
`$OMARCHY_PATH/shell` or `/usr/share/omarchy/shell`.

- Rust tests cover address, metadata, volume and backoff normalization.
- `tests/test_bridge.py` runs the real executable against local HTTP servers: JSON errors, timeouts, commands, reconnects, cancellation and no replay, plus album filtering, pagination, ordered queue replacement, failed lookups and saved-playlist listing/playback.
- QML tests exercise display/configuration helpers and the actual service with mocked Quickshell I/O: persistence, pending-command cleanup, volume coalescing, offline controls, startup/restart, album/playlist caching, stale listing results and duplicate activation suppression.
- `omarchy plugin validate` checks the manifest; `qmllint` checks the production QML against installed Omarchy imports.

The QML mock directory is supplied only to `qmltestrunner`; production lint
and the installed plugin use real Quickshell. `missing-property` warnings are
suppressed for dynamic Omarchy QObject facades; other warnings fail lint.
Loopback sockets require network permission in restricted sandboxes.
The default suite does not contact or control a real player.

## Live integration (explicit opt-in)

First deploy the committed version through the official Omarchy update/install
commands, build the installed copy and restart the shell. Then, with permission:

```sh
python3 tests/live_shell.py --run
python3 tests/live_player.py --read-only
# Only when playback/volume changes are explicitly authorized:
python3 tests/live_player.py --run
```

The shell test changes the plugin address temporarily, reloads plugins,
terminates only its backend, exercises network recovery against a loopback
server, disables/re-enables the plugin in its original bar position, and restores
the original effective address. It must run in the graphical session and
requires configuration/process-control permission. It restores the address and
bar position, but does not restore the icon mode after disable/re-enable; save
and restore that mode separately. It does not command playback. The read-only
player test compares API metadata and artwork without commands.
The playback test briefly plays/pauses and lowers volume by one
point, then attempts restoration in `finally`; avoid it while someone is
listening. Do not change player system settings.

Useful diagnostics:

```sh
omarchy plugin list --json
omarchy-shell delormous.volumio status
omarchy-shell shell summon delormous.volumio '{}'
omarchy-shell shell hide delormous.volumio
qs log -p /usr/share/omarchy/shell --tail 100
```

Manually check click, Escape, artwork, long titles, keyboard operation,
control alignment and unavailable-player appearance. For the bar icon, check
both modes, right-click switching, the tooltip, artwork changes, the fallback
glyph, scope freezing on pause and flattening when stopped or offline, and
that the mode survives a shell restart and appears on every monitor. Disabling
a plugin removes its settings in Omarchy; test persistence with
reload/restart, and restore the address and icon mode after any
disable/re-enable test. A rescan can retain cached QML on the tested version;
restart the shell after source updates.

## Album browser validation

The default suite includes focused album checks using the existing loopback
server and mocked service I/O. It covers:

- Paged album listings with internal-only, NAS/USB-only and mixed-source albums.
- Complete paged track resolution before one queue replacement, with only
  internal tracks in their returned order.
- Failed or empty lookups without queue changes, and no activation replay
  after an HTTP timeout, including the uncertain-outcome error.
- Progressive service results, completed-cache reuse/refresh, cancellation
  ignoring stale results, and suppression of duplicate activation clicks.

These tests do not render the album grid or verify Volumio's server-side
queue semantics. A later live check can cover Back/Escape, keyboard focus,
small screens, artwork and one real album activation. Desktop changes and
queue replacement require their respective explicit permissions. Live checks
are deferred from the documentation and focused-test work.

Actual results and remaining gaps are recorded in [validation](validation.md).

## Playlist browser validation

Three focused loopback tests cover listing saved names, playing names with
spaces/accents/punctuation, empty/failed/malformed listings without disabling
state polling, duplicate album/playlist activation rejection, and no replay
after a playlist-start timeout. Three mocked-service tests cover cache/refresh,
cancelled/stale listings, reconfiguration, old-backend feature detection,
listing errors and activation cleanup after failure/backend restart.

Run them through the normal `bash scripts/check.sh`; no real player is needed.
Production lint includes `PlaylistBrowser.qml`, and packaging includes it.
Real-shell navigation/appearance and one actual saved-playlist start remain
a later opt-in check. Starting a playlist replaces the queue and requires
explicit playback permission. No playlist creation/editing is tested or supported.

## Distribution

Generated `bin/`, `target/`, `dist/` and Python caches are ignored by Git.
Run `bash scripts/package.sh` to produce a native archive and its SHA-256
file in `dist/`. An archive contains QML, manifest, executable, license and
documentation. Regenerate it after source changes before distribution.

On a compatible Omarchy machine, verify the checksum with
`sha256sum -c <archive>.tar.gz.sha256` from the directory containing both files.
Create a new, empty
`~/.config/omarchy/plugins/delormous.volumio/` directory using
`mkdir -p "$HOME/.config/omarchy/plugins/delormous.volumio"`, then extract with
`tar -xzf <archive>.tar.gz --strip-components=1 -C <plugin-directory>`.
Do not overwrite an existing installation. Discover the plugin, then restart
the shell before enabling it, as with the source installation:

```sh
omarchy plugin validate "$HOME/.config/omarchy/plugins/delormous.volumio"
omarchy-shell shell rescanPlugins
omarchy restart shell
omarchy plugin enable delormous.volumio
```

Archives contain the compiled executable, so no local Rust build is needed.
They do not support `omarchy plugin update`; replace them explicitly or use
the Git installation documented in the README. Archives target the build
machine's architecture and libc; prefer source builds on other architectures.

Pinned sources/toolchain/dependencies provide repeatable source builds,
not guaranteed bit-identical artifacts across machines. No CI publication,
push, release upload or visibility change is performed automatically.
Record actual results and outstanding gaps in `docs/validation.md`.
