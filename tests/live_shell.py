"""Opt-in installed-plugin lifecycle checks; restores address, icon mode and bar position."""
import argparse
import os
import signal
import time
from test_bridge import Player
from live_support import PLUGIN, call, run, status, wait, capture_settings, restore_settings


def pids():
    path = os.path.expanduser("~/.config/omarchy/plugins/delormous.volumio/bin/omarchy-volumio")
    found = []
    for pid in os.listdir("/proc"):
        if pid.isdigit():
            try:
                if os.readlink("/proc/" + pid + "/exe").removesuffix(" (deleted)") == path:
                    found.append(int(pid))
            except OSError:
                pass
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", required=True)
    parser.parse_args()
    saved = capture_settings()
    section, index = saved.section, saved.index
    player = Player()
    original = player.address + "/"
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
        call("delormous.volumio", "configure", player.address)
        wait(lambda s: s["online"] and s["state"].get("title") == player.snapshot["title"])
        player.mode = "http"
        call("delormous.volumio", "refresh")
        wait(lambda s: not s["online"])
        player.mode = "ok"
        wait(lambda s: s["online"] and not s["error"])
        assert not player.calls
        print("PASS: QML observes automatic network recovery; no playback commands", flush=True)
        call("shell", "summon", "delormous.volumio", "{}")
        wait(lambda s: s["panelOpen"])
        call("shell", "hide", "delormous.volumio")
        wait(lambda s: not s["panelOpen"])
        print("PASS: panel opens and closes through official IPC", flush=True)
        run("omarchy", "plugin", "disable", PLUGIN)
        deadline = time.monotonic() + 5
        while pids() and time.monotonic() < deadline:
            time.sleep(.1)
        assert not pids(), pids()
        run("omarchy", "plugin", "enable", PLUGIN, "--section", section, "--index", str(index))
        wait(lambda s: s["backendPid"] > 0)
        call("delormous.volumio", "configure", original)
        wait(lambda s: s["online"] and s["address"] == original)
        assert len(pids()) == 1, pids()
        print("PASS: disable cleans up; enable starts one backend", flush=True)
    finally:
        try:
            restore_settings(saved)
        finally:
            player.shutdown()
            player.server_close()
    print("RESTORED:", saved, flush=True)


if __name__ == "__main__":
    main()
