# User guide

For installation, updates, and removal, see the [README](../README.md).

## Player address

Click the bar widget, enter the player's base URL under **Player**, and click
**Save**. The default is `http://volumio.local`; an IP address can avoid local
hostname-resolution problems.

HTTP(S), hostnames, and explicit ports are supported. Credentials, URL paths,
query parameters, and fragments are not. Settings are saved through
Omarchy's configuration API in the widget's entry in
`~/.config/omarchy/shell.json`.

Optional CLI configuration:

```sh
omarchy bar set delormous.volumio address http://YOUR-PLAYER
omarchy bar move delormous.volumio --section right
```

Disabling the plugin removes its settings. Re-enabling uses the default
address and cover mode. Reloading or restarting the shell preserves settings.

## Controls and connection

The panel shows title, artist, album, artwork, and playback status. Use the
previous, play/pause, and next buttons and the volume slider. Volume
adjustment is disabled when Volumio reports fixed output or no numeric volume.
Dragging sends the first volume value immediately and groups further changes
at 150 ms intervals. Release sends the latest value as soon as any pending
volume request finishes. Repeated arrow presses accumulate from your latest
requested volume. The slider shows that requested value while waiting for
confirmation, then returns to the player's value if it remains unconfirmed
2.5 seconds after acknowledgement.

Escape closes the panel. Space/Enter toggles playback and Left/Right adjusts
volume when the address field is not being edited and neither browser is open.

The backend normally polls two seconds after each successful state response
and refreshes immediately after successful commands, then every 250 ms after
responses for two seconds to catch delayed state changes. Commands take
priority over in-flight state reads; an already submitted command still runs
to completion. Offline retries back off to at most 30 seconds;
**Refresh** requests an immediate poll once any active request finishes.
Resolving and activating an album also delays polling and transport commands.
There is a per-HTTP-request timeout, but no overall album-activation deadline.

When disconnected, playback and volume controls are disabled and the last
metadata remains visible. Failed playback and volume commands are never
replayed automatically. Library-listing failures do not disable otherwise
working controls.

## Bar display

Cover art is the default. Right-click the widget to switch between cover art
and the oscilloscope; left-click opens the panel. Hover for track metadata.
Missing or failed artwork uses a music icon. If the player disconnects or
the backend stops, previously loaded artwork remains visible but dimmed.

The oscilloscope is decorative, driven by playback state rather than audio
levels. It scrolls and morphs between sine, sawtooth, square, and triangle
while playing, freezes on pause, and flattens when stopped or unreachable.

The selected mode is saved as `barIcon` alongside the player address. It can
also be changed through the CLI:

```sh
omarchy bar set delormous.volumio barIcon scope
omarchy bar set delormous.volumio barIcon cover
```

## Internal albums

Click **Browse albums** to open the cover grid. Only albums with playable
internal-storage tracks appear. Selecting a cover **replaces the current
queue** and starts those tracks in the order returned by Volumio. Mixed-source
albums play only their internal tracks. There is no track-details view or
separate Play button.

Browsing and scrolling do not affect playback. Arrow keys focus a cover;
Enter plays it. Space does nothing in the grid. **Back** returns to the
controls; Escape closes the panel. **Refresh** reloads the library.

Moving the pointer over covers does not highlight their background or border.
The focused grid tile has a thin outline for keyboard navigation; an album
being started keeps its activation highlight. The pointer cursor and title
tooltip still identify clickable covers.

Albums appear progressively. A completed scan is cached in memory until
refresh, backend restart, or player reconfiguration. Closing an incomplete
scan cancels it; reopening starts a new scan. Missing covers use a music icon.

If activation fails after submission, the queue may already have changed.
Check the player before retrying; activation is never replayed automatically.
The owner reports that the plugin and album browsing work in real use.
Automated tests cover simulated players and the service. The new hover
appearance, keyboard behavior and real-player album activation have not been
independently verified; see [validation results](validation.md).

## Saved playlists

Click **Browse playlists** beside **Browse albums** to see playlists saved
in Volumio. Click a name or use Up/Down and Enter to start it. Starting a
playlist **replaces the current queue**. Volumio plays its saved contents;
the plugin does not filter out NAS, USB, radio or other supported sources.
Playback still depends on those sources being available on the player.

The list keeps the same quiet styling as the album browser: pointer hover
does not change its background or border, keyboard focus has a thin outline,
and the playlist being started is highlighted. Space does nothing in the list.
**Back** returns to the controls, Escape closes the panel, and **Refresh**
reloads the saved playlist names. Empty and unavailable lists show a message.

Completed results stay cached until Refresh, backend restart or player
reconfiguration. Back/close cancels a pending listing. Failed listings do not
disable working playback controls. Duplicate starts are blocked, and a failed
or timed-out start is never replayed automatically. Check the player before
retrying if the error says the queue/playback may have changed.

Names with spaces, accents and punctuation are preserved. This browser lists
and plays saved playlists; it does not show their tracks or create, edit,
rename or delete them. After updating, rebuild the installed backend together
with the QML files. Older backends show a rebuild hint when opening this view.
Automated tests use simulated players and mocked service I/O; real-shell
appearance, keyboard handling and real-player playlist playback remain
unverified in this revision.

## Troubleshooting

| Problem | What to check |
| --- | --- |
| Backend unavailable or browser requests a rebuild | Run the installed copy's build command from the README, then restart the shell. |
| Player unreachable | Check the address and network with `curl --noproxy '*' --fail --max-time 5 http://YOUR-PLAYER/api/v1/getState`. This bypasses proxies, as the Rust backend does. |
| Widget missing | Run `omarchy plugin validate "$HOME/.config/omarchy/plugins/delormous.volumio"`, then enable the plugin. |
| Changes not appearing | Rebuild the installed copy and restart the shell; a rescan can retain cached QML on the tested Omarchy version. |
| Volume unavailable | Check whether Volumio reports fixed output or omits numeric volume. |

Inspect the effective address, connection, state, and last command/startup
error with:

```sh
omarchy-shell delormous.volumio status
```

## Limitations

Version 0.1.0 supports one player and the official Omarchy bar. Album browsing
covers internal storage only, with a 10,000-item limit per album or library
listing; saved-playlist listing also has a 10,000-name limit and a 1 MiB
response limit. Queue editing, direct USB/NAS browsing, library management, multiroom,
authentication, and player system settings are outside its scope.
Multi-monitor behavior and other architectures need further validation.
Binary archives are architecture/libc-specific; see
[development and packaging](development.md).
