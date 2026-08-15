#!/usr/bin/env python3
"""Build the source-only LocalTube bootstrap distribution.

The release intentionally does not vendor Deno/yt-dlp/FFmpeg: INSTALL downloads
architecture-correct artifacts over HTTPS and verifies upstream SHA-256 values.
"""
from __future__ import annotations
import hashlib, json, os, shutil, stat, struct, subprocess, sys, tempfile, zipfile, zlib, binascii
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = (ROOT / 'app/VERSION').read_text().strip()
DIST = ROOT / 'dist'
PKG_NAME = f'LocalTube-macOS-v{VERSION}'
STAGE = DIST / PKG_NAME


def run(*args: str, env=None) -> None:
    subprocess.run(args, cwd=ROOT, env=env, check=True)


def write_plist(path: Path, bundle_id: str, executable: str, display: str) -> None:
    path.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n  <key>CFBundleDevelopmentRegion</key><string>ru</string>\n  <key>CFBundleDisplayName</key><string>{display}</string>\n  <key>CFBundleExecutable</key><string>{executable}</string>\n  <key>CFBundleIdentifier</key><string>{bundle_id}</string>\n  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>\n  <key>CFBundleName</key><string>{display}</string>\n  <key>CFBundlePackageType</key><string>APPL</string>\n  <key>CFBundleShortVersionString</key><string>{VERSION}</string>\n  <key>CFBundleVersion</key><string>{VERSION}</string>\n  <key>CFBundleIconFile</key><string>AppIcon</string>\n  <key>LSMinimumSystemVersion</key><string>11.0</string>\n  <key>LSUIElement</key><true/>\n  <key>NSHighResolutionCapable</key><true/>\n</dict>\n</plist>\n''')


def _png_chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', binascii.crc32(tag + data) & 0xffffffff)


def png_icon(size: int) -> bytes:
    """Create a small RGBA icon using only the Python standard library."""
    px = bytearray(size * size * 4)
    def put(x: int, y: int, c: tuple[int,int,int,int]) -> None:
        i=(y*size+x)*4; px[i:i+4]=bytes(c)
    def rounded(x: int,y: int,x0: int,y0: int,x1: int,y1: int,r: int) -> bool:
        if x0+r <= x <= x1-r or y0+r <= y <= y1-r: return x0 <= x <= x1 and y0 <= y <= y1
        cx=x0+r if x<x0+r else x1-r; cy=y0+r if y<y0+r else y1-r
        return (x-cx)*(x-cx)+(y-cy)*(y-cy) <= r*r
    pad=int(size*.07); outer_r=int(size*.24)
    ix0,iy0,ix1,iy1=int(size*.19),int(size*.28),int(size*.81),int(size*.72); inner_r=int(size*.11)
    ax,ay=int(size*.44),int(size*.39); bx,by=int(size*.44),int(size*.61); cx,cy=int(size*.62),int(size*.50)
    def tri(x,y):
        d=(by-cy)*(ax-cx)+(cx-bx)*(ay-cy)
        a=((by-cy)*(x-cx)+(cx-bx)*(y-cy))/d
        b=((cy-ay)*(x-cx)+(ax-cx)*(y-cy))/d
        c=1-a-b
        return a>=0 and b>=0 and c>=0
    for y in range(size):
        for x in range(size):
            c=(0,0,0,0)
            if rounded(x,y,pad,pad,size-pad-1,size-pad-1,outer_r): c=(26,28,34,255)
            if rounded(x,y,ix0,iy0,ix1,iy1,inner_r): c=(245,246,248,255)
            if tri(x,y): c=(26,28,34,255)
            put(x,y,c)
    raw=b''.join(b'\x00'+bytes(px[y*size*4:(y+1)*size*4]) for y in range(size))
    ihdr=struct.pack('>IIBBBBB',size,size,8,6,0,0,0)
    return b'\x89PNG\r\n\x1a\n'+_png_chunk(b'IHDR',ihdr)+_png_chunk(b'IDAT',zlib.compress(raw,9))+_png_chunk(b'IEND',b'')


def write_icns(path: Path) -> None:
    # Modern ICNS accepts PNG payloads in these chunks.
    chunks=[]
    for tag, size in [('ic07',128),('ic08',256),('ic09',512),('ic10',1024)]:
        payload=png_icon(size)
        chunks.append(tag.encode()+struct.pack('>I',len(payload)+8)+payload)
    body=b''.join(chunks)
    path.write_bytes(b'icns'+struct.pack('>I',len(body)+8)+body)


def build_universal(source: Path, out: Path) -> None:
    temp=Path(tempfile.mkdtemp(prefix='localtube-go-'))
    try:
        bins=[]
        for arch in ('amd64','arm64'):
            target=temp/arch
            env=os.environ.copy(); env.update({'GOOS':'darwin','GOARCH':arch,'CGO_ENABLED':'0'})
            subprocess.run(['go','build','-trimpath','-ldflags=-s -w', '-o',str(target),str(source)], cwd=ROOT, env=env, check=True)
            bins.append(target)
        run(sys.executable, 'scripts/make_fat_macho.py', str(bins[0]), str(bins[1]), str(out))
        out.chmod(0o755)
    finally:
        shutil.rmtree(temp, ignore_errors=True)


def app_bundle(path: Path, source: Path, bundle_id: str, display: str, executable: str) -> None:
    macos=path/'Contents/MacOS'; resources=path/'Contents/Resources'
    macos.mkdir(parents=True, exist_ok=True); resources.mkdir(parents=True, exist_ok=True)
    write_plist(path/'Contents/Info.plist', bundle_id, executable, display)
    build_universal(source, macos/executable)
    write_icns(resources/'AppIcon.icns')
    if sys.platform == 'darwin':
        subprocess.run(['/usr/bin/codesign','--force','--deep','--sign','-','--timestamp=none',str(path)], check=True)


def copy_exec(src: Path, dst: Path, mode=0o755) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(src,dst); dst.chmod(mode)


def main() -> None:
    shutil.rmtree(DIST, ignore_errors=True); STAGE.mkdir(parents=True)
    # Payload and control scripts.
    shutil.copytree(ROOT/'app', STAGE/'payload/app')
    shutil.copytree(ROOT/'control', STAGE/'control')
    shutil.copytree(ROOT/'installer', STAGE/'installer')
    copy_exec(ROOT/'INSTALL.command', STAGE/'INSTALL.command')
    for p in (STAGE/'payload/app/scripts').glob('*.sh'): p.chmod(0o755)
    for p in (STAGE/'control').glob('*.command'): p.chmod(0o755)
    (STAGE/'installer/install.sh').chmod(0o755)

    app_bundle(STAGE/'Install LocalTube.app', ROOT/'native/installer_launcher.go', 'ru.localtube.installer', 'Install LocalTube', 'InstallLocalTube')
    app_bundle(STAGE/'app-template/LocalTube.app', ROOT/'native/app_launcher.go', 'ru.localtube.app', 'LocalTube', 'LocalTube')

    readme = f'''LocalTube {VERSION} for macOS\n\nRECOMMENDED INSTALLATION\n1. Double-click “Install LocalTube.app”.\n2. The installer does NOT start Terminal and does NOT read zsh/.zshrc/Oh-My-Zsh.\n3. Runtime components are downloaded for your CPU and SHA-256 verified.\n\nFALLBACK\nINSTALL.command is provided only for diagnostics/manual installation. If you run it from zsh, use:\n  ./INSTALL.command\nor an absolute path beginning with /Users/…\n\nRequirements: macOS 11+; Apple Silicon or Intel; Internet connection during first install.\nProject: https://github.com/f2re/localtube\n'''
    (STAGE/'README.txt').write_text(readme)

    # Internal corruption manifest. It intentionally excludes itself.
    lines=[]
    for p in sorted(x for x in STAGE.rglob('*') if x.is_file() and x.name != 'MANIFEST.sha256'):
        rel=p.relative_to(STAGE).as_posix(); digest=hashlib.sha256(p.read_bytes()).hexdigest(); lines.append(f'{digest}  {rel}')
    (STAGE/'MANIFEST.sha256').write_text('\n'.join(lines)+'\n')

    # ZIP with executable mode preservation and UTF-8-safe (ASCII executable names) paths.
    zip_path=DIST/f'{PKG_NAME}.zip'
    with zipfile.ZipFile(zip_path,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for p in sorted(STAGE.rglob('*')):
            rel=(Path(PKG_NAME)/p.relative_to(STAGE)).as_posix()
            if p.is_dir():
                zi=zipfile.ZipInfo(rel.rstrip('/')+'/'); zi.external_attr=(0o40755<<16)|0x10; z.writestr(zi,b'')
            else:
                zi=zipfile.ZipInfo.from_file(p, rel); zi.compress_type=zipfile.ZIP_DEFLATED; z.writestr(zi,p.read_bytes())
    sha=hashlib.sha256(zip_path.read_bytes()).hexdigest()
    (DIST/f'{PKG_NAME}.zip.sha256').write_text(f'{sha}  {zip_path.name}\n')
    print(zip_path)
    print('sha256', sha)

if __name__=='__main__': main()
