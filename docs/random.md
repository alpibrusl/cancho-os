# Randomness

> **Status: built for QEMU's `virt`, the Pi 3 (both in QEMU) and the Pi 4 (on a real board, where
> alone it can run).**

## What is wanted

Numbers nobody outside the machine can guess. Two things wait for them: the first sequence number of
a TCP connection (docs/network.md, section 7, says today's is a counter's value and can be guessed),
and every key SSH will ever make.

## Where they come from

A kernel has no randomness of its own; it must be given some by hardware. Each board has a generator:

| board | device | registers |
|---|---|---|
| QEMU `virt` | virtio-rng (device 4): the driver offers a buffer, the host fills it | the virtio slots and queue memory the network card already uses |
| Pi 3 (BCM2837) | the BCM2835 generator at `0x3f104000` | control `+0`, status `+4` (words ready in its top byte), data `+8` |
| Pi 4 (BCM2711) | the "RNG200" at `0xfe104000` | control `+0`, discard count `+0x10`, FIFO data `+0x20`, FIFO count `+0x24` |

The Pi 3's registers are the ones FreeBSD's `bcm2835_rng.c` (BSD-2-Clause) drives; the virtio device is
from the VIRTIO specification, section 5.4.

**The Pi 4's is started late.** (It had no driver at first, for the reason that follows; it has one
since a real board was on a serial line to try it on.) QEMU's Pi 4 does not have the RNG200 (`info mtree` on `-M raspi4b`, QEMU
11.1.3, shows nothing at `0xfe104000`), and reading the address there is a fault. A driver could only
be tried on a real board. So the kernel does not touch it at boot: `net eth`, which only a real Pi 4
can run, starts the generator with the card, and until then `random` says so and connections begin at
the counter. The registers are the ones FreeBSD's `bcm2835_rng.c` and Linux's `iproc-rng200.c` drive.

On the real board (2026-11-26): before `net eth`, "not started"; after it, two draws, "random (the
RNG200): cca9995b..." and "883d0505...", different; and `net` said "connections begin at a random
number (the RNG200)".

## The shape

- **One new capability, `rng`**, whose bound is the Pi 3's three registers. The virtio generator
  needs none: it is reached through `vio` and `dma`, which exist.
- **A pool of 16 words in the kernel's state**, filled where the kernel already waits for a key. What
  needs a number takes one from the pool, so the code that takes one (the network's) needs no
  capability for it.
- **A new connection's first sequence number is a word from the pool**, used once. If the board has
  no generator, or it gives nothing, the counter is used as before, and `net` says which.
- **`random` in the shell** prints sixteen bytes and where they came from.

## What was measured

At the commit that adds this file, QEMU 11.1.3:

| | what | result |
|---|---|---|
| `MACHINE=virt ./test.sh random random` | two draws from virtio-rng | 32 hex digits each, different |
| `./test.sh random random` | two draws on QEMU's Pi 3 | the same, from the BCM2835 generator |
| `MACHINE=raspi4b ./test.sh random` | QEMU's Pi 4 | "this board gave the kernel no source of randomness" |
| three connections to the kernel, captured (`DUMP=`), with the generator | the first sequence numbers of its three SYN-ACKs | 3358049669, 694824746, 2247639394 |
| the same without it (`NORNG=' '`) | | 187496562, 187878437, 251593562: the counter, each a little after the last |
| `./authority.sh` | `docs/authority.txt` | one new line, `mmio("0x3f104000..0x3f10400c")` |

Two draws differing says the device answers, not that its numbers are good: nothing here tests that.

## What it does not do

- **The hardware is believed.** Its words are used as they come: no health test, no mixing of several
  sources, no generator of our own seeded from it. A generator that is broken or lying is not noticed.
- **In QEMU the "hardware" is the host's own generator,** so nothing here says anything about the
  real chips' output. On a real Pi 3 the generator wants a warm-up, which is asked for and not checked.
- **`random` shows the generator's words to whoever has the shell,** including over port 23. They are
  drawn for the command and not from the pool, so they are never also a connection's number.
- **A random first sequence number is not RFC 6528's** (which adds a clock to a keyed hash of the
  connection's addresses, so numbers also rise over time). It is not guessable, which is the point;
  it does not protect against a stale segment of an earlier connection between the same two ports.
