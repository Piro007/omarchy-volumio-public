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
- `tests/test_bridge.py` runs the real executable against local HTTP servers: JSON errors, timeouts, commands, reconnects, cancellation and no replay.
- QML tests exercise display/configuration helpers and the actual service with mocked Quickshell I/O: persistence, pending-command cleanup, volume coalescing, offline controls, startup failure and restart scheduling.
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
requires configuration/process-control permission. It does not command
playback. The read-only player test compares API metadata and artwork without commands.
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
control alignment and unavailable-player appearance. Disabling a plugin
removes its settings in Omarchy; test persistence with reload/restart, and
restore the address after any disable/re-enable test. A rescan can retain
cached QML on the tested version; restart the shell after source updates.

## Distribution

Generated `bin/`, `target/`, `dist/` and Python caches are ignored by Git.
An archive contains QML, manifest, executable, license and documentation.
Validate it after extraction and verify its checksum. It targets the build
machine's architecture and libc. Source builds on another architecture are
preferred to assuming binary compatibility.

Pinned sources/toolchain/dependencies provide repeatable source builds,
not guaranteed bit-identical artifacts across machines. No CI publication,
push, release upload or visibility change is performed automatically.
Record actual results and outstanding gaps in `docs/validation.md`.
