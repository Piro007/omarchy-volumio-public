# Validation

## Saved playlist browser (2026-10-22)

Source base: `4261099` on `main`. Added the name-only **Browse playlists**
view, cached/cancellable saved-playlist listing and direct playlist activation.
Playlist contents and sources are delegated to Volumio. The JSON-lines
protocol remains v1 with the additive `playlists` feature and requests.

Observed results:

- `bash scripts/check.sh`: passed. Formatting, Clippy, build, 3 Rust tests,
  14 loopback bridge tests and 27 QML test functions (33 including
  setup/cleanup), manifest validation and lint for all six production QML files.
- Three added loopback tests verify saved names and their exact URL encoding,
  empty/error/malformed listings, state polling after listing failures,
  duplicate album/playlist starts, and no replay after a playlist timeout.
- Three added mocked-service tests verify cache/refresh/cancellation,
  stale results, reconfiguration, old-backend compatibility, listing errors,
  duplicate starts and activation cleanup without replay after backend failure.
- Volumio's official REST and playlist-manager source was inspected to confirm
  the array-of-names listing format and native playlist playback path.
- Native packaging passed; checksum and archived QML/documentation contents
  matched the source. The release executable advertised `playlists` and
  exited cleanly on EOF without contacting a player.
- Documentation links, shell/Python syntax and `git diff --check` passed.

No installed-copy update, shell restart or real-player commands were run.
The new list's real-shell appearance/keyboard behavior and actual Volumio
playlist activation remain unverified. Existing owner reports about album
browsing do not establish playlist validation.

## Album tile hover styling (2026-10-22)

Source base: `2eb78dc` on `main`. Album tiles now keep a transparent background
and no border on pointer hover. A one-pixel theme-colored outline marks the
focused grid tile, and the existing starting-album highlight remains.
This uses the native button's public color and border properties; playback,
tooltips and pointer handling are unchanged.

Observed: `bash scripts/check.sh` passed (3 Rust tests, 11 loopback tests,
24 QML test functions, manifest validation and production QML lint).
`git diff --check` passed. No tests were added for this styling-only change.

Owner-reported: the plugin and album browsing work in real use. The updated
hover appearance has not been checked in the real shell. No deployment,
shell restart or live player control was performed during this change.

## Focused album tests and documentation (2026-10-22)

Source base: `d2e7aea` on `main`. This pass changes tests and documentation
only; no production-code fixes were needed for the added test cases.

Observed results:

- `bash scripts/check.sh`: passed. Formatting, Clippy, build, 3 Rust unit
  tests, 11 loopback bridge tests, 24 QML test functions (30 including
  setup/cleanup), official manifest validation and lint for all five
  production QML files passed.
- Four added bridge tests exercise the real backend against a simulated
  player: paged album filtering (internal, NAS/USB and mixed sources),
  complete track resolution before one ordered internal-only queue payload,
  failed/empty lookups without playback requests, and activation timeout
  without replay over the following state refresh and polling cycle.
- Three added mocked-service tests cover progressive results, completed-cache
  reuse/refresh, cancellation ignoring stale events, duplicate activation
  suppression and failed activation requesting state refresh without replay.
- The README now separates installation, building the installed copy, shell
  restart and enablement. Detailed behavior and troubleshooting moved to the
  [user guide](usage.md). Documentation was checked against the implementation
  and installed Omarchy commands, including the immediate-enable prompt,
  offline artwork, polling exceptions and proxy-free backend requests.

The HTTP fixture records submitted queue payloads; it does not implement or
validate Volumio's actual queue behavior. The QML harness exercises the
service, not the album grid's visual layout or keyboard handling. No live
desktop/player tests, installation, shell restart or package rebuild were
performed. Real-player album activation and real-shell browser/icon behavior
remain unverified. Existing generated archives were not refreshed by this pass.

## Historical results

The sections below record earlier revisions and their validation scope.
Their statements about pending tests, installations and archives apply to
those revisions; the current results above supersede only the checks they
explicitly cover. Owner-reported results remain distinct from observed tests.

### Bar icon modes (2026-10-22)

Implemented on `feat/album-browser`: the bar entry is now icon-only, showing
album cover art or an oscilloscope, switched by right click and persisted as
`barIcon`. The address and backend protocol are unchanged.

Completed checks:

- `bash scripts/check.sh`: passed. Rust formatting, Clippy and build; 3 Rust
  unit tests; 7 loopback bridge tests; 21 QML test functions (27 including
  setup/cleanup), including new model, service and oscilloscope tests for mode
  parsing, waveform blending, persistence, config restore and idempotent
  toggling; official manifest validation and `qmllint` for all five production
  QML files.
- `bash scripts/package.sh`: passed; the archive contains `Oscilloscope.qml`,
  the manifest, the documentation updates and the rebuilt binary.
- Offscreen `grabToImage` render of `Oscilloscope.qml` at one sine frame and
  five hold/morph points: all four shapes and the intermediate blends drew as
  expected with the baseline and frame.

Not verified:

- Visual appearance, right-click behaviour and tooltips in the real shell;
  the offscreen render does not test the bar slot, theme colours or size.
- Persistence across a shell restart, mode changes through `omarchy bar set`,
  multi-monitor synchronisation, vertical bars and idle CPU cost.
- Installation, shell restarts and live player requests were not performed.

### Album browser implementation (2026-10-22)

The album-grid/click-to-play feature is implemented on `feat/album-browser`.
Only Rust compilation, QML static analysis and manifest validation are in
scope for this phase. Functional/visual tests, live queue replacement,
installation and desktop restarts are deferred as requested. The successful
MVP results below describe the earlier control plugin, not validation of the
new album-browser behavior.

Completed checks:

- `cargo check --locked --all-targets`: passed; existing test targets compile
  but no tests were executed.
- `cargo build --locked`: passed.
- QML lint for `Service.qml`, `ControlPanel.qml` and `AlbumBrowser.qml`: passed
  with no reported warnings (the existing dynamic-facade suppression remains).
- `omarchy plugin validate .`, modified-script syntax and whitespace checks:
  passed.

No new dependencies, live player requests, deployment, shell restart or
functional test runs were needed for implementation. The previous installation
remains unchanged. Library filtering, real queue replacement and visual behavior
are explicitly **unverified** until the separate test step.

Implementation details and the later validation scenarios are recorded in
[architecture](architecture.md) and [development](development.md).

### Results through final validation (2026-10-21)

Environment: Omarchy 4.0.6, Qt 6.12.0, Rust 1.99.1, x86_64 Linux.

| Check | Result |
| --- | --- |
| Rust formatting and Clippy (`-D warnings`) | Passed. |
| Rust unit tests | 3 passed. |
| Real Rust executable against loopback HTTP servers | All 7 integration tests passed: commands, malformed JSON, HTTP failure, timeout, reconnection, cancellation and no replay. |
| QML helpers and service with mocked Quickshell I/O | 12 test functions passed; 16 including setup/cleanup. Covers all six bar sections, current configuration overriding a stale facade, saved settings, startup/restart, pending commands, volume, offline controls and destruction. |
| Official plugin validation and production QML lint | Final manifest validation and QML lint passed. Palette references use `Commons.Color`. Dynamic Omarchy `missing-property` warnings are selectively suppressed. |
| Shell script syntax and Python compilation | Passed. |
| Clean local Git clone build | Passed from an unrelated working directory, with conflicting Cargo target/target-directory environment overrides. Binary appeared in the clone's `bin/`; Git stayed clean. |
| Native archive | SHA-256, extracted manifest, expected contents, executable startup and EOF shutdown passed. No Git/build directories included. |
| Installed-copy build and former installer wrapper | Passed from an unrelated directory. Executable built in the installed copy. Existing bar layout and settings remained unchanged. |
| Real Volumio read-only check | Final read-only check matched API metadata and retrieved artwork while the player was playing at volume 21. Finalization sent no playback/volume commands. |

Generated artifacts are ignored by Git. No history rewrite, push, release
publication or repository-visibility change was performed.

### Final live validation

After the desktop was unlocked, live testing exposed a real reload bug:
Omarchy's detached configuration snapshot and recreated widget settings
could retain an old address. Ignoring initial widget settings alone did not
resolve it. The final service refreshes configuration through the documented
`omarchy-shell shell listShellConfig` IPC when its backend starts, while
saves continue through `shell.updateEntryInline`.

The installed revision `ce2d449` passed `python3 tests/live_shell.py --run`:

- Custom address survived a full plugin rescan/reload.
- Saving the same address remained idempotent.
- Terminating the backend triggered recovery with exactly one backend.
- A loopback player HTTP failure produced offline state and automatic recovery.
- Official panel summon/hide worked.
- Disable stopped the backend; re-enable started one backend.
- The original player address and bar position were restored.

The loopback fixture emitted two `KeyError: 'cmd'` tracebacks for artwork
requests because it only implements state and command endpoints. The test
exited successfully and all lifecycle assertions passed; mock artwork is
not validated. The separate real-player read-only test passed artwork and
JSON checks. Screenshot inspection confirmed the English panel, artwork,
metadata, controls and corrected theme colors rendered correctly.

Only targeted QML tests/lint, the live service checks, a read-only player
check and one final manifest validation were run for these final fixes.
Rust/backend and build/distribution results above come from earlier checks;
those components were not changed or retested during finalization.

### Prior manual evidence and remaining limits

The owner reports successful compilation, installation, playback, metadata
and volume on two Omarchy computers. Earlier development also exercised
play/pause/volume, artwork and Escape on the development machine. These are
prior/manual results, not fresh tests of this revision.

- Fresh click/Escape and removal tests were not repeated; panel IPC and disable/re-enable were verified.
- Multi-monitor behavior and other architectures are not verified here.
- Omarchy discards a disabled plugin's settings; re-enable uses the default address until configured again.
- Binary archives are architecture/libc-specific; no bit-for-bit reproducibility claim is made. The previously checked archive predates the final QML fixes; regenerate it before distributing binaries.
- The loopback artwork fixture limitation above remains; real-player artwork passed.

The three identified finalization issues are resolved and the source MVP is
ready for an initial public preview with these limitations. Nothing was
published and repository visibility was not changed.


### Public README and installation cleanup

The optional `scripts/install.sh` wrapper was removed after the validation
above. Installation now uses the official add, build-installed-copy and
enable sequence documented in the README, targeting
`https://github.com/Piro007/omarchy-volumio-public.git`. The historical
installer result remains as evidence for the former wrapper, not a current
installation entry point.

Documentation links, command paths and obsolete installation references were
checked, and `omarchy plugin validate .` passed. Runtime code and the build
script were unchanged; Rust and live-player tests were not repeated. These
checks do not establish that the new remote already contains this revision.
No Git remote was changed and nothing was pushed or published by this cleanup.
