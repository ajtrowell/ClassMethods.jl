#!/usr/bin/env python3
"""Resolve the vendored Julia binary path for a provisioned project.

Usage:
    resolve_vendored_julia.py /path/to/project

Prints the absolute path to the Julia executable that was installed via Juliaup
for the project-local depot. Exits with a non-zero status if the metadata is
missing or the toolchain cannot be found.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


def resolve_julia_binary(project_root: Path) -> Path:
    """Return the absolute path to the vendored Julia binary."""
    metadata_candidates = [
        project_root / ".juliaup" / "juliaup.json",
        project_root / ".juliaup" / "juliaup" / "juliaup.json",
    ]
    metadata_path = next((p for p in metadata_candidates if p.is_file()), None)
    if metadata_path is None:
        raise RuntimeError(
            f"Juliaup metadata not found under {project_root / '.juliaup'}"
        )

    toolchain_root = project_root / ".julia" / "juliaup"
    if not toolchain_root.is_dir():
        raise RuntimeError(
            f"Julia toolchains not found at {toolchain_root}; "
            "ensure the shared depot has been refreshed."
        )

    data = json.loads(metadata_path.read_text())

    version = None
    default_channel = data.get("Default")
    if default_channel:
        version = (
            data.get("InstalledChannels", {})
            .get(default_channel, {})
            .get("Version")
        )

    if version is None:
        installed = data.get("InstalledVersions") or {}
        if installed:
            version = next(iter(installed.keys()))

    if version is None:
        raise RuntimeError(
            f"No installed Julia versions recorded in {metadata_path}"
        )

    entry = (
        data.get("InstalledVersions", {})
        .get(version, {})
        .get("Path")
    )
    if not entry:
        raise RuntimeError(
            f"Toolchain path missing for Julia version {version} in {metadata_path}"
        )

    entry_path = Path(entry)
    if not entry_path.is_absolute():
        entry_path = (toolchain_root / entry_path).resolve()

    binary = entry_path / "bin" / "julia"
    if not binary.exists():
        raise RuntimeError(f"Julia binary not found at {binary}")

    return binary


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(
            "Usage: resolve_vendored_julia.py /path/to/project",
            file=sys.stderr,
        )
        return 2

    project_root = Path(argv[1]).resolve()
    try:
        binary = resolve_julia_binary(project_root)
    except RuntimeError as err:
        print(f"{err}", file=sys.stderr)
        return 1

    print(binary)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
