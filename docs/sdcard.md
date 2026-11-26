# The SD card

> **Status: built, and run on a real Pi 4** (one board, one card, one session, 2026-11-26) and in QEMU as
> a Pi 3 and a Pi 4. `src/sdcard.cho`, 270 lines. It reads and writes one sector at a time, which is all
> [`storage.md`](storage.md) asks of a disk; everything above it (FAT, versions, the record) is the code
> that already ran on QEMU's `virt` disk, unchanged.

## What it is

A Pi's card slot is behind a standard controller (SDHCI: the SD Host Controller specification, version
3). On a Pi 4 it is the one at `0xfe340000`, which the board's documents call `emmc2`. The driver does
what the specification says and nothing more:

1. The controller is reset, the card is given power at 3.3 V, and the clock is set to 400 kHz or less.
2. The card is brought up with the commands every card takes: `CMD0`, `CMD8`, `ACMD41` until it says it
   is ready, `CMD2`, `CMD3`, `CMD9` (how big it is), `CMD7`. Then the clock goes to 25 MHz.
3. A sector is read with `CMD17` and written with `CMD24`: one block a command, the 512 bytes moved
   through the data register four at a time.

One data line, no DMA, no interrupts, no faster modes: the slowest way a card has, chosen because it has
the least to get wrong. Both kinds of card are handled: one that counts in bytes (2 GB and under, which
is what QEMU's is) and one that counts in sectors (every card sold now, and the real one).

**Nothing waits for ever.** Every wait is a count of turns, as in the virtio-blk driver, because the
driver holds no clock. A card that is not there fails at the sixth step and `disk` says so.

**The card is looked for the first time a disk is wanted**, not at boot: a kernel that could not start
its card must still reach its shell.

## What the kernel may touch for it

- The `vio` capability, which already held the virtio slots and the Pi 4's Ethernet card, gains the two
  controllers' registers: `0x3f300000..0x3f300100` and `0xfe340000..0xfe340100`. `docs/authority.txt`
  has the new bound, and that is the whole change to it.
- **A fourth question to the firmware.** The controller does not say how fast its own clock runs, and
  the divider is wrong without it. The firmware knows (tag `0x30002`, clock 12 on a Pi 4 and 1 on a
  Pi 3), and is asked once at boot. It is a question: the kernel still sets nothing through the mailbox.
- The card's signal voltage is left as the firmware set it when it loaded the kernel (3.3 V). Changing
  it is a firmware *set*, which the faster modes would need and this driver does not.

## Measured

In QEMU (version 11 here), the same FAT16 image `storage.md` uses, as a card:

| machine | what | result |
|---|---|---|
| `raspi3b` (the card is on the controller at `0x3f300000`) | `disk`, `ls`, `sum BIG.BIN`, `cat HELLO.TXT` | "an SD card of 32768 sectors (16 MB)"; the 10 files; the checksum macOS gives the file |
| `raspi3b` | `write`, `write` again, `copy` (300,000 bytes), `remove`, `purge`, `record` | macOS's `fsck_msdos -n` finds nothing wrong; the copy is the original byte for byte; Python finds the record whole |
| `raspi4b`, the card attached to `emmc2` by hand | `disk`, `sum BIG.BIN`, `cat HELLO.TXT` | the same |

QEMU's Pi 4 puts its card on the *other* controller, where a real Pi 4 has its Wi-Fi; `-device
sd-card,bus=main-system-bus/generic-sdhci/sd-bus` moves it to where the real board has it. CI's QEMU has
no Pi 4 at all, so CI runs the Pi 3.

On the real Pi 4 (4 GB), with the card it boots from, a 128 GB card whose first partition Linux made:

| what | result |
|---|---|
| `disk` | "an SD card of 249737216 sectors (121942 MB); a FAT32 volume at sector 8192, 516190 clusters of 512 bytes" |
| `ls` | 43 files: the firmware's, and the kernel the board had booted from |
| `sum CONFIG.TXT` | 404 bytes, the Adler-32 this repository's `board/config.txt` has |
| `write TEST.TXT ...`, then `cat` | "written: 45 bytes", and the text back |
| `write TEST.TXT` again, `versions`, `cat OLD/00000001.V` | the first text, kept |
| `net ssh on` | "ssh host key (new, and kept on the disk as HOSTKEY.BIN)" |
| the kernel started again (loaded over serial), `net ssh on` | "read from the disk: the same as before the restart", and the same key |
| a Mac logs in with OpenSSH and writes a file | written; the record's line names the key by the digits `ssh-keygen -l` gives |
| the same key asks to `purge` | "taken at the serial console only" |
| `cat LOG.TXT`, fetched over SSH and checked by Python | 4 lines, each following |
| `sum START4.ELF` (2,228,800 bytes) over SSH | 4.0 s: about 550 KB a second |
| `copy START4.ELF S4COPY.ELF` | 18.9 s, about 118 KB a second; the copy has the original's checksum |

## What was not done

- **No other system has checked the real card yet.** Everything in the table was read back by the kernel
  that wrote it. `fsck.fat` on another machine is the judge `permissions.md` asks for, and that needs the
  card moved. In QEMU the same code's writes were judged by macOS's checker.
- **No power cycle.** The restart was a kernel loaded over the serial console. The board has not been
  turned off and on with the new files on its card.
- **The kernel on the card is still an old one.** There is no command that writes a kernel to the card.
- **One card.** Cards differ, above all in how long they take to become ready and to store a block.
- **It is slow**, by choice: one data line and one block a command. Four lines and many blocks a command
  would be several times faster, and are not built.
- **A real Pi 3** has its card on a third controller (`sdhost`); only QEMU's Pi 3 was tried.
- **The Pi 5** has another controller again, and is not attempted (docs/pi5.md).
- **A card taken out** while the kernel runs is not noticed until a command fails.
