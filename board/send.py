#!/usr/bin/env python3
"""Send a kernel to a running cancho-os over its serial console (docs/load.md).

    python3 board/send.py /dev/ttyAMA0 build/kernel8.img

The machine this runs on is the one wired to the board's console. It types `load <bytes>`, sends the
file, compares the checksum the kernel says with its own (zlib's Adler-32), and types `go <checksum>`
only if they agree. Needs pyserial. Not part of the kernel: a tool for whoever holds the console.
"""
import sys, time, zlib, re
import serial


def read_until(port, pattern, seconds):
    got = b""
    end = time.time() + seconds
    while time.time() < end:
        got += port.read(4096)
        found = re.search(pattern, got)
        if found:
            return got, found
    return got, None


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    image = open(sys.argv[2], "rb").read()
    ours = "%08x" % zlib.adler32(image)
    port = serial.Serial(sys.argv[1], 115200, timeout=0.1)
    port.write(b"\r")
    read_until(port, rb"$^", 0.5)
    port.write(b"load %d\r" % len(image))
    got, found = read_until(port, rb"send \d+ bytes", 3)
    if not found:
        sys.exit("the kernel did not say `send`: %r" % got[-200:])
    started = time.time()
    port.write(image)
    port.flush()
    got, found = read_until(port, rb"adler32 ([0-9a-f]{8})|nothing loaded[^\r]*", 30 + len(image) / 5000)
    if not found or not found.group(1):
        sys.exit("not received: %r" % got[-200:])
    theirs = found.group(1).decode()
    print("sent %d bytes in %.1f s; checksum ours %s, the kernel's %s" % (len(image), time.time() - started, ours, theirs))
    if theirs != ours:
        port.write(b"no\r")
        sys.exit("the checksums differ: not started")
    port.write(b"go %s\r" % ours.encode())
    got, _ = read_until(port, rb"> $", 8)
    sys.stdout.write(got.decode("latin-1").replace("\r", ""))
    print()


main()
