# Storage

> **Status: design, first slice.** What was measured is at the end.

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
4. **The real card**: the SD controller of the Pi 4, which only a board can try.
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

## What it does not do, yet

- **Writing.** Nothing here changes a disk.
- **Directories below the top, long names, FAT12, exFAT.**
- **The SD card.** On a real Pi there is no disk until its controller has a driver.
