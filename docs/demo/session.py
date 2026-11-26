#!/usr/bin/env python3
"""A real SSH session to cancho-os on a Raspberry Pi 4, typed at a human pace, for the recording.
What the kernel answers is whatever it answers; only the typing is scripted. The ssh options that skip the
host-key question (the kernel's key is new at every start) are passed and not shown."""
import os, pty, select, sys, time

HOST = sys.argv[1]
SHOWN = "ssh cancho@" + HOST
LINES = ["about", "uptime", "mem", "random", "ping example.com", "lookup example.com", "arm zero", "disk", "exit"]

def out(b):
    os.write(1, b)

def typed(text, each=0.055):
    for ch in text:
        out(ch.encode())
        time.sleep(each)

out(b"\x1b[2m# a Mac, and on the same network a Raspberry Pi 4 running cancho-os\x1b[0m\r\n")
time.sleep(1.2)
out(b"$ ")
typed(SHOWN, 0.06)
time.sleep(0.5)
out(b"\r\n")

pid, fd = pty.fork()
if pid == 0:
    os.execvp("ssh", ["ssh", "-tt", "-i", os.path.expanduser("~/.ssh/id_ed25519"), "-o", "IdentitiesOnly=yes",
                      "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", "-o", "LogLevel=ERROR",
                      "cancho@" + HOST])

def pump(seconds):
    end = time.time() + seconds
    alive = True
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                data = os.read(fd, 4096)
            except OSError:
                return False
            if not data:
                return False
            out(data)
    return alive

pump(2.5)
for line in LINES:
    for ch in line:
        os.write(fd, ch.encode())
        pump(0.07)
    pump(0.45)
    os.write(fd, b"\r")
    if not pump(3.2 if line.startswith(("ping", "lookup", "mem")) else 2.2):
        break
pump(1.0)
out(b"$ ")
time.sleep(2.5)
out(b"\r\n")
