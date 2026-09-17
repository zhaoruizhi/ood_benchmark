#!/usr/bin/env python3
"""Build an EvalPlus wheel for the local vLLM-only benchmark profile.

EvalPlus imports the Google provider lazily, but 0.3.1 declares
google-generativeai as an unconditional dependency.  That dependency cannot
coexist with vLLM 0.8.5's OpenTelemetry/protobuf pins in the offline cache.
Remove only that unused provider dependency and regenerate wheel RECORD data.
"""

import argparse
import base64
import csv
import hashlib
import io
import zipfile
from pathlib import Path


GOOGLE_REQUIREMENT = b"Requires-Dist: google-generativeai "


def record_row(name: str, payload: bytes) -> list[str]:
    digest = base64.urlsafe_b64encode(hashlib.sha256(payload).digest()).rstrip(b"=")
    return [name, f"sha256={digest.decode()}", str(len(payload))]


def patch_wheel(source: Path, output_dir: Path) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    target = output_dir / source.name

    with zipfile.ZipFile(source) as archive:
        members = {
            info.filename: archive.read(info.filename)
            for info in archive.infolist()
            if not info.is_dir()
        }

    metadata_names = [name for name in members if name.endswith(".dist-info/METADATA")]
    record_names = [name for name in members if name.endswith(".dist-info/RECORD")]
    if len(metadata_names) != 1 or len(record_names) != 1:
        raise RuntimeError("expected exactly one METADATA and one RECORD file")

    metadata_name = metadata_names[0]
    lines = members[metadata_name].splitlines(keepends=True)
    filtered = [line for line in lines if not line.startswith(GOOGLE_REQUIREMENT)]
    if len(filtered) == len(lines):
        raise RuntimeError("google-generativeai requirement was not found")
    members[metadata_name] = b"".join(filtered)

    record_name = record_names[0]
    rows = [record_row(name, payload) for name, payload in sorted(members.items()) if name != record_name]
    rows.append([record_name, "", ""])
    record_buffer = io.StringIO(newline="")
    csv.writer(record_buffer, lineterminator="\n").writerows(rows)
    members[record_name] = record_buffer.getvalue().encode()

    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, payload in sorted(members.items()):
            archive.writestr(name, payload)
    return target


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()
    print(patch_wheel(args.source, args.output_dir))


if __name__ == "__main__":
    main()
