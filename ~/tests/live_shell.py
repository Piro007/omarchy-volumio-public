"""Opt-in installed-plugin lifecycle checks; restores the original address."""
import argparse
import json
import os
import signal
import subprocess
import time
from test_bridge import Player


def call(*args):
    return subprocess.check_output(["omarchy-shell", *args], text=True, timeout=5).strip()


def status():
    return json.loads(call("delormous.volumio", "status"))


def wait(check):
    last = None
    for _ in range(60):
        try:
            last = status()
            if check(last):
                return last
        except (subprocess.CalledProcessError, ValueError):
            pass
        time.sleep(.2)
    raise AssertionError(last)


def pids():
    path = os.path.expanduser("~/.config/omarchy/plugins/delormous.volumio/bin/omarchy-volumio")
    found = []
    for pid in os.listdir("/proc"):
        if pid.isdigit():
            try:
                if os.readlink("/proc/" + pid + "/exe") == path:
                    found.append(int(pid))
            except OSError:
                pass
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", required=True)
    parser.parse_args()
    original = status()["address"]
    config = json.loads(call("shell", "listShellConfig"))
    placement = [(section, i) for section, entries in config["bar"]["layout"].items()
                 for i, entry in enumerate(entries) if entry.get("id") == "delormous.volumio"]
    assert len(placement) == 1, placement
    section, index = placement[0]
    disabled = False
    try:
        call("delormous.volumio", "configure", "http://127.0.0.1:9")
        wait(lambda s: not s["online"] and s["address"] == "http://127.0.0.1:9/")
        old = pids()
        call("shell", "rescanPlugins")
        time.sleep(.5)
        wait(lambda s: not s["online"] and s["address"] == "http://127.0.0.1:9/")
        assert pids() != old, (pids(), old)
        print("PASS: persisted custom address survives full plugin reload", flush=True)
        call("delormous.volumio", "configure", original)
        wait(lambda s: s["online"] and s["address"] == original)
        call("delormous.volumio", "configure", original)
        time.sleep(.5)
        assert not status()["error"], status()
        print("PASS: saving identical address is idempotent", flush=True)
        old = pids()
        assert len(old) == 1, old
        os.kill(old[0], signal.SIGTERM)
        wait(lambda s: not s["online"])
        wait(lambda s: s["online"])
        new = pids()
        assert len(new) == 1 and new != old, (old, new)
        print("PASS: backend restarts after termination; one process", flush=True)
        player = Player()
        try:
            call("delormous.volumio", "configure", player.address)
            wait(lambda s: s["online"] and s["state"].get("title") == player.snapshot["title"])
            player.mode = "http"
            call("delormous.volumio", "refresh")
            wait(lambda s: not s["online"])
            player.mode = "ok"
            wait(lambda s: s["online"])
            assert not player.calls
            print("PASS: QML observes automatic network recovery; no playback commands", flush=True)
        finally:
            player.shutdown()
            player.server_close()
        call("shell", "summon", "delormous.volumio", "{}")
        wait(lambda s: s["panelOpen"])
        call("shell", "hide", "delormous.volumio")
        wait(lambda s: not s["panelOpen"])
        print("PASS: panel opens and closes through official IPC", flush=True)
        subprocess.run(["omarchy", "plugin", "disable", "delormous.volumio"], check=True)
        disabled = True
        deadline = time.monotonic() + 5
        while pids() and time.monotonic() < deadline:
            time.sleep(.1)
        assert not pids(), pids()
        subprocess.run(["omarchy", "plugin", "enable", "delormous.volumio",
                        "--section", section, "--index", str(index)], check=True)
        disabled = False
        wait(lambda s: s["backendPid"] > 0)
        call("delormous.volumio", "configure", original)
        wait(lambda s: s["online"] and s["address"] == original)
        assert len(pids()) == 1, pids()
        print("PASS: disable cleans up; enable starts one backend", flush=True)
    finally:
        if disabled:
            subprocess.run(["omarchy", "plugin", "enable", "delormous.volumio",
                            "--section", section, "--index", str(index)], check=True)
            wait(lambda s: s["backendPid"] > 0)
        call("delormous.volumio", "configure", original)
        wait(lambda s: s["online"] and s["address"] == original)
    print("RESTORED:", original, flush=True)


if __name__ == "__main__":
    main()
