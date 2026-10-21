# MVP validation

## Results through final validation (2026-10-21)

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

## Final live validation

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

## Prior manual evidence and remaining limits

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


## Public README and installation cleanup

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
