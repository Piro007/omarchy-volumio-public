"""Explicit opt-in smoke test of installed QML -> Rust -> real Volumio.

Temporarily controls playback, lowers volume one point, tests reconnection,
and restores the player and plugin configuration in a finally block.
"""
import argparse
import json
import urllib.parse
import urllib.request
import math
from live_support import PLUGIN, call, wait, capture_settings, restore_settings


def ipc(*args):
    return call(PLUGIN, *args)


def volume_value(value):
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value if 0 <= value <= 100 else None
    if isinstance(value, str) and value.isascii() and value.isdigit():
        number = int(value)
        return number if number <= 100 else None
    return None


def seek_seconds(value):
    if isinstance(value, bool) or not isinstance(value, (int, float, str)):
        return None
    try:
        number = float(value)
        return int(number / 1000) if math.isfinite(number) and number >= 0 else None
    except ValueError:
        return None


def matches_state(snapshot, api):
    return (snapshot.get("status") == api.get("status")
            and all(snapshot.get(key, "") == (api.get(key) if isinstance(api.get(key), str) else "")
                    for key in ("title", "artist", "album"))
            and snapshot.get("volume") == volume_value(api.get("volume")))


def restore_player(original, get):
    errors = []
    commands = []
    volume = volume_value(original.get("volume"))
    if not original.get("disableVolumeControl") and volume is not None:
        commands.append("volume&volume=" + str(volume))
    seek = seek_seconds(original.get("seek"))
    if original["status"] in ("play", "pause") and seek is not None:
        commands.append("seek&position=" + str(seek))
    commands.append(original["status"])
    for command in commands:
        try:
            get("api/v1/commands/?cmd=" + command)
        except (OSError, ValueError) as error:
            errors.append(str(error))
    if errors:
        raise RuntimeError("Player restoration incomplete: " + "; ".join(errors))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--run", action="store_true", help="Temporarily change playback and volume")
    mode.add_argument("--read-only", action="store_true", help="Compare API and plugin state without commands")
    args = parser.parse_args()
    initial = wait(lambda s: s["online"])
    address = initial["address"]
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def get(path):
        with opener.open(urllib.parse.urljoin(address, path), timeout=5) as response:
            return response.read()

    original = json.loads(get("api/v1/getState"))
    print("Initial:", json.dumps({k: original.get(k) for k in ("status", "volume", "seek")}), flush=True)
    if args.read_only:
        wait(lambda s: s["online"] and matches_state(s["state"], json.loads(get("api/v1/getState"))))
        art = initial["state"].get("albumart")
        if art:
            with opener.open(art, timeout=10) as response:
                assert response.headers.get_content_type().startswith("image/")
                assert response.read()
        print("PASS: real API JSON matches plugin state; artwork readable; no commands sent", flush=True)
        return
    if original.get("status") not in ("play", "pause", "stop"):
        raise AssertionError("Unknown initial playback state")
    saved = capture_settings()
    original_volume = volume_value(original.get("volume"))
    try:
        ipc("action", "play")
        wait(lambda s: s["state"].get("status") == "play")
        assert json.loads(get("api/v1/getState"))["status"] == "play"
        print("PASS: QML -> Rust -> real player play", flush=True)
        ipc("action", "pause")
        wait(lambda s: s["state"].get("status") == "pause")
        assert json.loads(get("api/v1/getState"))["status"] == "pause"
        print("PASS: pause", flush=True)
        if not original.get("disableVolumeControl") and original_volume is not None:
            value = max(0, original_volume - 1)
            ipc("volume", str(value))
            wait(lambda s: s["state"].get("volume") == value)
            assert volume_value(json.loads(get("api/v1/getState")).get("volume")) == value
            print("PASS: volume", value, flush=True)
        art = initial["state"].get("albumart")
        if art:
            with opener.open(art, timeout=10) as response:
                assert response.headers.get_content_type().startswith("image/")
                assert len(response.read()) > 0
            print("PASS: artwork HTTP image", flush=True)
        ipc("configure", "http://127.0.0.1:9")
        wait(lambda s: not s["online"] and s["address"] == "http://127.0.0.1:9/")
        print("PASS: offline state", flush=True)
        ipc("configure", address)
        wait(lambda s: s["online"] and s["address"] == address)
        print("PASS: reconnect to player", flush=True)
    finally:
        try:
            # Direct requests restore the original player even if plugin IPC failed.
            restore_player(original, get)
        finally:
            # Settings restoration does not require the player to be online.
            restore_settings(saved)
    ipc("refresh")
    restored = wait(lambda s: s["state"].get("status") == original["status"]
                    and (original_volume is None or s["state"].get("volume") == original_volume))
    print("RESTORED:", restored["state"].get("status"), restored["state"].get("volume"), flush=True)


if __name__ == "__main__":
    main()
