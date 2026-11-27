# What the board does at its start: BOOT.TXT

> **Since 2026-11-27** the shell has no `write` and no `append`. A file's contents are written by cancho-tools' `write`,
> built into the kernel: `write --create --stdin NAME`, or `--if-sha256 HEX` for a file that is there, then the text and
> Ctrl-D at the console, or the text as the command's input over SSH ([tools.md](tools.md)). It goes through the same
> writer: the old contents to `OLD`, a line in the record. Where a table below says `write NAME text` or `append`, that
> is what was typed when it was measured.

> **Status: built**, in QEMU, and used on the real Pi 4 (one board, one time). 0.0.32.

After a restart the kernel knows nothing: no link, no address, no SSH, no word of where the servo bus
is. Somebody had to type four lines at the serial console every time. `restart` over SSH
([`restart.md`](restart.md)) was therefore only half of an update with nobody at the board.

## What it is

A file on the card, `BOOT.TXT`. At its start the kernel reads it and types its lines to itself, as if
at the console, before it reads anything from the console:

```
# what this board does at its start
net eth
net dhcp
net ssh on
servo via 10.42.0.1 6000
```

- **Only a short list is run**, because the file is run with nobody there: `net up`, `net eth`,
  `net dhcp`, `net ssh on`, `servo via ...` and `echo ...`. Each must be the whole line. A line that
  could change the disk, load a kernel or restart the board is not on the list (`restart` in the file
  would be a board that never stops restarting), is not run, and is counted in what the kernel says.
- **Sixteen lines of 80 characters at most.** Empty lines and lines that begin with `#` are passed over.
- **A key at the console in the first second stops it.** That is the way out of a file that was a
  mistake: the kernel says how many lines it is about to run, waits a second, and runs none if a key
  came.
- **It is written at the console only.** Its lines run with the console's authority, and two of them
  (`net ssh on`, `servo via`) are things the network may not ask for. `watch on` may be a line too: it only makes a program that never ends reset the board (docs/tools.md).
  So over SSH `write`, `replace`, `move`,
  `copy` onto, `remove` and `put` all refuse the name, for an owner's key too. Reading it is allowed.
- `src/boot.cho` decides which lines are run and is pure, like `inet`, `fat`, `keys` and `record`.
- With no disk, or no such file, nothing happens and nothing is said.

A Pi's card is now looked for at the start, where it used to be looked for the first time a disk was
wanted ([`sdcard.md`](sdcard.md)). Every wait of that driver is bounded, so a card that does not answer
costs a moment and the shell still comes.

## Measured

QEMU's `virt`, a FAT16 volume:

| what | result |
|---|---|
| at the console: `write BOOT.TXT # ...`, then `append` of `net up`, `restart`, `net ssh on`, `echo the board is up` | the file, five lines |
| the same disk started again, nothing typed | "BOOT.TXT: 3 lines to run, 1 not run ..."; then `net up`, `net ssh on` and the `echo`, each with its answer; the host key made and kept |
| OpenSSH then logs in and asks `write BOOT.TXT from ssh` | "a file the board starts from", and the file unchanged |
| keys pressed during the first second | "BOOT.TXT: stopped by a key", and the link is down |

On the real Pi 4, the card holding a BOOT.TXT of `net eth`, `net dhcp`, `net ssh on` and `servo via ...`,
written at its console:

| what | result |
|---|---|
| over SSH: this kernel sent with `board/put.sh`, `write BOOT.TXT from ssh`, then `restart` | kept; "a file the board starts from"; "restarting ..." |
| nothing typed at the console; 28 seconds later, over SSH | `about`: 0.0.32; `uptime`: 21.280 s; `servo pos`: the arm's six positions; `record`: 19 lines, each following |
| the console's own log of that start | "BOOT.TXT: 4 lines to run", then the four lines and their answers: the link, an address from the other board, SSH on, the servo bus |

and 5 tests of `boot.cho` on its own (what is allowed; seventeen lines that are not, among them
`net ssh on; restart`; a file made into the lines to type; no more than sixteen; every byte of a file as
every value and the file cut at every byte: none traps).

## What it does not do

- **It does not wait for anything.** `net dhcp` is typed right after `net eth`; if the cable is not in,
  the lines after it run without an address.
- **It is not a shell script:** no conditions, no variables, one fixed list of commands.
- **Nothing is retried.** A lease that runs out is still not asked for again.
- **A wrong file is mended at the console**, or on another machine.
