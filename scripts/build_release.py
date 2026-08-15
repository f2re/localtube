#!/usr/bin/env python3
"""Build LocalTube bootstrap packages for macOS, Linux and Windows.

The bootstrap archives intentionally do not vendor Deno, yt-dlp or FFmpeg.
Installers download architecture-correct upstream binaries over HTTPS, verify
SHA-256, and keep the runtime private to LocalTube.
"""
from __future__ import annotations

import binascii
import hashlib
import os
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import zipfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = (ROOT / 'app/VERSION').read_text(encoding='utf-8').strip()
DIST = ROOT / 'dist'


def run(*args: str, env=None) -> None:
    subprocess.run(args, cwd=ROOT, env=env, check=True)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def write_sidecar(path: Path) -> None:
    path.with_name(path.name + '.sha256').write_text(
        f'{sha256_file(path)}  {path.name}\n', encoding='utf-8'
    )


def copy_exec(src: Path, dst: Path, mode: int = 0o755) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    dst.chmod(mode)


def write_manifest(stage: Path) -> None:
    lines: list[str] = []
    for p in sorted(x for x in stage.rglob('*') if x.is_file() and x.name != 'MANIFEST.sha256'):
        rel = p.relative_to(stage).as_posix()
        lines.append(f'{sha256_file(p)}  {rel}')
    (stage / 'MANIFEST.sha256').write_text('\n'.join(lines) + '\n', encoding='utf-8')


def _png_chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack('>I', len(data)) + tag + data + struct.pack(
        '>I', binascii.crc32(tag + data) & 0xFFFFFFFF
    )


def png_icon(size: int) -> bytes:
    px = bytearray(size * size * 4)

    def put(x: int, y: int, c: tuple[int, int, int, int]) -> None:
        i = (y * size + x) * 4
        px[i:i + 4] = bytes(c)

    def rounded(x: int, y: int, x0: int, y0: int, x1: int, y1: int, r: int) -> bool:
        if x0 + r <= x <= x1 - r or y0 + r <= y <= y1 - r:
            return x0 <= x <= x1 and y0 <= y <= y1
        cx = x0 + r if x < x0 + r else x1 - r
        cy = y0 + r if y < y0 + r else y1 - r
        return (x - cx) ** 2 + (y - cy) ** 2 <= r * r

    pad = int(size * .07)
    outer_r = int(size * .24)
    ix0, iy0, ix1, iy1 = int(size * .19), int(size * .28), int(size * .81), int(size * .72)
    inner_r = int(size * .11)
    ax, ay = int(size * .44), int(size * .39)
    bx, by = int(size * .44), int(size * .61)
    cx, cy = int(size * .62), int(size * .50)

    def tri(x: int, y: int) -> bool:
        d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        a = ((by - cy) * (x - cx) + (cx - bx) * (y - cy)) / d
        b = ((cy - ay) * (x - cx) + (ax - cx) * (y - cy)) / d
        c = 1 - a - b
        return a >= 0 and b >= 0 and c >= 0

    for y in range(size):
        for x in range(size):
            color = (0, 0, 0, 0)
            if rounded(x, y, pad, pad, size - pad - 1, size - pad - 1, outer_r):
                color = (26, 28, 34, 255)
            if rounded(x, y, ix0, iy0, ix1, iy1, inner_r):
                color = (245, 246, 248, 255)
            if tri(x, y):
                color = (26, 28, 34, 255)
            put(x, y, color)

    raw = b''.join(b'\x00' + bytes(px[y * size * 4:(y + 1) * size * 4]) for y in range(size))
    ihdr = struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0)
    return (
        b'\x89PNG\r\n\x1a\n'
        + _png_chunk(b'IHDR', ihdr)
        + _png_chunk(b'IDAT', zlib.compress(raw, 9))
        + _png_chunk(b'IEND', b'')
    )


def write_icns(path: Path) -> None:
    chunks = []
    for tag, size in [('ic07', 128), ('ic08', 256), ('ic09', 512), ('ic10', 1024)]:
        payload = png_icon(size)
        chunks.append(tag.encode() + struct.pack('>I', len(payload) + 8) + payload)
    body = b''.join(chunks)
    path.write_bytes(b'icns' + struct.pack('>I', len(body) + 8) + body)


def write_plist(path: Path, bundle_id: str, executable: str, display: str) -> None:
    path.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>ru</string>
  <key>CFBundleDisplayName</key><string>{display}</string>
  <key>CFBundleExecutable</key><string>{executable}</string>
  <key>CFBundleIdentifier</key><string>{bundle_id}</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>{display}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>{VERSION}</string>
  <key>CFBundleVersion</key><string>{VERSION}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
''', encoding='utf-8')


def build_universal(source: Path, out: Path) -> None:
    temp = Path(tempfile.mkdtemp(prefix='localtube-go-'))
    try:
        bins: list[Path] = []
        for arch in ('amd64', 'arm64'):
            target = temp / arch
            env = os.environ.copy()
            env.update({'GOOS': 'darwin', 'GOARCH': arch, 'CGO_ENABLED': '0'})
            subprocess.run(
                ['go', 'build', '-trimpath', '-ldflags=-s -w', '-o', str(target), str(source)],
                cwd=ROOT, env=env, check=True,
            )
            bins.append(target)
        run(sys.executable, 'scripts/make_fat_macho.py', str(bins[0]), str(bins[1]), str(out))
        out.chmod(0o755)
    finally:
        shutil.rmtree(temp, ignore_errors=True)


def app_bundle(path: Path, source: Path, bundle_id: str, display: str, executable: str) -> None:
    macos = path / 'Contents/MacOS'
    resources = path / 'Contents/Resources'
    macos.mkdir(parents=True, exist_ok=True)
    resources.mkdir(parents=True, exist_ok=True)
    write_plist(path / 'Contents/Info.plist', bundle_id, executable, display)
    build_universal(source, macos / executable)
    write_icns(resources / 'AppIcon.icns')
    if sys.platform == 'darwin':
        subprocess.run(
            ['/usr/bin/codesign', '--force', '--deep', '--sign', '-', '--timestamp=none', str(path)],
            check=True,
        )


def write_zip(stage: Path, archive: Path) -> None:
    prefix = stage.name
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for p in sorted(stage.rglob('*')):
            rel = (Path(prefix) / p.relative_to(stage)).as_posix()
            if p.is_dir():
                zi = zipfile.ZipInfo(rel.rstrip('/') + '/')
                zi.external_attr = (0o40755 << 16) | 0x10
                z.writestr(zi, b'')
            else:
                zi = zipfile.ZipInfo.from_file(p, rel)
                zi.compress_type = zipfile.ZIP_DEFLATED
                z.writestr(zi, p.read_bytes())


def write_tar(stage: Path, archive: Path) -> None:
    with tarfile.open(archive, 'w:gz', compresslevel=9) as tf:
        tf.add(stage, arcname=stage.name)


def common_payload(stage: Path) -> None:
    shutil.copytree(ROOT / 'app', stage / 'payload/app')
    for p in (stage / 'payload/app/scripts').glob('*.sh'):
        p.chmod(0o755)


def build_macos() -> Path:
    stage = DIST / f'LocalTube-macOS-v{VERSION}'
    stage.mkdir(parents=True)
    common_payload(stage)
    shutil.copytree(ROOT / 'control', stage / 'control')
    shutil.copytree(ROOT / 'installer', stage / 'installer')
    copy_exec(ROOT / 'INSTALL.command', stage / 'INSTALL.command')
    for p in stage.rglob('*.command'):
        p.chmod(0o755)
    for p in stage.rglob('*.sh'):
        p.chmod(0o755)
    app_bundle(
        stage / 'Install LocalTube.app',
        ROOT / 'native/installer_launcher.go',
        'ru.localtube.installer', 'Install LocalTube', 'InstallLocalTube',
    )
    app_bundle(
        stage / 'app-template/LocalTube.app',
        ROOT / 'native/app_launcher.go',
        'ru.localtube.app', 'LocalTube', 'LocalTube',
    )
    (stage / 'README.txt').write_text(
        f'''LocalTube {VERSION} — macOS

1. Запустите “Install LocalTube.app”.
2. Установщик скачает Deno, yt-dlp, FFmpeg/FFprobe для вашего CPU и проверит SHA-256.
3. После установки запускайте ~/Applications/LocalTube.app.

Требования: macOS 11+, Apple Silicon или Intel, интернет при первой установке.
Резервный INSTALL.command предназначен для ручной диагностики.

https://github.com/f2re/localtube
''', encoding='utf-8',
    )
    write_manifest(stage)
    archive = DIST / f'{stage.name}.zip'
    write_zip(stage, archive)
    write_sidecar(archive)
    return archive


def build_linux() -> Path:
    stage = DIST / f'LocalTube-Linux-v{VERSION}'
    stage.mkdir(parents=True)
    common_payload(stage)
    copy_exec(ROOT / 'installer/install-linux.sh', stage / 'INSTALL.sh')
    copy_exec(ROOT / 'control/linux/localtube', stage / 'localtube')
    (stage / 'README.txt').write_text(
        f'''LocalTube {VERSION} — Linux

1. Распакуйте архив.
2. Выполните: ./INSTALL.sh
3. Запускайте командой: localtube
   либо через пункт LocalTube в меню приложений.

Установка выполняется в профиль пользователя без sudo.
Поддерживаются x86_64 и arm64/aarch64. Для нативного выбора папки
рекомендуется zenity или kdialog.

https://github.com/f2re/localtube
''', encoding='utf-8',
    )
    write_manifest(stage)
    archive = DIST / f'{stage.name}.tar.gz'
    write_tar(stage, archive)
    write_sidecar(archive)
    return archive


def build_windows() -> Path:
    stage = DIST / f'LocalTube-Windows-v{VERSION}'
    stage.mkdir(parents=True)
    common_payload(stage)
    shutil.copy2(ROOT / 'installer/install-windows.ps1', stage / 'INSTALL.ps1')
    shutil.copytree(ROOT / 'control/windows', stage / 'control')
    (stage / 'README.txt').write_text(
        f'''LocalTube {VERSION} — Windows

1. Распакуйте ZIP в обычную папку.
2. Правый клик INSTALL.ps1 → Run with PowerShell.
   Если PowerShell блокирует локальный скрипт:
     powershell -NoProfile -ExecutionPolicy Bypass -File ./INSTALL.ps1
3. После установки используйте LocalTube из меню Пуск.

Установка выполняется в %LOCALAPPDATA%/LocalTube без прав администратора.
Поддерживаются Windows 10/11, x64 и ARM64.

https://github.com/f2re/localtube
''', encoding='utf-8',
    )
    write_manifest(stage)
    archive = DIST / f'{stage.name}.zip'
    write_zip(stage, archive)
    write_sidecar(archive)
    return archive


def main() -> None:
    shutil.rmtree(DIST, ignore_errors=True)
    DIST.mkdir(parents=True)
    archives = [build_macos(), build_linux(), build_windows()]
    for archive in archives:
        print(archive)
        print('sha256', sha256_file(archive))


if __name__ == '__main__':
    main()
