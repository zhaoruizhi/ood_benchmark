#!/usr/bin/env python3
"""Recover cached wheel response bodies into an offline --find-links directory."""

import email
import os
import re
import sys
import tarfile
import zipfile
from pathlib import Path


def normalized_project(name: str) -> str:
    return re.sub(r"[-_.]+", "_", name)


def normalized_version(version: str) -> str:
    return re.sub(r"[^A-Za-z0-9.+!]", "_", version)


def zip_filename(path: Path) -> str | None:
    try:
        with zipfile.ZipFile(path) as archive:
            names = archive.namelist()
            metadata_names = [
                name for name in names if name.endswith(".dist-info/METADATA")
            ]
            wheel_names = [name for name in names if name.endswith(".dist-info/WHEEL")]
            if metadata_names and wheel_names:
                metadata = email.message_from_bytes(archive.read(metadata_names[0]))
                wheel = email.message_from_bytes(archive.read(wheel_names[0]))
                tags = wheel.get_all("Tag") or []
                if not tags:
                    return None
                selected_tag = next(
                    (tag for tag in tags if not tag.startswith("py2-")), tags[0]
                )
                python_tag, abi_tag, platform_tag = selected_tag.split("-", 2)
                return (
                    f"{normalized_project(metadata['Name'])}-"
                    f"{normalized_version(metadata['Version'])}-"
                    f"{python_tag}-{abi_tag}-{platform_tag}.whl"
                )
            pkg_info = next(name for name in names if name.endswith("/PKG-INFO"))
            metadata = email.message_from_bytes(archive.read(pkg_info))
            return (
                f"{normalized_project(metadata['Name'])}-"
                f"{normalized_version(metadata['Version'])}.zip"
            )
    except (StopIteration, zipfile.BadZipFile, OSError, KeyError):
        return None


def tar_filename(path: Path) -> str | None:
    try:
        with tarfile.open(path, mode="r:*") as archive:
            member = next(
                member for member in archive.getmembers() if member.name.endswith("/PKG-INFO")
            )
            handle = archive.extractfile(member)
            if handle is None:
                return None
            metadata = email.message_from_binary_file(handle)
    except (StopIteration, tarfile.TarError, OSError, KeyError):
        return None
    return (
        f"{normalized_project(metadata['Name'])}-"
        f"{normalized_version(metadata['Version'])}.tar.gz"
    )


def package_filename(path: Path) -> str | None:
    return zip_filename(path) or tar_filename(path)


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} PIP_CACHE_DIR WHEELHOUSE")
    cache = Path(sys.argv[1])
    wheelhouse = Path(sys.argv[2])
    wheelhouse.mkdir(parents=True, exist_ok=True)
    recovered = 0
    for body in cache.rglob("*.body"):
        filename = package_filename(body)
        if not filename:
            continue
        target = wheelhouse / filename
        if not target.exists():
            try:
                os.link(body, target)
            except OSError:
                target.write_bytes(body.read_bytes())
            recovered += 1
    print(f"recovered={recovered} wheelhouse={wheelhouse}")


if __name__ == "__main__":
    main()
