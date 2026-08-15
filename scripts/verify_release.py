#!/usr/bin/env python3
import hashlib
import stat
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
version = (root / "app/VERSION").read_text(encoding="utf-8").strip()
zip_path = root / "dist" / f"LocalTube-macOS-v{version}.zip"
stage = root / "dist" / f"LocalTube-macOS-v{version}"
assert zip_path.is_file(), zip_path

with zipfile.ZipFile(zip_path) as archive:
    names = archive.namelist()
    prefix = f"LocalTube-macOS-v{version}/"
    required = [
        prefix + "Install LocalTube.app/Contents/MacOS/InstallLocalTube",
        prefix + "INSTALL.command",
        prefix + "MANIFEST.sha256",
        prefix + "payload/app/server.ts",
        prefix + "app-template/LocalTube.app/Contents/MacOS/LocalTube",
    ]
    for name in required:
        assert name in names, name
    for name in names:
        base = name.rsplit("/", 1)[-1]
        if base.endswith((".command", ".sh")):
            assert base.isascii(), f"non-ASCII executable filename: {base}"
    for name in required[:2] + required[-1:]:
        mode = archive.getinfo(name).external_attr >> 16
        assert mode & stat.S_IXUSR, f"not executable in ZIP: {name}"

# Validate MANIFEST.sha256 without depending on a platform-specific shasum binary.
manifest = stage / "MANIFEST.sha256"
for raw_line in manifest.read_text(encoding="utf-8").splitlines():
    line = raw_line.strip()
    if not line:
        continue
    digest, rel = line.split(None, 1)
    rel = rel.lstrip("* ")
    target = stage / rel
    assert target.is_file(), f"manifest target missing: {rel}"
    actual = hashlib.sha256(target.read_bytes()).hexdigest()
    assert actual == digest.lower(), f"SHA-256 mismatch: {rel}"

# Both native entry points must be universal Mach-O with x86_64 and arm64 slices.
def fat_arches(path: Path) -> set[int]:
    data = path.read_bytes()[:4096]
    assert len(data) >= 8 and data[:4] == b"\xca\xfe\xba\xbe", f"not a big-endian FAT Mach-O: {path}"
    nfat = int.from_bytes(data[4:8], "big")
    assert 1 <= nfat <= 16, (path, nfat)
    arches = set()
    offset = 8
    for _ in range(nfat):
        assert offset + 20 <= len(data), f"truncated FAT header: {path}"
        arches.add(int.from_bytes(data[offset:offset + 4], "big"))
        offset += 20
    return arches

CPU_X86_64 = 0x01000007
CPU_ARM64 = 0x0100000C
for binary in [
    stage / "Install LocalTube.app/Contents/MacOS/InstallLocalTube",
    stage / "app-template/LocalTube.app/Contents/MacOS/LocalTube",
]:
    arches = fat_arches(binary)
    assert {CPU_X86_64, CPU_ARM64}.issubset(arches), f"missing universal architectures in {binary}: {arches}"

print("release structure: OK")
