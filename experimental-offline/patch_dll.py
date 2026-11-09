#!/usr/bin/env python3
"""Build an experimental network-reduced copy of the exact DLL in this repo.

This patches the UPX unpacking stub, not the original compressed payload. It is
NOT a complete malware-removal tool. See README.md before using its output.
"""
from hashlib import sha256
from pathlib import Path
import struct
import sys

EXPECTED_SHA256 = 'e994f26cbb99a3a14a2f06c34890d7ee16457c4a4f7e25eb9b2cbaf2f482559a'
BASE = 0x474000
RAW = 0x400
HOOK = 0x4a9597
CAVE = 0x4a95d9
CAVE_END = 0x4a9600
ORIGINAL = bytes.fromhex('8b ae 6c e4 0a 00')


def offset(addr):
    return RAW + addr - BASE


def jump(src, dst):
    return b'\xe9' + struct.pack('<i', dst - (src + 5))


def patch(original):
    if sha256(original).hexdigest() != EXPECTED_SHA256:
        raise ValueError('Unsupported input: SHA-256 does not match the analyzed DLL')
    data = bytearray(original)
    if data[offset(HOOK):offset(HOOK)+len(ORIGINAL)] != ORIGINAL:
        raise ValueError('Unexpected unpacker instructions')
    cave_size = CAVE_END - CAVE
    if data[offset(CAVE):offset(CAVE_END)] != bytes(cave_size):
        raise ValueError('Expected code cave is not empty')

    # ESI points to the unpacked image at 0x401000 (or its rebased equivalent).
    # Abort the identified Indy HTTP GET wrapper and download-and-open routine.
    code = bytearray()
    for address in (0x466eac, 0x46a604):
        code += b'\xc6\x86' + struct.pack('<I', address - 0x401000) + b'\xc3'
    # Abort the POST wrapper; it must pop its one stack argument (ret 4).
    code += b'\xc7\x86' + struct.pack('<I', 0x466f04 - 0x401000) + b'\xc2\x04\x00\x00'
    # Preserve the instruction overwritten by the hook, then continue unpacking.
    code += ORIGINAL
    code += jump(CAVE + len(code), HOOK + len(ORIGINAL))
    if len(code) > cave_size:
        raise ValueError('Patch exceeds the code cave')
    data[offset(HOOK):offset(HOOK)+len(ORIGINAL)] = jump(HOOK, CAVE) + b'\x90'
    data[offset(CAVE):offset(CAVE)+len(code)] = code
    return bytes(data)


def main():
    root = Path(__file__).resolve().parent.parent
    src = root / 'Application.dll'
    dst = Path(__file__).resolve().parent / 'Application.dll'
    try:
        result = patch(src.read_bytes())
        dst.write_bytes(result)
    except (OSError, ValueError) as exc:
        print(f'Error: {exc}', file=sys.stderr)
        return 1
    print(f'Created: {dst}')
    print(f'SHA-256: {sha256(result).hexdigest()}')
    print('WARNING: experimental; not a verified safe or offline binary.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
