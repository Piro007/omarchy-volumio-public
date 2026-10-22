# Omarchy Volumio

Control a Volumio player from the native Omarchy/Quickshell bar.

- Compact widget with a themed control panel.
- Album cover art or an animated oscilloscope in the bar; right-click switches.
- Track title, artist, album, artwork and playback status in the panel and tooltip.
- Play/pause, previous/next and volume controls.
- Automatic state updates, offline indication and reconnection.
- Player address saved through Omarchy's configuration API.
- Internal-storage album browser with cover artwork and click-to-play.

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

### Bar display

The bar shows the current album's cover art by default. Right-click the
widget to switch to an oscilloscope and back; the choice is saved as
`barIcon` in the widget's entry next to the address. Left click still opens
the panel. No title is shown in the bar: hover for the tooltip or open the
panel for details. Missing artwork, an unreachable player or a stopped
backend falls back to the music icon.

The oscilloscope is a decorative animation driven by playback state, not by
audio levels (the Volumio API exposes none). It scrolls and morphs between
sine, sawtooth, square and triangle while playing, freezes on pause and
flattens when stopped or unreachable.

You can also choose the mode from the command line:

```sh
omarchy bar set delormous.volumio barIcon scope
omarchy bar set delormous.volumio barIcon cover
```

Optional CLI configuration:

```sh
omarchy bar set delormous.volumio address http://YOUR-PLAYER
omarchy bar move delormous.volumio --section right
```

## Browse internal albums

Click **Browse albums** to open a cover grid. Only albums containing music
in Volumio's internal storage appear. Clicking a cover starts that album,
**replacing the current queue** with its internal-storage tracks in the
order returned by Volumio. Mixed-source albums play only their internal tracks.
There is no separate Play button or track-details view.

Browsing and scrolling do not affect playback. Use arrow keys to focus a
cover and Enter to play it; Space does nothing in the grid. **Back** returns
to the controls, Escape closes the panel, and **Refresh** reloads the library.
Albums appear progressively and remain cached in memory until refresh,
backend restart or player reconfiguration. Missing covers use a music icon.

If activation fails after the request was sent, the queue may already have
changed. Check the player before retrying; activation is never retried
automatically. Library listing errors do not disable otherwise working controls.

**Development status:** the album browser has compilation/static checks only.
Functional and visual validation are deferred to a separate testing step.
Build the updated backend together with the QML files before testing.

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
the default address and cover art; save your custom address and switch the
icon mode again. Reloading or restarting the shell preserves both settings.

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

The browser supports internal-storage albums only, with a 10,000-item limit
per album or library listing. Queue editing, USB/NAS browsing, library
management, multiroom, authentication and player system settings are outside
its scope. The bar oscilloscope is synthetic: Volumio exposes no audio-level
data, so it follows playback state only. Multi-monitor behavior and other
architectures need further validation. Native binary archives are
architecture/libc-specific.

See [development and packaging](docs/development.md),
[architecture](docs/architecture.md) and [validation results](docs/validation.md).

Licensed under the [MIT license](LICENSE).
