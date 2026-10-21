# Omarchy Volumio

Control a Volumio player from the native Omarchy/Quickshell bar.

- Compact widget with a themed control panel.
- Track title, artist, album, artwork and playback status.
- Play/pause, previous/next and volume controls.
- Automatic state updates, offline indication and reconnection.
- Player address saved through Omarchy's configuration API.

Version **0.1.0** is a working MVP for one player and the official Omarchy bar.

## Requirements

- Omarchy Quattro with the official `omarchy plugin` commands; tested on 4.0.6.
- Rust/Cargo installed through rustup, Git and a C compiler/linker.
- Internet access for the pinned Rust toolchain and dependencies on the first build.
- A reachable Volumio HTTP(S) API. Nothing is installed on the player.

## Install

```sh
omarchy plugin add https://github.com/Piro007/omarchy-volumio-public.git
bash "$HOME/.config/omarchy/plugins/delormous.volumio/scripts/build.sh"
omarchy plugin enable delormous.volumio
```

**Build the installed copy before enabling it.** The service loads
`bin/omarchy-volumio` from its own plugin directory. Building a separate
checkout does not update the installed executable. The build script works
from any working directory and does not install system packages or services.

## Configure and use

Click the widget, enter your player's base URL under **Player**, then click
**Save**. The default is `http://volumio.local`; use your player's IP address
if local hostname resolution is unavailable.

HTTP(S), hostnames and explicit ports are supported. Credentials, URL paths,
query parameters and fragments are not. The address is stored in the widget's
entry in `~/.config/omarchy/shell.json` through Omarchy's API.

Use the buttons for previous, play/pause and next, and the slider for volume.
Volume adjustment is disabled when the player reports fixed output or no
numeric volume. Missing artwork uses a music icon.

Escape closes the panel. Space/Enter toggles playback and Left/Right adjusts
volume when the address field is not being edited.

State refreshes every two seconds. When disconnected, controls are disabled
and the last metadata remains visible. Automatic retries back off to at most
30 seconds; **Refresh** retries immediately. Failed commands are never replayed.

Optional CLI configuration:

```sh
omarchy bar set delormous.volumio address http://YOUR-PLAYER
omarchy bar move delormous.volumio --section right
```

## Update

```sh
omarchy plugin update delormous.volumio
bash "$HOME/.config/omarchy/plugins/delormous.volumio/scripts/build.sh"
omarchy restart shell
```

Rebuild the installed copy after updates. Restarting the shell briefly
recreates the bar and panels and ensures updated QML is loaded. The plugin
does not compile or download code at startup.

## Remove

```sh
omarchy plugin remove delormous.volumio
```

Omarchy removes a disabled plugin's entry and settings. Re-enabling it uses
the default address; save your custom address again. Reloading or restarting
the shell preserves the configured address.

## Troubleshooting

| Problem | What to check |
| --- | --- |
| Backend unavailable | Run the installed copy's build command above, then restart the shell. |
| Player unreachable | Check the address and network with `curl --fail --max-time 5 http://YOUR-PLAYER/api/v1/getState`. Requests bypass HTTP proxies. |
| Widget missing | Run `omarchy plugin validate "$HOME/.config/omarchy/plugins/delormous.volumio"`, then enable the plugin. |
| Changes not appearing | Rebuild the installed copy and restart the shell; a rescan can retain cached QML on the tested Omarchy version. |
| Volume unavailable | Check whether Volumio reports fixed output or omits numeric volume. |

Inspect the current connection and state with:

```sh
omarchy-shell delormous.volumio status
```

## Limitations and development

The MVP does not manage queues, libraries, multiroom, authentication or player
system settings. Multi-monitor behavior and other architectures need further
validation. Native binary archives are architecture/libc-specific.

See [development and packaging](docs/development.md),
[architecture](docs/architecture.md) and [validation results](docs/validation.md).

Licensed under the [MIT license](LICENSE).
