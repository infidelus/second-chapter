#!/usr/bin/env python3
"""
Second Chapter: show or add to the kernel start-up settings (the "command
line") stored inside an Android boot image, without changing anything else.

Usage:
    python3 bootimg-cmdline.py show  boot.img
    python3 bootimg-cmdline.py add   boot.img new-boot.img "printk.devkmsg=on"

The original file is never changed; "add" writes a new copy. Works with boot
image header versions 0 to 4. Settings already present are not added twice.
"""

import struct
import sys

MAGIC = b"ANDROID!"

# Where the command line lives in each header version: (offset, size) of the
# main field, and (offset, size) of the extra field, if any.
LAYOUTS = {
    0: ((64, 512), (608, 1024)),
    1: ((64, 512), (608, 1024)),
    2: ((64, 512), (608, 1024)),
    3: ((44, 1536), None),
    4: ((44, 1536), None),
}


def read_cmdline(data):
    if data[:8] != MAGIC:
        sys.exit("Error: not an Android boot image (no ANDROID! at the start)")
    version = struct.unpack_from("<I", data, 40)[0]
    if version not in LAYOUTS:
        sys.exit(f"Error: unsupported boot image header version {version}")
    (main_off, main_size), extra = LAYOUTS[version]
    main = data[main_off:main_off + main_size].split(b"\0", 1)[0]
    extra_text = b""
    if extra:
        extra_off, extra_size = extra
        extra_text = data[extra_off:extra_off + extra_size].split(b"\0", 1)[0]
    return version, main.decode("ascii", "replace"), extra_text.decode("ascii", "replace")


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("show", "add"):
        sys.exit(__doc__)
    with open(sys.argv[2], "rb") as f:
        data = bytearray(f.read())
    version, main_text, extra_text = read_cmdline(data)

    if sys.argv[1] == "show":
        print(f"Header version: {version}")
        print(f"Command line: {main_text!r}")
        if extra_text:
            print(f"Extra command line: {extra_text!r}")
        return

    if len(sys.argv) != 5:
        sys.exit(__doc__)
    out_path, wanted = sys.argv[3], sys.argv[4].split()
    present = (main_text + " " + extra_text).split()
    to_add = [w for w in wanted if w not in present]
    if not to_add:
        print("Nothing to add: those settings are already there.")
    new_text = " ".join(main_text.split() + to_add)

    (main_off, main_size), extra = LAYOUTS[version]
    encoded = new_text.encode("ascii")
    if len(encoded) >= main_size:
        sys.exit("Error: the command line would be too long for this header")
    data[main_off:main_off + main_size] = encoded + b"\0" * (main_size - len(encoded))

    with open(out_path, "wb") as f:
        f.write(data)
    print(f"Header version: {version}")
    print(f"Old command line: {main_text!r}")
    print(f"New command line: {new_text!r}")
    print(f"Written to {out_path}")


if __name__ == "__main__":
    main()
