#!/usr/bin/env python3
"""SemVer ordering for release tags: 0.3.0-alpha.1 < 0.3.0-beta.1 < 0.3.0-rc.1 < 0.3.0 < 0.3.1.

Usage: semver.py newest [VERSION...]   prints the newest version (reads stdin when no arguments)
       semver.py is-newer OLD NEW      exits 0 when NEW is newer than OLD
"""
import sys

PRERELEASE_ORDER = {"alpha": 0, "beta": 1, "rc": 2}


def key(version):
    core, _, prerelease = version.removeprefix("v").partition("-")
    numbers = tuple(int(part) for part in core.split("."))
    if not prerelease:
        return numbers + (len(PRERELEASE_ORDER),)  # a final release sorts after its pre-releases
    kind, number = prerelease.split(".")
    return numbers + (PRERELEASE_ORDER[kind], int(number))


if __name__ == "__main__":
    command, *versions = sys.argv[1:]
    if command == "newest":
        versions = versions or [line.strip() for line in sys.stdin if line.strip()]
        print(max(versions, key=key) if versions else "")
    elif command == "is-newer":
        sys.exit(0 if key(versions[1]) > key(versions[0]) else 1)
    else:
        sys.exit(__doc__)
