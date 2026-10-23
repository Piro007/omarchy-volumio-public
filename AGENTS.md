# Omarchy Volumio

- English is the project language: documentation, comments, UI text, commit messages, Issues and PRs. Keep API names and identifiers unchanged. Discussion with the owner may be in French.
- Preserve the Rust HTTP/JSON-lines backend and native QML service/widget/panel architecture. Read `docs/architecture.md` before changing lifecycle or IPC behavior.
- Keep `Cargo.lock` and the pinned toolchain. Build the installed plugin using its own `scripts/build.sh`; never assume the invoking working directory is the plugin directory.
- Use official Omarchy plugin/configuration APIs. Never edit `/usr/share/omarchy` or add a system service.
- Run `bash scripts/check.sh`; validate QML changes in the real shell when permitted. A successful compile is not a functional test.
- Default tests use loopback servers and mocked QML I/O. Live tests require explicit permission for desktop configuration changes; playback tests additionally require permission to control the player.
- Never replay commands after a timeout or address change. Respect `disableVolumeControl` and clean up child processes.
- Update existing README and docs with relevant behavior, tests and limitations. Distinguish observed, user-reported and unverified results.
- Work on the owner-selected branch (`feat/Optimization` for this maintenance pass) with focused conventional commits. Future development branches are local unless explicitly authorized for publication. Do not rewrite history, push, or change repository visibility without explicit authorization.
- Do not modify files outside the repository or install system packages without permission.
