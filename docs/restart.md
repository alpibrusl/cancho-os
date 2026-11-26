# Restart

> **Status: built**, in QEMU as a Pi 3 and a Pi 4. 0.0.29. The real board is in "Measured" when it has
> been tried there.

`restart` starts the whole board again, as at power-on: the firmware runs, reads the card, and loads
`KERNEL8.IMG`. After [`put`](update.md) that is the kernel that was sent, so the two together are an
update with nobody at the board.

## How

A Pi's power block has a watchdog: a counter, and a register that says what happens when it reaches
zero. The kernel gives it ten ticks (about 150 millionths of a second) and "a full reset". Two writes,
each taken only with `0x5a` in its top byte, which is the block's guard against a stray write.

- **A new capability, `pm`**: `0x3f10001c..0x3f100028` on a Pi 3 and `0xfe10001c..0xfe100028` on a Pi 4, the
  watchdog's registers and nothing else of the power block. `restart` is the one function that holds it.
  It is one more line in `docs/authority.txt`.
- **Half a second first.** The command says what it is about to do, adds its line to the record if there
  is a disk (`restart board`, with who asked), and the reset comes 50 ticks later, so that the words have
  left by the console or the SSH session.
- **Who may:** the console, and an owner's key over SSH. A reader's key is refused like any command that
  changes something.
- QEMU's `virt` machine and the Pi 5 have other ways to restart, not built: the command says so there.

## Measured

| where | what | result |
|---|---|---|
| QEMU `raspi3b`, and `raspi4b` | `restart`, then `about` | "cancho-os booted" a second time, and the shell answers |
| `raspi3b` with an SD card | `write A.TXT x`, `restart`, `cat LOG.TXT` | after the restart the record has line 2, `console console restart board`, and both lines follow |
| `virt`, at the console and over SSH | `restart` | "this machine has no such watchdog here" |

## What it does not do

- **It does not save a board from a kernel that does not boot.** `put` a bad kernel, `restart`, and the
  board stays down until its card is mended elsewhere. The firmware can try a kernel once and go back
  to the old one; using that is not built.
- **Nothing restarts the board by itself.** The same watchdog could reset a kernel that hangs, which a
  controller for a robot wants. Here it is only wound when `restart` is typed.
- **Nothing is put away first.** There is nothing to put away: every write is already on the card when
  its command answers. An SSH session that is open is cut.
