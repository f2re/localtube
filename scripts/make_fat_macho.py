#!/usr/bin/env python3
import struct, sys
from pathlib import Path

def read_arch(path):
    b=Path(path).read_bytes()
    if len(b)<32 or b[:4] not in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf'):
        raise SystemExit(f'not a Mach-O 64 binary: {path}')
    little=b[:4]==b'\xcf\xfa\xed\xfe'
    endian='<' if little else '>'
    cputype, cpusub=struct.unpack_from(endian+'ii', b, 4)
    return b,cputype,cpusub

def align_up(n,a): return (n+a-1)//a*a

if len(sys.argv)!=4:
    raise SystemExit('usage: make_fat_macho.py amd64 arm64 output')
parts=[]
for p in sys.argv[1:3]: parts.append(read_arch(p))
ALIGN_EXP=14; ALIGN=1<<ALIGN_EXP
header_size=8+20*len(parts)
offset=align_up(header_size, ALIGN)
entries=[]
for b,cpu,sub in parts:
    entries.append((cpu,sub,offset,len(b),ALIGN_EXP))
    offset=align_up(offset+len(b), ALIGN)
out=bytearray()
out += struct.pack('>II', 0xcafebabe, len(parts))
for e in entries: out += struct.pack('>iiIII', *e)
for (b,_,_),e in zip(parts,entries):
    if len(out)<e[2]: out += b'\0'*(e[2]-len(out))
    out += b
Path(sys.argv[3]).write_bytes(out)
