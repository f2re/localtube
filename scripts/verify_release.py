#!/usr/bin/env python3
"""Verify the three LocalTube bootstrap distributions without installing them."""
from __future__ import annotations

import hashlib
import stat
import tarfile
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
version = (root / 'app/VERSION').read_text(encoding='utf-8').strip()
dist = root / 'dist'


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def verify_sidecar(path: Path) -> None:
    sidecar = path.with_name(path.name + '.sha256')
    assert sidecar.is_file(), sidecar
    expected = sidecar.read_text(encoding='utf-8').split()[0].lower()
    assert expected == sha256(path), f'archive SHA mismatch: {path.name}'


def verify_manifest(stage: Path) -> None:
    manifest = stage / 'MANIFEST.sha256'
    assert manifest.is_file(), manifest
    for raw in manifest.read_text(encoding='utf-8').splitlines():
        if not raw.strip():
            continue
        digest, rel = raw.strip().split(None, 1)
        rel = rel.lstrip('* ')
        target = stage / rel
        assert target.is_file(), f'manifest target missing: {rel}'
        assert sha256(target) == digest.lower(), f'manifest SHA mismatch: {rel}'


def fat_arches(path: Path) -> set[int]:
    data = path.read_bytes()[:4096]
    assert len(data) >= 8 and data[:4] == b'\xca\xfe\xba\xbe', f'not FAT Mach-O: {path}'
    nfat = int.from_bytes(data[4:8], 'big')
    assert 1 <= nfat <= 16, (path, nfat)
    arches: set[int] = set()
    offset = 8
    for _ in range(nfat):
        assert offset + 20 <= len(data), f'truncated FAT header: {path}'
        arches.add(int.from_bytes(data[offset:offset + 4], 'big'))
        offset += 20
    return arches


mac_stage = dist / f'LocalTube-macOS-v{version}'
mac_zip = dist / f'LocalTube-macOS-v{version}.zip'
assert mac_stage.is_dir() and mac_zip.is_file()
verify_manifest(mac_stage)
verify_sidecar(mac_zip)
with zipfile.ZipFile(mac_zip) as z:
    prefix = mac_stage.name + '/'
    required = [
        prefix + 'Install LocalTube.app/Contents/MacOS/InstallLocalTube',
        prefix + 'INSTALL.command',
        prefix + 'MANIFEST.sha256',
        prefix + 'payload/app/server.ts',
        prefix + 'app-template/LocalTube.app/Contents/MacOS/LocalTube',
    ]
    names = set(z.namelist())
    for name in required:
        assert name in names, name
    for name in required[:2] + required[-1:]:
        mode = z.getinfo(name).external_attr >> 16
        assert mode & stat.S_IXUSR, f'not executable in mac ZIP: {name}'

CPU_X86_64 = 0x01000007
CPU_ARM64 = 0x0100000C
for binary in [
    mac_stage / 'Install LocalTube.app/Contents/MacOS/InstallLocalTube',
    mac_stage / 'app-template/LocalTube.app/Contents/MacOS/LocalTube',
]:
    assert {CPU_X86_64, CPU_ARM64}.issubset(fat_arches(binary)), f'missing mac architectures: {binary}'


linux_stage = dist / f'LocalTube-Linux-v{version}'
linux_tar = dist / f'LocalTube-Linux-v{version}.tar.gz'
assert linux_stage.is_dir() and linux_tar.is_file()
verify_manifest(linux_stage)
verify_sidecar(linux_tar)
with tarfile.open(linux_tar, 'r:gz') as tf:
    names = {m.name: m for m in tf.getmembers()}
    prefix = linux_stage.name + '/'
    required = [
        prefix + 'INSTALL.sh',
        prefix + 'localtube',
        prefix + 'MANIFEST.sha256',
        prefix + 'payload/app/server.ts',
        prefix + 'payload/app/scripts/run_server.sh',
    ]
    for name in required:
        assert name in names, name
    for name in required[:2]:
        assert names[name].mode & stat.S_IXUSR, f'not executable in linux tar: {name}'


win_stage = dist / f'LocalTube-Windows-v{version}'
win_zip = dist / f'LocalTube-Windows-v{version}.zip'
assert win_stage.is_dir() and win_zip.is_file()
verify_manifest(win_stage)
verify_sidecar(win_zip)
with zipfile.ZipFile(win_zip) as z:
    prefix = win_stage.name + '/'
    names = set(z.namelist())
    required = [
        prefix + 'INSTALL.ps1',
        prefix + 'MANIFEST.sha256',
        prefix + 'payload/app/server.ts',
        prefix + 'payload/app/scripts/run_server.ps1',
        prefix + 'control/START.ps1',
        prefix + 'control/STOP.ps1',
        prefix + 'control/DIAGNOSE.ps1',
        prefix + 'control/UPDATE.ps1',
        prefix + 'control/UNINSTALL.ps1',
    ]
    for name in required:
        assert name in names, name

print('macOS/Linux/Windows release structures: OK')
