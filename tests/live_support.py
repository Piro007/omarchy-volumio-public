"""Bounded official IPC and settings restoration for opt-in live tests."""
import json
import subprocess
import time
from dataclasses import dataclass

PLUGIN = "delormous.volumio"


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=5).stdout.strip()


def call(*args):
    return run("omarchy-shell", *args)


def status():
    return json.loads(call(PLUGIN, "status"))


def wait(check, timeout=12):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        try:
            last = status()
            if check(last):
                return last
        except (subprocess.SubprocessError, ValueError) as error:
            last = str(error)
        time.sleep(.2)
    raise AssertionError(last)


def entries():
    config = json.loads(call("shell", "listShellConfig"))
    return [(section, index, entry) for section, items in config["bar"]["layout"].items()
            for index, entry in enumerate(items) if entry.get("id") == PLUGIN]


@dataclass
class Settings:
    section: str
    index: int
    address: str
    icon: str


def capture_settings():
    found = entries()
    if len(found) != 1:
        raise AssertionError(found)
    section, index, entry = found[0]
    return Settings(section, index, entry.get("address", "http://volumio.local"),
                    entry.get("barIcon", "cover"))


def restore_settings(saved):
    # A timed-out disable/enable may still have changed the actual layout.
    found = entries()
    commands = []
    if not found:
        commands.append(("omarchy", "plugin", "enable", PLUGIN, "--section", saved.section, "--index", str(saved.index)))
    elif (found[0][0], found[0][1]) != (saved.section, saved.index):
        commands.append(("omarchy", "bar", "move", PLUGIN, "--section", saved.section, "--index", str(saved.index)))
    commands.extend((
        ("omarchy", "bar", "set", PLUGIN, "address", saved.address),
        ("omarchy", "bar", "set", PLUGIN, "barIcon", saved.icon),
    ))
    errors = []
    for command in commands:
        try:
            run(*command)
        except (subprocess.SubprocessError, OSError) as error:
            # Attempt independent restoration steps once, never replay a timeout.
            errors.append(str(error))
    if errors:
        raise RuntimeError("Could not fully restore plugin settings: " + "; ".join(errors))
    wait(lambda s: s["address"].rstrip("/") == saved.address.rstrip("/") and s["iconMode"] == saved.icon)
    restored = capture_settings()
    if restored != saved:
        raise AssertionError((restored, saved))
