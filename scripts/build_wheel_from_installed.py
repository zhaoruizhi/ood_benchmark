#!/usr/bin/env python3
"""Repack selected installed distributions into an offline wheelhouse."""

import email
import re
import sys
import zipfile
from importlib.metadata import distribution
from pathlib import Path, PurePosixPath


def normalize_name(value: str) -> str:
    return re.sub(r"[-_.]+", "_", value)


def normalize_version(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9.+!]", "_", value)


def repack(name: str, wheelhouse: Path) -> Path:
    dist = distribution(name)
    wheel_text = dist.read_text("WHEEL")
    if wheel_text is None:
        raise RuntimeError(f"{name} has no WHEEL metadata")
    wheel = email.message_from_string(wheel_text)
    tags = wheel.get_all("Tag") or []
    if not tags:
        raise RuntimeError(f"{name} has no wheel tag")
    selected_tag = next((tag for tag in tags if not tag.startswith("py2-")), tags[0])
    python_tag, abi_tag, platform_tag = selected_tag.split("-", 2)
    target = wheelhouse / (
        f"{normalize_name(dist.metadata['Name'])}-"
        f"{normalize_version(dist.version)}-{python_tag}-{abi_tag}-{platform_tag}.whl"
    )
    root = Path(dist.locate_file("")).resolve()
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for relative in dist.files or []:
            posix = PurePosixPath(str(relative))
            if ".." in posix.parts:
                continue
            source = Path(dist.locate_file(relative))
            if source.is_file() and source.resolve().is_relative_to(root):
                archive.write(source, str(posix))
    return target


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit(f"usage: {sys.argv[0]} WHEELHOUSE PACKAGE [PACKAGE ...]")
    wheelhouse = Path(sys.argv[1])
    wheelhouse.mkdir(parents=True, exist_ok=True)
    for name in sys.argv[2:]:
        print(repack(name, wheelhouse))


if __name__ == "__main__":
    main()
