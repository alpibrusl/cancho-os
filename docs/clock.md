# The date

> **Status: built**, in QEMU and tried against a real clock. What uses the date so far is small: the times of files
> the kernel writes, a line in the record, and the `time` command. A grant that ends on a day
> ([`permissions.md`](permissions.md)) and the checking of a certificate are what it is for, and are not built.

## What was missing

The board has no clock that keeps running without power. It counted from the moment it started and knew nothing
else, and that had come up five times: a grant cannot say "until"; a certificate cannot be checked; every file the
kernel wrote was dated the first day of 1980; the record orders its lines but cannot say on which day; and the
address the network lends is never asked for again.

## Where the date comes from

A machine on the network is asked (SNTP, RFC 4330): one datagram to its port 123, one back.

- `net time <address> [port]` asks. It is a line `BOOT.TXT` may have ([`boot.md`](boot.md)), so a board can know
  the date from its start. `time` says what the board believes.
- `src/clock.cho` makes the question, reads the answer and turns seconds into a date. It is pure, like `inet` and
  `fat`: `tests/clock_test.cho` holds its dates to what Python's `time.gmtime` gives for the same seconds, its
  answers to packets laid out as the RFC lays them out, and no bytes make it trap.
- The kernel keeps one number, the time the board started at (k[4275]): the time now is that and how long the board
  has been up. The time a command was typed at (k[4276]) is what the files it writes are dated.
- An answer is taken only if it gives back the number the question carried (drawn from the random pool when there
  is one), comes from a server that says it has the time itself, and names a moment after 2023.

## What it is used for

- **The files the kernel writes** are dated: `store_as`, a directory made, a name changed, a copy, and `LOG.TXT`
  each time it grows. FAT keeps a date with no zone; the kernel writes UTC there, and a system that reads the card
  takes it for its own zone's time, as it does for every FAT volume.
- **The record gains a line** when the date is learned: `n ticks kernel kernel time <seconds> ...`. The record's
  lines have no dates of their own; with that line and the ticks each line carries, every later line of the same
  start can be dated. The format of a line is not changed.

## What it is not

- **It is believed, not proved.** Nothing in SNTP shows that the answer is the server's. Whoever can answer for that
  address on the board's network can tell it any date after 2023. The number in the question stops an answer from
  someone who cannot see the question, and nothing more.
- **The date may go backwards.** A second `net time` replaces the first, and nothing on the card is consulted.
  Before anything is refused or allowed by the date (a grant's "until"), two rules have to be built: the board
  keeps the latest date it has seen and takes none before it, and a board that has not been told the date treats
  what ends on a day as ended.
- **It is asked once.** The board's count from then on is its processor's counter: it is not corrected afterwards.
- **Whole seconds**, and FAT keeps even ones.
- **Before the date is known** everything is as it was: files of 1980, and `time` says so.

## Measured

In `qemu-system-aarch64` as `virt` (2026-11-27), with `tests/sntp.py` on the Mac as the machine that is asked:

| done | seen |
|---|---|
| `time` before anything | "the board has not been told the date" |
| `net time 10.0.0.1` against a server saying 1795790412 | "it is 2026-11-27 14:40:12 (UTC)"; `time` a second later says :13 |
| `write` of a file, `mkdir`, `copy`, `move` after it | `ls` gives each the time it was made at; macOS, reading the card, gives the same date and time for each, the directory too |
| `cat LOG.TXT` | a line `kernel kernel time 1795790412` |
| the server asked on port 12300, saying the Mac's own time | the kernel's date is the Mac's, to the second |
| a server that gives back another question's number | "did not say what time it is", and the date stays unknown |
| `net time` with no address, or a port that is not a number | how it is used |

macOS's `fsck_msdos` finds nothing wrong with the volume.
