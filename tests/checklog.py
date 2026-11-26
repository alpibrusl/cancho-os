#!/usr/bin/env python3
"""The record (LOG.TXT, docs/permissions.md) checked by a second implementation.

    checklog.py LOG.TXT [directory the volume's files were copied to]

Every line must end with the SHA-256 of the chain before it and its own text, and be numbered in order.
With a directory, the last write or copy of each name that is still there must be what the file holds.
Prints the lines, shortened; exit 0 if every line follows, 1 if one does not."""
import hashlib
import os
import sys

data = open(sys.argv[1], "rb").read().decode("latin-1")
prev, n, bad = "0" * 64, 0, 0
if data and not data.endswith("\n"):
    print("the last line is not finished")
    bad += 1
lines = data.splitlines()
for line in lines:
    n += 1
    body, _, chain = line.rpartition(" ")
    f = body.split(" ")
    ok = hashlib.sha256((prev + body + " ").encode("latin-1")).hexdigest() == chain and len(f) == 10 and f[0] == str(n)
    if not ok:
        bad += 1
        print("line", n, "does not follow")
    prev = chain
    print(" ".join(f[:9]), (f[9] if len(f) > 9 else "")[:12], chain[:12])
print(f"{n} lines, {bad} that do not follow")
if len(sys.argv) > 2:
    there = {name.upper(): os.path.join(sys.argv[2], name) for name in os.listdir(sys.argv[2])}
    last = {}
    for line in lines:
        f = line.split(" ")
        if len(f) != 11:
            continue
        if f[4] in ("write", "copy", "put"):
            last[f[5].upper()] = f[9]
        if f[4] in ("append", "remove"):
            last.pop(f[5].upper(), None)
    for name, digest in sorted(last.items()):
        if name in there:
            same = hashlib.sha256(open(there[name], "rb").read()).hexdigest() == digest
            print(name, "holds what the record says" if same else "DOES NOT hold what the record says")
            bad += 0 if same else 1
sys.exit(1 if bad else 0)
