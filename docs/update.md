# A file sent over SSH, and a new kernel without a cable

> **Since 2026-11-27** the shell has no `write` and no `append`. A file's contents are written by cancho-tools' `write`,
> built into the kernel: `write --create --stdin NAME`, or `--if-sha256 HEX` for a file that is there, then the text and
> Ctrl-D at the console, or the text as the command's input over SSH ([tools.md](tools.md)). It goes through the same
> writer: the old contents to `OLD`, a line in the record. Where a table below says `write NAME text` or `append`, that
> is what was typed when it was measured.

> **Status: built**, in QEMU, and used once on the real Pi 4 to replace the kernel on its own card
> (below), which it then started from after its power was cut and restored. 0.0.28.

## What it is

`put <name> <bytes> <sha256>`, over SSH, and then the file's bytes on the same session.
`board/put.sh` does it:

```
board/put.sh cancho@192.168.1.24 build/kernel8.img KERNEL8.IMG
```

1. The line says how long the file is and what its SHA-256 is. The session then carries the file, not
   typing, until that many bytes have come. They wait in memory (the 2 MB that `load` uses), so a file is
   2,097,136 bytes at most.
2. **What came must have the hash that was given.** If not, nothing is written.
3. The bytes go to clusters that were free, and are **read back from the disk** before anything names
   them. If the disk does not give back the same hash, nothing is changed.
4. Then as any write ([`permissions.md`](permissions.md)): what the name held goes to `OLD`, the record
   gets its line (`put`, with the hash), and the directory entry is changed last, in one sector.

So a kernel that arrives damaged, or a card that stores it wrongly, never becomes the file the board
starts from.

## The files the board starts from

The firmware reads `CONFIG.TXT`, `CMDLINE.TXT` and every `.ELF`, `.DAT`, `.DTB`, `.BIN` and `.IMG` before
any kernel runs. A wrong one stops the board until its card is mended on another machine. Over SSH,
`write`, `replace`, `move`, `copy` onto and `remove` now refuse those names: they are changed with `put`, which
checks every byte, or at the serial console.

`put` itself needs an owner's key. Every key is a person's today. When agents have keys of their own
(slice 5), replacing one of these files is among the things a person's key must approve.

## The open shell on port 23 is gone

`net shell on` gave the shell to whoever connected, with no password and no encryption. It was a step
towards SSH and stayed one change longer for comparison. It is removed: the command, the session code,
and the record's `port23`. The only way in from the network is SSH with a key that is allowed.

## Measured

In QEMU's `virt`, with OpenSSH's client (and the same in CI, judged by `fsck.fat`, `mcopy` and the
record's checker):

| what | result |
|---|---|
| this build (377,680 bytes then) sent as `KERNEL8.IMG` | "kept: 377680 bytes, read back from the disk with the SHA-256 that was given"; `sum` gives Python's Adler-32; 8 s for the whole test |
| a second file sent under the same name | kept, "what was there is OLD/00000001.V"; macOS reads both, byte for byte |
| five bytes sent with another five's hash | "what came does not have the SHA-256 that was given: nothing was written", and no file |
| `remove KERNEL8.IMG`, `write CONFIG.TXT x` over SSH | "a file the board starts from", twice |
| `put LOG.TXT ...` | refused: the kernel's own names stay its own |
| `net shell on`, typed over SSH or at the console | "unknown command"; port 23 refuses a connection |

On the real Pi 4, from a Mac on the same network, to the card the board boots from:

| what | result |
|---|---|
| `board/put.sh cancho@... kernel8.img KERNEL8.IMG` (this kernel, 373,376 bytes) | "kept: 373376 bytes, read back from the disk with the SHA-256 that was given; what was there is OLD/00000002.V", in 6.8 s |
| `sum KERNEL8.IMG` | the Adler-32 Python gives the file that was sent |
| `versions` | the kernel that was there, 368,832 bytes, kept |
| `remove KERNEL8.IMG`, `write CONFIG.TXT x` | "a file the board starts from", twice; `CONFIG.TXT` unchanged |
| `record` | 6 lines, each following |
| the board turned off and on | `about` says 0.0.28: the firmware loaded the kernel that came over SSH; the host key and the record as before |

## What it does not do

- **It does not know a good kernel from a bad one.** A kernel that arrives whole and does not boot stops
  the board. The one before it is in `OLD`, and another machine can put it back; the board cannot.
  Trying a new kernel once and falling back is not built.
- **2 MB.** The file waits in memory before it is written.
- **One at a time,** and nothing else is read from that session until the file has come.
- **A session that ends early** leaves nothing: the bytes that came are forgotten.
