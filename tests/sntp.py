#!/usr/bin/env python3
"""A machine that says what time it is, for the kernel's `net time` (docs/clock.md): SNTP, RFC 4330, on UDP.

    sntp.py <port> [seconds since 1970 | now] [how]

Answers every question with the time given (this machine's own with `now` or nothing). `how` makes it answer
wrongly, to see the kernel refuse: `stale` gives back another question's number, `client` answers as a client
would, `unsynchronised` says it does not have the time itself. Runs until it is stopped."""
import socket
import struct
import sys
import time

port = int(sys.argv[1])
fixed = None if len(sys.argv) < 3 or sys.argv[2] == "now" else int(sys.argv[2])
how = sys.argv[3] if len(sys.argv) > 3 else ""
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("0.0.0.0", port))
while True:
    q, who = s.recvfrom(512)
    if len(q) < 48:
        continue
    unix = time.time() if fixed is None else fixed
    secs = (int(unix) + 2208988800) & 0xffffffff
    origin = q[40:48]
    if how == "stale":
        origin = bytes(8)
    first = 0x23 if how == "client" else 0x24
    stratum = 0 if how == "unsynchronised" else 2
    a = struct.pack("!BBbb", first, stratum, 4, -20) + bytes(8) + b"LOCL" + struct.pack("!II", secs, 0) + origin
    a += struct.pack("!II", secs, 0) + struct.pack("!II", secs, 0)
    s.sendto(a, who)
