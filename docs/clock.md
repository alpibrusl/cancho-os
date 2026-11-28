# The date

> **Status: built**, in QEMU and on the Raspberry Pi 4. What uses the date: the times of files the kernel writes,
> a line in the record, the `time` command, and a grant that ends on a day ([`permissions.md`](permissions.md)).
> The checking of a certificate is not built.

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
- **The date does not go back, as far as the card can tell** (0.0.47). The record's entry in the top directory
  is dated each time a line is added, so its date is a moment the board has lived through; `net time` does not
  take a date more than two seconds before it, and says both dates. `net time <address> [port] back`, typed at the
  console, takes it all the same: a board once told a date in the future could otherwise never be put right. It is
  not a line `BOOT.TXT` may have. Someone who can write the card can change that entry, as they can change
  everything else on it.
- **A board that has not been told the date takes what ends on a day to have ended**: an agent's grant with
  `until:` grants nothing ([`permissions.md`](permissions.md)).
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

On the Raspberry Pi 4, from its card (2026-11-27, 0.0.46), with `tests/sntp.py` on the Raspberry Pi 5 beside it
(port 12300, saying the Pi 5's own time, which it keeps by NTP): `net time 10.42.0.1 12300` over SSH gave the
date, and `time` three seconds later was one second from what the Mac's clock said at that moment; a file written
then is dated, by `ls`, four seconds before the Mac's clock when it was read. The Pi 5 has no time server of its
own running: for the board to know the date at every start, `BOOT.TXT` needs a `net time` line and a machine that
answers on port 123.

The date not going back, and a grant that ends on a day (2026-11-27, 0.0.47), in QEMU as `virt`:

| done | seen |
|---|---|
| a file written with the date known (27 November, 14:40); the same disk started again; a machine that says 18 November | "not believed", with both dates; `time` says the date is not known |
| `net time ... back`, typed at the console | taken |
| a machine that says a minute later than the record | taken |
| an agent's line with `until:2020-01-01` | `list DOCS` refused |
| the line with `until:2999-12-31`, the board not told the date | refused |
| the same line, after `net time` | `list DOCS` answered |

## The clock and random bytes, lent to a program (0.0.52, epic #60 task #50)

A program holds what it was handed (docs/tools.md). Two more things can now be handed to it.

- **The clock.** A program that holds a `Clock` asks `clock_ms` (milliseconds since the board started, which only go
  up) and `clock_unix_ms` (milliseconds since 1970). `ksys.clock` answers both from the processor's counter and the
  date the board was told. A board not told the date answers `clock_unix_ms` with 0: no pretend date. The block that
  lends the system discharges `clock` (cancho, the clock in `docs/bare-system.md`), so the kernel's own authority does
  not gain it. `now` is a program that shows both.
- **Random bytes.** A program asks for them as cancho has a program ask on any system: it opens `/dev/urandom` through
  its `Fs` and reads (cancho `docs/narrowing-into-several.md`). No new builtin, and a program that wants them must hold
  an `Fs` that covers that path, which its row says. On the board that path is not a file: `ksys` seeds a handle with
  four words of the board's generator, each used once, and gives SHA-256 of the seed and a count. A board with no
  generator answers "no such device" (19); one whose pool is used up, "try again" (11). The kernel's own `random`
  command is gone: `random [n]` is a program that reads `/dev/urandom` and prints n bytes in hex.

What it is not:

- The bytes are as good as the board's generator, stretched by SHA-256 over a 128-bit seed per opening. That is a hash
  DRBG in the plainest form, not one of NIST's constructions, and it has not been judged by a test suite of that kind.
- A program cannot be lent the clock without the date: `clock_unix_ms` is 0 until the board is told it, and a program
  cannot tell "not told" from the first moment of 1970 except by that 0.
- `/dev/urandom` is the one name of its kind. A grant does not name it: reading it reveals nothing of the disk.

Measured, in QEMU as `virt`: `now` before `net time` gives `"unix_ms":null`, after it the server's date in milliseconds;
24 readings of 256 bytes are all different, 49.9% of their bits are ones, and the 256 values come as often as chance
has them (chi-squared 277.8 with 255 degrees of freedom); on QEMU's Pi 3 the same, from its own generator; with no
generator, "no random bytes: this machine has no generator".
