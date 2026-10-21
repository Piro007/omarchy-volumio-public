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

## Rust backend

Tokio handles stdin, timers and one HTTP task at a time. Reqwest/rustls makes
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

Other operations: `pause`, `previous`, `next`.

| Event | Meaning |
| --- | --- |
| `configured` | Request ID and normalized address; syntax accepted, not connectivity confirmed. |
| `state` | `online: true` and normalized status, metadata, artwork URL, volume and capabilities. |
| `connection` | `online: false`, `connecting`, and on failure `error`/`retrySeconds`. |
| `result` | Request ID, `ok`, optional error; null ID for unreadable requests. |

QML permits one transport command at a time and coalesces volume changes
with a 150 ms timer and one pending value. EOF terminates the backend.
The diagnostic Omarchy IPC target exposes `status`, `refresh`, `configure`,
`action` and `volume`. Status includes the effective/saved address, process
ID, panel-open flag, state and last command/startup error.

## References

- [Official Omarchy plugin guide](https://plugins.omarchy.org/develop.html)
- [Official Volumio REST API](https://developers.volumio.com/api/rest-api)
- Installed shell README, `Ui` components and clock/audio/media plugins under `/usr/share/omarchy/shell`.

No host or player system files are modified. Scope is one player and the
official bar; queue management, library browsing and authentication are excluded.
