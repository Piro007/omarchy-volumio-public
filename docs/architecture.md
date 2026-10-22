# Architecture

## Omarchy integration

The `delormous.volumio` manifest declares a shared service and a bar widget.
`Service.qml` owns one Rust process; widgets obtain it through
`bar.shell.serviceFor`. The nested panel implements the host's open/close,
toggle and popout-switch lifecycle. Native `KeyboardPanel`, `PanelKeyCatcher`,
`PanelSlider` and theme tokens provide layout and styling.

Configuration is written through `shell.updateEntryInline`. On creation,
the service reads the public `shell.barConfig` snapshot, then refreshes it
through `omarchy-shell shell listShellConfig` when the backend is ready.
This bounded, short-lived IPC process avoids stale host snapshots after
plugin reloads and is stopped when the service is destroyed.
Widgets ignore their first settings injection: Omarchy can recreate slots
with stale inline settings after a rescan. Later address edits are forwarded
to the service. Successful saves update the service's remembered address directly:
the detached shell snapshot does not necessarily refresh after every write.

The backend is a child `Quickshell.Io.Process`, not a detached daemon or
system service. Disabling/destroying the service stops it. Unexpected exit
clears pending commands and schedules one restart after three seconds.
A five-second startup watchdog reports a missing/nonresponsive executable.
Reconnection never replays pending playback or volume requests.

## Bar icon modes

The bar entry is icon-only: `WidgetButton` hides its label and draws either
the current cover art or a small oscilloscope. Left click opens the panel;
right click calls the service's `toggleIconMode()`. The tooltip still exposes
the track title, artist and album.

The service owns the mode (`iconMode`, `savedIconMode`), so every monitor's
widget follows one value. `updateEntryInline` replaces the widget's layout
entry rather than merging it, so both the address save and the mode save send
`address` and `barIcon` together. The mode is restored from `shell.barConfig`
and the `listShellConfig` refresh; external changes made with
`omarchy bar set` are forwarded from widget settings after the first
injection, matching the address behaviour.

Cover mode loads `snapshot.albumart` asynchronously into a square thumbnail
with a small source size and falls back to the music glyph when the URL is
empty, fails or the player is offline. Scope mode runs a Canvas at about
30 fps only while playing; pause stops the timer and keeps the last frame,
while stop or disconnect paints a flat line. Each of the sine, sawtooth,
square and triangle shapes is held for 2.6 seconds and blended into the next
over 1.4 seconds with smoothstep easing. The animation is deliberately
synthetic: `getState` exposes no audio levels, so it follows `status` rather
than sound. No backend or protocol change is involved. The slot swaps width
and height on vertical bars.

## Rust backend

Tokio handles stdin, timers and one state/transport HTTP task at a time.
A separate cancellable library task makes sequential browse requests so
loading the grid does not block state polling or transport commands. Reqwest/rustls makes
direct requests with a three-second timeout and a 1 MiB response limit.
Redirects and proxy use are disabled. `GET /api/v1/getState` runs every two
seconds and after commands; polling avoids a Socket.IO dependency for this MVP.

Commands use `/api/v1/commands/?cmd=…`: `play`, `pause`, `prev`, `next` and
`volume`. HTTP acknowledgement alone does not prove a playback change;
the UI follows subsequently fetched state. Errors mark the connection
unavailable, cancel queued commands and back off to a maximum of 30 seconds.
Changing address cancels the old HTTP task and queue. A request already
received by the old player cannot be undone; its result may be unknown.

Metadata is plain text; optional fields are tolerated. Unknown playback
states are rejected. Volume must be 0–100; missing volume or
`disableVolumeControl` disables adjustment. Only HTTP(S) artwork is accepted;
relative URLs are resolved against the player and loaded asynchronously by QML.

## JSON-lines protocol v1

Each message is one UTF-8 JSON line. Requests arrive on stdin, events on
stdout and diagnostics on stderr. The backend announces
`{"type":"ready","protocol":1}` and contacts no player before configuration.

```json
{"id":1,"op":"configure","address":"http://volumio.local"}
{"id":2,"op":"play"}
{"id":3,"op":"volume","volume":20}
{"id":4,"op":"refresh"}
```

Other transport operations: `pause`, `previous`, `next`.

The ready event additionally advertises `features: ["albums"]`; protocol v1
remains compatible with the original controls. QML reports a rebuild hint
when the installed backend lacks that capability.

Album requests:

```json
{"id":5,"op":"browse_albums"}
{"id":6,"op":"cancel_browse"}
{"id":7,"op":"play_album","uri":"albums://Artist/Album"}
```

Browse emits correlated `albums` events with `items` (`uri`, `title`,
`albumart`) and `done`, or `library_error` with `error`. Cancellation drops
old events using their request IDs. Album activation emits the normal
`result`; only one activation may be pending. A bounded channel sends library
events to the main loop, which alone writes stdout.

| Event | Meaning |
| --- | --- |
| `configured` | Request ID and normalized address; syntax accepted, not connectivity confirmed. |
| `state` | `online: true` and normalized status, metadata, artwork URL, volume and capabilities. |
| `connection` | `online: false`, `connecting`, and on failure `error`/`retrySeconds`. |
| `result` | Request ID, `ok`, optional error; null ID for unreadable requests. |

QML permits one transport command at a time and coalesces volume changes
with a 150 ms timer and one pending value. EOF terminates the backend.
The diagnostic Omarchy IPC target exposes `status`, `refresh`, `configure`,
`action` and `volume`. Status includes the effective/saved address, bar icon
mode, process ID, panel-open flag, state and last command/startup error.

## Album browser

`AlbumBrowser.qml` lives inside the existing panel, using a virtualized
three-column grid, asynchronous thumbnails and native button/theme states.
Browser keyboard handling is isolated from the control panel shortcuts.
The service owns a ListModel and caches complete results in memory. Back or
close cancels a partial scan; reopening an incomplete scan starts again.
Player reconfiguration/backend failure clears the cache and pending requests.

The backend pages `GET /api/v1/browse?uri=albums://` in groups of 100. Each
candidate album is browsed until an MPD song/track URI under
`music-library/INTERNAL/` is found or the album is exhausted. Artwork URLs
never determine storage membership. Album identity is the opaque URI, not
the title. Listings are bounded to 10,000 items; repeated URIs or incomplete
pages report an error instead of looping. Existing per-request timeout and
1 MiB response limits apply. Only one scan runs at a time.

On a cover activation, the transport task resolves all album pages before
changing playback. Internal tracks retain Volumio's returned order. An empty
or failed lookup sends no playback mutation. The backend sends one
`POST /api/v1/replaceAndPlay` containing `list`, its first `item`, and `index: 0`;
payloads over 8 MiB are rejected before submission. It never clears the queue
as a separate operation. Errors after submission report possible queue/playback
changes, are never retried, and trigger a state refresh. Library errors do not
assert that the player is offline. State/transport requests serialize behind
an activation; independent browse scanning continues unless cancelled.

## References

- [Official Omarchy plugin guide](https://plugins.omarchy.org/develop.html)
- [Official Volumio REST API](https://developers.volumio.com/api/rest-api)
- Installed shell README, `Ui` components and clock/audio/media plugins under `/usr/share/omarchy/shell`.

No host or player system files are modified. Scope is one player and the
official bar. Album browsing/playback covers internal storage only; queue
editing, library management and authentication are excluded.
