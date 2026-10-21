"""Explicit opt-in smoke test of installed QML -> Rust -> real Volumio.

Temporarily controls playback, lowers volume one point, tests reconnection,
and restores the player and plugin configuration in a finally block.
"""
import argparse
import json
import subprocess
import time
import urllib.parse
import urllib.request


def ipc(*args):
    result = subprocess.run(["omarchy-shell", "delormous.volumio", *args],
                            check=True, capture_output=True, text=True)
    return result.stdout.strip()


def wait(predicate, timeout=12):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        last = json.loads(ipc("status"))
        if predicate(last):
            return last
        time.sleep(.3)
    raise AssertionError(last)


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
    print("Initial:", json.dumps({k: original[k] for k in ("status", "volume", "seek")}), flush=True)
    if args.read_only:
        for key in ("status", "title", "artist", "album", "volume"):
            assert initial["state"].get(key) == original.get(key), key
        art = initial["state"].get("albumart")
        if art:
            with opener.open(art, timeout=10) as response:
                assert response.headers.get_content_type().startswith("image/")
                assert response.read()
        print("PASS: real API JSON matches plugin state; artwork readable; no commands sent", flush=True)
        return
    try:
        ipc("action", "play")
        wait(lambda s: s["state"].get("status") == "play")
        assert json.loads(get("api/v1/getState"))["status"] == "play"
        print("PASS: QML -> Rust -> real player play", flush=True)
        ipc("action", "pause")
        wait(lambda s: s["state"].get("status") == "pause")
        assert json.loads(get("api/v1/getState"))["status"] == "pause"
        print("PASS: pause", flush=True)
        if not original.get("disableVolumeControl") and isinstance(original.get("volume"), int):
            value = max(0, original["volume"] - 1)
            ipc("volume", str(value))
            wait(lambda s: s["state"].get("volume") == value)
            assert json.loads(get("api/v1/getState"))["volume"] == value
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
        ipc("configure", address)
        wait(lambda s: s["online"] and s["address"] == address)
        if not original.get("disableVolumeControl") and isinstance(original.get("volume"), int):
            get("api/v1/commands/?cmd=volume&volume=" + str(original["volume"]))
        # Stop restores a stopped track to position zero. Paused tracks retain
        # a seek position; restore it through the playback API, never settings.
        if original["status"] in ("play", "pause") and original.get("seek", 0):
            get("api/v1/commands/?cmd=seek&position=" + str(int(original["seek"] / 1000)))
        get("api/v1/commands/?cmd=" + original["status"])
        ipc("refresh")
        restored = wait(lambda s: s["state"].get("status") == original["status"]
                        and s["state"].get("volume") == original["volume"])
        print("RESTORED:", restored["state"]["status"], restored["state"]["volume"], flush=True)


if __name__ == "__main__":
    main()
