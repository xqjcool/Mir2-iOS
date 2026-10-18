"""Convert a classic 12/14-byte map to OpenMir2's 12-byte server layout.

The original client map remains unchanged. Only the two extended rendering
library selectors are omitted; collision, door and animation bytes are retained.
"""
from pathlib import Path
import argparse
import hashlib
import struct


def convert(raw):
    if len(raw) < 52:
        raise ValueError('Truncated map header')
    width, height = struct.unpack_from('<HH', raw)
    cells = width * height
    if not cells:
        raise ValueError('Empty map dimensions')
    stride, remainder = divmod(len(raw) - 52, cells)
    if remainder or stride not in (12, 14):
        raise ValueError('Unsupported cell layout')
    result = raw[:52] + b''.join(raw[i:i+12] for i in range(52, len(raw), stride))
    assert all(result[52+i*12:64+i*12] == raw[52+i*stride:64+i*stride] for i in range(cells))
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    if args.source.resolve() == args.output.resolve():
        parser.error('Use a separate output file to retain the original map')
    raw = args.source.read_bytes()
    result = convert(raw)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(result)
    print('sourceSHA256', hashlib.sha256(raw).hexdigest())
    print('serverSHA256', hashlib.sha256(result).hexdigest())
