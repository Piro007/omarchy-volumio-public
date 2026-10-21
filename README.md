# Omarchy Volumio

Control a Volumio player from the official Omarchy/Quickshell bar: playback,
track metadata, artwork and volume. The compact panel follows the desktop
theme, refreshes every two seconds and reconnects automatically.

## Requirements

- Omarchy Quattro with the official `omarchy plugin` commands; developed on 4.0.6.
- Rust/Cargo through rustup, Git and a C compiler/linker. The pinned Rust toolchain and dependencies require Internet on the first build.
- A reachable Volumio HTTP(S) API. No software is installed on the player.

Python 3 and Qt's QML test/lint tools are needed for development checks,
not for normal use. Scripts do not install system packages or services.

## Install

The repository is currently private; Git must already have access to it.
The commands below install its default branch. To install `feat/initial-plugin`
explicitly, clone it with `git clone --branch feat/initial-plugin` and use the
local-checkout installer described below.

```sh
omarchy plugin add https://github.com/Piro007/omarchy-volumio.git --yes
bash "$HOME/.config/omarchy/plugins/delormous.volumio/scripts/build.sh"
omarchy plugin enable delormous.volumio --section right
```

**Build the installed copy.** The QML service expects
`~/.config/omarchy/plugins/delormous.volumio/bin/omarchy-volumio`.
Building a separate development checkout does not update that executable.
The build script can be invoked from any working directory; it resolves its
own checkout and places the native executable in that checkout's `bin/`.

For a local, committed Git checkout, `bash /path/to/omarchy-volumio/scripts/install.sh`
uses the official add command, builds the newly installed copy, then enables
it. It refuses to overwrite an existing installation. From the installed
copy, the same script builds and enables that copy.

## Configure and use

Click the widget to open the panel. Enter your player's base URL under
**Player**, then click **Save**. The default is `http://volumio.local`;
use your player's IP address if local hostname resolution is unavailable.
The address is stored through Omarchy's API in the widget's entry in
`~/.config/omarchy/shell.json`. HTTP(S), hostnames and explicit ports are
supported; credentials, paths, query parameters and fragments are not.

The buttons provide previous, play/pause and next. The slider controls
volume from 0 to 100 unless the player disables volume control. Escape
closes the panel; Space/Enter toggles playback and Left/Right adjusts volume
when the address field is not being edited. Missing artwork uses a music icon.

When disconnected, controls are disabled and the last metadata remains
visible with an unreachable indicator. Retries occur after 2, 4, 8, 16,
then at most 30 seconds. **Refresh** requests an immediate attempt. Failed
commands are reported and never automatically replayed.

```sh
omarchy bar move delormous.volumio --section right
# Configure without opening the panel:
omarchy bar set delormous.volumio address http://YOUR-PLAYER
omarchy-shell shell summon delormous.volumio '{}'
omarchy-shell shell hide delormous.volumio
omarchy-shell delormous.volumio status
```

## Update or remove

```sh
omarchy plugin update delormous.volumio
bash "$HOME/.config/omarchy/plugins/delormous.volumio/scripts/build.sh"
omarchy restart shell
# Remove:
omarchy plugin remove delormous.volumio
```

If upgrading an early development build that used the development IP as its
default, explicitly save your player address before updating, using **Save**
or `omarchy bar set delormous.volumio address http://YOUR-PLAYER`.

A shell restart briefly recreates the desktop bar and panels. It ensures
updated QML is loaded: on the tested Omarchy version, a plugin rescan alone
could retain old QML code. The plugin never compiles or downloads code on
startup. Local installations retain the local Git checkout as their origin.

Omarchy removes a disabled plugin's entry and settings. Re-enabling it uses
the default address; save your custom address again. Reloading or restarting
the shell preserves a configured address.

## Troubleshooting

- **Backend unavailable:** run the installed copy's build script; check that its `bin/omarchy-volumio` is executable, then restart the shell.
- **Player unreachable:** check the address and network; try `curl --fail --max-time 5 http://YOUR-PLAYER/api/v1/getState`. Requests bypass HTTP proxies.
- **Widget missing:** run `omarchy plugin validate "$HOME/.config/omarchy/plugins/delormous.volumio"`, then enable it with the command above.
- **Changes not appearing:** rebuild the installed copy and restart the shell, rather than repeatedly rescanning plugins.
- **Volume unavailable:** Volumio may expose a fixed-output configuration or omit a numeric volume. The plugin respects this setting.

## Distribution and limitations

`bash scripts/package.sh` creates a native binary archive and SHA-256 file
in `dist/`. On a compatible Omarchy system, verify the checksum, extract the
archive into a new `~/.config/omarchy/plugins/delormous.volumio/` directory
with `tar --strip-components=1`, validate that directory, rescan plugins,
and enable it. Do not overwrite an existing installation. Binary archives
do not support `omarchy plugin update`; replace them explicitly or use Git.

The MVP supports one player and the official bar. It does not manage queues,
libraries, multiroom, authentication or player system settings. Source builds
are pinned, but binary archives are architecture/libc-specific, not universal
or guaranteed bit-for-bit reproducible. Multi-monitor behavior needs broader
validation. No public release or automated publishing is configured.

See [architecture](docs/architecture.md), [development](docs/development.md)
and [validation results](docs/validation.md). MIT license.
