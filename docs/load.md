# Loading a kernel over the serial line

> **Status: built; in QEMU on all three boards, and on a real Pi 4**, where it found a fault in itself
> that QEMU could not (the end of this file).

## What is wanted

A real Pi 4 boots this kernel now, and its console is a serial line to another machine. But the kernel
is a file on an SD card inside the Pi: every new build means moving the card by hand. A driver for real
hardware takes many builds. So the kernel should be able to take its successor over the line it already
has, and start it.

## The shape

- **`load <bytes>`, at the serial console only.** The kernel reads that many bytes from the console
  into memory set aside for it (2 MB, a new capability, `stage`), and prints how many arrived and their
  Adler-32 checksum.
- **Nothing runs until the sender agrees.** The sender computes the same checksum over the file it
  sent and types `go <checksum>`. Anything else, or a mismatch, and the bytes are forgotten.
- **Starting it is the boot stub's job, and the stub is told by a fault.** cancho has no way to jump to
  an address, and this kernel has no foreign function, so the kernel cannot call anything. It writes a
  mark and the length in front of the staged image and then does what `crash null` does. Every fault
  enters the stub; the stub sees the mark, copies the image over the running kernel and jumps to it.
  With no mark, a fault is reported as before.
- **About thirty instructions of assembly,** the first added since the exception stub: the data cache
  is written out and emptied, translation and caches are turned off (the old image is mapped read-only,
  and the new kernel must not meet the old one's cached data), a copy loop is moved below the stack
  because it cannot run from the image it overwrites, and the loop copies and jumps.

## What it means for trust

Whoever has the serial console can replace the kernel. That was already true in the sense that matters:
the console is where `net shell on` is given and where the board is held. `load` is not offered over
the network shell. It is a tool for bringing up hardware, and a kernel that guards a robot should be
built without it.

## What was measured

At the commit that adds this file, QEMU 11.1.3, `./load.sh` (and `MACHINE=raspi4b`, `MACHINE=virt`; CI runs
the Pi 3 and `virt`, its QEMU having no Pi 4):

| | result |
|---|---|
| a kernel of 127,464 bytes sent, then `go 00000000` | "forgotten"; `about` still says 0.0.18 |
| the same sent again, then `go` and its real Adler-32 (from Python's `zlib`, not from the kernel) | "starting it", the boot message again, and `about` says 0.0.99 |
| in the kernel that was loaded | `ticks` counts; `crash null` is reported and halts, as before |
| `load` typed over the network shell | "unknown command" |
| `./authority.sh` | one new line, `mmio("0x220000..0x420000,0x40220000..0x40420000")`; still no foreign code |

QEMU has no caches, so the part of the stub that empties them and turns them off has been assembled
and executed there, and tested by nothing. That part is what a real board decides.

**On the real Pi 4** (2026-11-26, one board): 0.0.18 booted from the card; `board/send.py`, run on the
machine wired to its console, sent the 0.0.99 image: "sent 127464 bytes in 11.2 s; checksum ours
bf805bc8, the kernel's bf805bc8", then "starting it", the boot message, and `about` said 0.0.99. `mem`
printed the new image's map and `uptime` went on counting. So the cache handling in the stub did what
it is for, once.

**And then it was found not to.** `ticks` in a loaded kernel began some thousands too high, and a later
one woke up with its predecessor's network address and packet counts. The stub emptied the cache only
up to the end of the staging area, and the kernel's state is in the heap above it: the old kernel's
cached lines were still there when the new kernel turned the cache on, and came back over its freshly
zeroed memory. The stub now empties the cache for all the RAM the kernel maps (960 MB, a fraction of a
second). After that fix a loaded kernel starts from nothing: loaded once more by the old stub, a kernel
said "76644 timer interrupts" and "link up ... address 192.168.1.69" before anything was typed; loaded
by the fixed stub, the same image said "105 timer interrupts", "link down", "0 packets answered".

The same hazard existed at power-on: the kernel turned the cache on without emptying it first, and
relied on the firmware having left it clean. The boot stub now empties every level of the data cache
(by set and way, the architecture's recipe), the instruction cache and the TLB before `main`, on every
start. That code has run on the real board each time a kernel was loaded since; **it has not yet run
there at a real power-on**, where the kernel is entered a level higher. In QEMU it runs and does nothing.

## What it does not do

- **It does not write the SD card.** After a power cycle the Pi boots the card's kernel again.
- **No compression, no resuming:** a byte lost (the console is polled, with no flow control) fails the
  checksum, and the file is sent again.
