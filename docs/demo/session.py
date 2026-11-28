#!/usr/bin/env python3
"""A real session with cancho-os on a Raspberry Pi 4, typed at a human pace, for the recording.

    asciinema rec --cols 100 --rows 30 -c "python3 docs/demo/session.py 10.42.0.169 build/kernel8.img" pi4.cast

What the kernel answers is whatever it answers; only the typing is scripted. The board is reached through a
second board (`-J pi`), which also has the robot arm's adapters. Three ssh options are passed and not shown:
the key to log in with, and the two that skip the host-key question."""
import os, pty, select, subprocess, sys, time

HOST = sys.argv[1]
KERNEL = sys.argv[2]
WHERE = ["-J", "pi", "cancho@" + HOST]
QUIET = ["-i", os.path.expanduser("~/.ssh/id_ed25519"), "-o", "IdentitiesOnly=yes", "-o", "StrictHostKeyChecking=no",
         "-o", "UserKnownHostsFile=/dev/null", "-o", "LogLevel=ERROR"]
LINES = ["about", "disk", "write NOTE.TXT first words", "write NOTE.TXT second thoughts", "cat OLD/00000004.V",
         "record", "servo pos", "arm pose", "exit"]
SLOW = ("write", "servo", "arm", "disk")


def out(b):
    os.write(1, b)


def typed(text, each=0.05):
    for ch in text:
        out(ch.encode())
        time.sleep(each)


def shown(command):
    out(b"$ ")
    typed(command)
    time.sleep(0.5)
    out(b"\r\n")


out(b"\x1b[2m# a Mac; a Raspberry Pi 4 running cancho-os from its own card, reached through a second\r\n"
    b"# board that also holds a robot arm's adapters\x1b[0m\r\n")
time.sleep(1.5)
shown("ssh -J pi cancho@" + HOST)

pid, fd = pty.fork()
if pid == 0:
    os.execvp("ssh", ["ssh", "-tt"] + QUIET + WHERE)


def pump(seconds):
    end = time.time() + seconds
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
    return True


pump(3.0)
for line in LINES:
    for ch in line:
        os.write(fd, ch.encode())
        pump(0.06)
    pump(0.4)
    os.write(fd, b"\r")
    if not pump(3.4 if line.startswith(SLOW) else 2.0):
        break
pump(0.8)
os.waitpid(pid, 0)

# a new kernel, sent to the card over SSH; then the board is told to start again from it
out(b"\x1b[2m# a new kernel to its card, and a restart into it\x1b[0m\r\n")
time.sleep(1.0)
shown("board/put.sh -J pi cancho@" + HOST + " " + KERNEL + " KERNEL8.IMG")
r = subprocess.run(["board/put.sh"] + QUIET + WHERE + [KERNEL, "KERNEL8.IMG"], capture_output=True)
out(r.stdout.replace(b"\r", b"").replace(b"\n", b"\r\n"))
time.sleep(1.8)
shown("ssh -J pi cancho@" + HOST + " restart")
r = subprocess.run(["ssh"] + QUIET + WHERE + ["restart"], capture_output=True, stdin=subprocess.DEVNULL)
out(r.stdout.replace(b"\r", b"").replace(b"\n", b"\r\n"))
time.sleep(1.5)
out(b"$ ")
time.sleep(3.0)
out(b"\r\n")
