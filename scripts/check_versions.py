"""Fail when release metadata disagrees; never update the lockfile implicitly."""
import json
from pathlib import Path
import tomllib


def check_versions(root):
    manifest = json.loads((root / "manifest.json").read_text())["version"]
    package = tomllib.loads((root / "Cargo.toml").read_text())["package"]
    lock = tomllib.loads((root / "Cargo.lock").read_text())
    locked = [item["version"] for item in lock["package"] if item["name"] == package["name"]]
    if manifest != package["version"] or locked != [manifest]:
        raise ValueError(f"Release versions disagree: manifest={manifest}, Cargo={package['version']}, lock={locked}")
    return manifest


if __name__ == "__main__":
    print("Release metadata:", check_versions(Path(__file__).resolve().parent.parent))
