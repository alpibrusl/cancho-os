# Storage

> **Status: reading and a first kind of writing work, in QEMU.** A file can be added, and added to; nothing
> that is there can be changed or removed yet. No real card.

## What is wanted

Somewhere for things to outlive a restart. Three are waiting: the SSH host key, which is new at every
start because there is nowhere to keep it (docs/ssh.md); the keys that may log in, which are built
into the image; and the kernel itself, which reaches a real board by moving a card or over the serial
line (docs/load.md) and is gone at the next power cycle.

## The order

The same as the network's, for the same reasons:

1. **The file system, with no hardware under it.** `src/fat.cho`: FAT16 and FAT32, pure, given sectors
   and giving answers. Tested on the machine that builds it, and against file systems made by other
   people's tools.
2. **A disk QEMU has**, so every change is tried in CI: virtio-blk on the `virt` machine.
3. **Reading**, then **writing**.
4. **The real card**: the SD controller of the Pi 4, which only a board can try. Built, and tried on
   one: [`sdcard.md`](sdcard.md).
5. **Using it**: the host key kept, the allowed keys read, a new kernel written to the card.

This file is slices 1 to 3, reading only.

## Why FAT

A Pi's firmware reads the kernel from a FAT partition, so the card already has one, and every other
machine can read and write it. A file system of our own would be simpler to make correct and would
put the kernel's files where nothing else could reach them, including the firmware. FAT is old,
has no journal and no permissions; what it has is that the card is already speaking it.

## The shape

- **`src/fat.cho` is pure**, as `src/inet.cho` is: no capability, no trap on any bytes. It cannot read
  a disk. It is given a sector and says what it means: where the partition is (`partition`), what the
  volume is (`mount`), what a directory entry names (`entry`), which sector holds a cluster
  (`cluster_sector`), which cluster comes next (`fat_sector`, `next`). The caller does the reading.
- **Sectors are 512 bytes.** A volume with another size is refused.
- **Names are the short ones** (`KERNEL8.IMG`, eight and three). Long names are skipped: a file with
  one is seen under its short alias, as on any old system. Only the top directory is read.
- **A disk is two functions**, `disk_read` and `disk_write` of one sector, whatever is under them.
  First under them: virtio-blk (VIRTIO 1.2, section 5.2), with the queue in `dma` beside the others
  and its registers in `vio`, so no new capability.
- **Commands:** `disk` (what is there), `ls`, `cat <name>`, and `sum <name>`, which reads a whole file
  and says its length and Adler-32, so that a file of any size can be compared with the same file on
  another machine.

## What was measured

At the commit that adds this file, QEMU 11.1.3. `./authority.sh` says "as recorded": the disk is reached
through capabilities the network card already used.

| | what | result |
|---|---|---|
| `cancho test tests/fat_test.cho src/fat.cho --std` | 11 tests, on sectors of three volumes macOS made (`hdiutil create -fs "MS-DOS FAT32"`, `FAT16`, and FAT32 behind a partition table), their meaning read by a second implementation (Python's `struct`) | the partition's start, each volume's ten numbers, five files' names, clusters and lengths, a chain of 586 clusters followed to its end; 57,856 damaged sectors, none traps |
| `MACHINE=virt DISK=fat32.img ./test.sh disk ls 'sum BIG.BIN' ...` | the kernel reading those volumes through virtio-blk | "a FAT32 volume at sector 0, 129022 clusters of 512 bytes"; ten files listed; `sum BIG.BIN`: "300000 bytes, adler32 2832a702", which is what Python's `zlib` says of the file that was copied in |
| the same on the FAT16 volume (clusters of 2,048 bytes) and behind the partition table (volume at sector 1) | | the same three checksums |
| in CI | three volumes made there by Linux's tools (`mkfs.fat`, `mcopy`, `sfdisk`): a third implementation | the same checks, the checksum computed on the runner; and `ssh host 'sum BIG.BIN'` gives it over SSH |

A file with a long name was there too: it is listed as `A-LONG~9.TEX` and reads correctly under that
name. macOS also left its own `._` files beside each, which `ls` shows as it finds them.

## Writing

Not "write a sector". [`permissions.md`](permissions.md) is the design: who may change what (keys and
grants, not users), every write a new version, a record that is only added to, and an order of writes in
which a power cut never leaves a file half changed. It was written before any code that writes.

**Three slices are built**: `write <name> <text>` makes a file, `append <name> <text>` adds a line
to one, `copy <from> <to>` makes a new file with another's contents. Since the third slice `write` to a
name that exists replaces it and `remove <name>` takes it away, and both keep what the file held, in the
directory `OLD`; every change has a line in `LOG.TXT`. [`permissions.md`](permissions.md) has the order
of writes and what was measured.

- **`fat.cho` still writes nothing.** It changes the bytes of a sector it is handed (a free cluster
  found, an entry of the table set, a directory entry made) and is still pure. `disk.cho` decides what
  goes to the disk and when.
- **The order.** A file's contents and the table's chain for them first; the directory sector that
  names them last. Until that sector is written the disk reads exactly as it did. For `append`, the
  new bytes go past the file's end, where nothing reads them, and the length is changed last.
- **A FAT32 directory that is full is given another cluster;** a FAT16 top directory is a fixed size and
  can be full. FAT32's count of free clusters is brought down by what was taken.

Measured, at the commit that adds this section:

| | what | result |
|---|---|---|
| `cancho test tests/fat_test.cho src/fat.cho --std` | 18 tests (11 before) | an entry made here has the bytes of the entry macOS made for the same file (name, kind, first cluster, length); a free cluster found where the second implementation finds it; the top four bits of a FAT32 entry kept; 39,936 names, none traps |
| the kernel in QEMU writing to copies of the three volumes macOS made: a new file, a 300,000-byte copy, a line added, twenty more files, thirteen lines added across clusters | then macOS's own `fsck_msdos -n` and macOS mounting the result | the checker finds nothing to fix; the copy is the original byte for byte; the thirteen lines are the thirteen lines; the files that were there are untouched |
| in CI | the same on three volumes Linux's tools made, judged by `fsck.fat -n`, `mcopy` and `mdir` | the same |

One thing CI found that this machine did not: on a busy runner a single request to the disk took longer
than the driver waited (ten million turns of a loop, which is well under a second), and a `copy` gave up
with the disk untouched. The driver now waits two thousand million turns. It still counts turns and not
time, because it holds no clock.

What this slice does not do: replace or remove a file; write below the top directory; survive a power cut
*provably* (the order is the argument; nothing here cuts the power); set a date (files are dated 1 January
1980, the kernel having no clock); or ask who is writing (that is the next slice: until then whoever has
the shell may add files).

## What it does not do, yet

- **Directories below the top, long names, FAT12, exFAT.**
- **Writing a kernel to the card.** Files come in as one line of text or as a copy of another file.
