# Omarchy Volumio

Control one Volumio player from the Omarchy bar: playback, volume, metadata,
cover art, internal-storage albums, and saved playlists.

## Requirements

- Omarchy Quattro with the official plugin commands; tested on 4.0.6.
- Rust/Cargo through rustup, Git, and a C compiler/linker.
- Internet access for the pinned toolchain and dependencies on the first build.
- A reachable Volumio HTTP(S) API. Nothing is installed on the player.

## Install

**Omarchy installs the plugin files but does not build the Rust backend.**
Complete all four steps in order.

1. **Install the plugin.** Answer **No** if asked to enable it now.

   ```sh
   omarchy plugin add https://github.com/Piro007/omarchy-volumio-public.git
   ```

2. **Build the installed copy.** Building a separate checkout does not update it.

   ```sh
   cd "$HOME/.config/omarchy/plugins/delormous.volumio"
   ./scripts/build.sh
   ```

   If execution reports `Permission denied`, run `chmod +x scripts/build.sh`,
   then run `./scripts/build.sh` again. The script does not install system
   packages or services.

3. **Restart the Omarchy shell.** This briefly recreates the bar and panels.

   ```sh
   omarchy restart shell
   ```

4. **Enable the plugin.**

   ```sh
   omarchy plugin enable delormous.volumio
   ```

## Use

Click the widget, enter your player's base URL under **Player**, and click
**Save**. The default is `http://volumio.local`; use the player's IP address
if that hostname does not resolve.

Use the playback buttons and volume slider. Right-click the bar widget to
switch between cover art and a decorative oscilloscope. **Browse albums**
shows internal-storage albums; selecting one **replaces the current queue**
and starts its internal tracks.
**Browse playlists** lists playlists saved in Volumio and plays them as saved,
replacing the current queue.

Commands take priority over state reads, with faster state checks briefly
after each successful command. Volume changes are sent during dragging,
and repeated arrow presses accumulate from the latest requested value.

See the [user guide](docs/usage.md) for keyboard shortcuts, connection
behavior, limitations, and troubleshooting, and [validation results](docs/validation.md)
for tested behavior and remaining gaps.

## Update or remove

After an update, rebuild the installed copy and restart the shell:

```sh
omarchy plugin update delormous.volumio
bash "$HOME/.config/omarchy/plugins/delormous.volumio/scripts/build.sh"
omarchy restart shell
```

To remove it:

```sh
omarchy plugin remove delormous.volumio
```

Disabling the plugin discards its address and icon settings in Omarchy.
Reloading or restarting the shell preserves them.

## Development

See [development and packaging](docs/development.md),
[architecture](docs/architecture.md), and [validation results](docs/validation.md).

Licensed under the [MIT license](LICENSE).
