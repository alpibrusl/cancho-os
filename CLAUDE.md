# cancho-os — context for agents

Goal: an OS written in cancho (https://github.com/alpibrusl/cancho), no Linux underneath.
Read README.md (build, layout) and docs/ROADMAP.md (decisions, tracks, milestones) first.

Rules of the road
- Everything is cancho (`src/`), drivers included. `board/boot.S` holds only boot, the exception
  stub and the start of a kernel loaded over the serial line (docs/load.md; it is reached by a fault, not
  called), and exports nothing to cancho: never add logic or a callable symbol there. The kernel has no
  `extern fn` and no `Ffi`; `cancho authority` must keep saying it never touches foreign code. There is no C in this repository: do not add any.
- Hardware is a capability. A register is reached through an `Mmio` whose bound is exactly the
  registers the driver uses (cancho docs/mmio.md, edition 13); `main` cuts the eight and is the only
  place a bound is chosen. A new register means widening one bound there and in the signatures that
  carry it, and `./authority.sh` then fails until docs/authority.txt is updated: read that diff in review.
  Never lend a function a capability it does not need. System registers go through `Cpu`
  (cancho docs/cpu.md, edition 14): `cpu_read(cpu, "name")`, and the row lists each name.
- Interrupts stay masked and are polled after `wfi`; a fault re-enters `main`, which reports it.
  So no code runs behind cancho's back and there is no shared mutable state (docs/issues/04).
- Every milestone must boot in QEMU in CI (.github/workflows/qemu.yml) with a scripted shell check.
- The compiler must have `--target aarch64-none-elf` (cancho docs/freestanding.md). In the cancho repo:
  `sh scripts/build-standalone.sh --out /tmp/cancho-out --rev $(git rev-parse HEAD)`, then
  `CANCHO=/tmp/cancho-out/cancho ./build.sh`. The seed alone (`seed-build.sh`) is too old until a reseed.
- QEMU 8.x has only raspi3b; raspi4b needs QEMU ≥ 9. One kernel8.img serves both: the kernel reads
  MIDR_EL1 (`detect` in kernel.cho). A new board is a new branch there, from its datasheet.
- Direction and the robot steps are in docs/ROADMAP.md ("Direction"). `src/feetech.cho`, `calibration.cho`,
  `kinematics.cho`, `so101.cho` and `safety.cho` are vendored from cancho-robot: change them there. The kernel must stay unable to move a servo until the safety core
  exists: do not vendor `feetech_write.cho` before then.
- `SERVOS=1 ./test.sh 'servo scan'` attaches `sim/servos.cho` (built for the host by build.sh).
- The network (docs/network.md): `src/inet.cho` is pure and must stay so (no capability, no trap on any
  bytes); its packets are checked against vectors a second implementation built, never against itself.
  `NET=1 ./test.sh 'net up' net` attaches `sim/netpeer.cho`; `sudo ./ping.sh` is Linux-only (CI).
  TCP's state is the caller's (two slices the shell allocates) and its clock an argument: keep it so.
  A new vector comes from the second implementation, never from `inet`'s own output (tests/tcp_test.cho).
  A change to TCP is tried against a real stack before it is believed: `MACHINE=virt TCPFILE=... ./test.sh`
  (QEMU's own TCP) here, `sudo ./ping.sh` (Linux's) in CI. Twice every test passed and a real stack
  showed the code wrong (docs/network.md, section 7): never take back window that was offered.
- The Pi 4's Ethernet (docs/genet.md) runs only on the real board: QEMU's raspi4b has no GENET and `net eth`
  faults there, so no test may type it. Change it only with the board on the serial link, and send builds
  with `board/send.py` (docs/load.md). `dma` is mapped as device memory on purpose: a card writes it.
  The network's only way in is SSH: the open shell on port 23 was removed (docs/update.md) and stays out.
- Storage (docs/storage.md): `src/fat.cho` is pure like `inet` (given a sector, says what it means; no trap
  on any bytes) and its tests use sectors of volumes other tools made, read by a second implementation.
  Three layers, each importing only the ones before it: `src/disk.cho` (the driver, the table, directories,
  the writer), `src/ledger.cho` (LOG.TXT on the disk), `src/files.cho` (the commands, the kernel's own files, `put`). A change is tried against real images before it is
  believed: `MACHINE=virt DISK=img ./test.sh ... 'sum NAME'` and the checksum from another tool.
  Writing follows docs/permissions.md: the directory sector that names new data is written LAST, nothing
  that is on the disk is changed in place, and a write is believed only when another system's checker
  (`fsck.fat -n`, macOS `fsck_msdos -n`) finds nothing wrong and another system reads the bytes back.
  A write over a file or a `remove` gives what was there a name in `OLD` first and changes the file's own
  entry last; only `purge`, at the console, frees a version. Directories are walked with their own table
  buffer (`wt`), never the writer's `tab`, whose cached sector `w[5]` tracks.
- The record (docs/permissions.md, slice 3): `src/record.cho` is pure and makes and checks LOG.TXT's lines;
  its vectors come from Python's `hashlib`, and `tests/checklog.py` is the judge of a real file. Every
  command that changes the disk calls `record_add` after its data is on the disk and before the one
  sector that makes the change take effect, and stops if the line could not be added. The line format is
  what other tools read: do not change a field without changing `checklog.py` and the doc. `OLD`, `LOG.TXT`
  and `HOSTKEY.BIN` are names the shell does not change (`kept_name` in files.cho).
- The SD card (docs/sdcard.md): `src/sdcard.cho` is standard SDHCI with 32-bit register access only, every
  wait a bounded count, and it is started the first time a disk is wanted, never at boot. QEMU's raspi4b has
  its card on the other controller: `-device sd-card,drive=...,bus=main-system-bus/generic-sdhci/sd-bus`
  puts one on `emmc2`. `SD=image ./test.sh` is the Pi 3 in QEMU, which CI runs. The real card is the one
  the board boots from: a wrong write there can stop it booting, so change the write path only after
  QEMU and a checker have passed it, and never write `KERNEL8.IMG` or the firmware's files in a test.
- Who may do what (docs/permissions.md): a session's role is k[4179] (2 an owner's key, 1 a reader's); a
  new shell command must be put on the reader's list in `reading` (kernel.cho) only if it changes nothing
  and reaches nowhere. `HOSTKEY.BIN` is never shown, copied or changed by the shell (`secret` in files.cho).
  `./keys.sh` is the test, with OpenSSH and three keys.
- SSH (docs/ssh.md) is cancho-ssh, pinned by `SSH_REF` in the workflow and taken from `../cancho-ssh` (or
  `SSH=`) by build.sh: change it there, never copy it here. `src/sshd.cho` is the loop and must keep its two
  rules (read the connection only when nothing else moved; keep what `feed` and `tcp_write` did not take).
  A real person's public key goes into an image, never into the repository: `AUTHORIZED=` writes
  `build/authorized.cho`, and `build/` is ignored. SSH must refuse to start without a generator.
- The firmware's mailbox (`fw`, docs/genet.md) can set things as well as answer: the kernel asks four tags
  (three about the board, one clock's rate for the SD card) and sets nothing. A new tag is a decision, not a convenience. Never write a real board's serial number or
  full card address into a doc, a test or a commit.
- A real Pi 4 has booted it (README, "On a real Pi 4"): one board, one session. Say exactly that, and
  keep "measured in QEMU" on everything that was not seen on the board.
- The Pi 5 (docs/pi5.md) is the one board whose code no test runs: QEMU has none. Do not describe it as
  working, and do not add a Pi 5 driver (RP1, the RNG200, USB) before the console has been seen on a real board.
- Files, none near 2,000 lines (network.cho, at 1,560, is the one to watch): `src/kernel.cho` (boot, memory, shell, servo and arm), `src/base.cho`
  (console output, clock, bus bytes), `src/network.cho` (links, generator, session, network commands). A
  new network command goes in `network.net_command`, never in the shell's loop.
- The kernel's address, mask, gateway and name server are k[4154..4157] (docs/addresses.md); nothing may
  assume 10.0.0.2. DHCP and DNS answers are parsed by `inet` and must have a no-trap test like the others.
- `tcp_connect` is a name of cancho's prelude, and `where` a keyword: `inet` says `tcp_dial`.
  A command that waits on the network (`http`) sets k[39] so `session` leaves the shell's connection alone.
- Randomness (docs/random.md): `rng_word` reads the generator, the pool at k[4136..] is what other code takes
  from. QEMU's raspi4b has no RNG200 and reading 0xfe104000 there faults: do not add the Pi 4 driver without
  a real board to try it on. Never print or reuse a word taken from the pool.
- The servo bus through another machine (docs/netbus.md): `servo via` sets k[4262] (address) and k[4263] (port);
  `transact` then calls `network.bus_exchange`. `board/busbridge.py` must keep passing on ONLY packets that read
  (instructions 1, 2, 0x82): it is the one thing between a network and the arm's motors. Never add a write there.
- The heap (cancho docs/freestanding.md, section 8): the compiler's bare runtime has `malloc` and `free` over the
  memory the regions use, so `std.buffer`, `std.vec`, `std.json` build here. `heap` in the shell tries it. The kernel
  holds the `Heap` capability and lends it only to what needs it: keep regions for anything with a known size, and
  never use the heap in a path that must not fail (no memory left is a trap, not an answer).
- BOOT.TXT (docs/boot.md): `src/boot.cho` (pure) holds the list of lines the kernel may type to itself at its
  start. Adding a command to that list is a decision: nothing that changes the disk, loads a kernel or restarts.
  The file is written at the console only (`files.boot_name`, `files.put_name`). A key in the first second stops it.
- `restart` (docs/restart.md) holds the `pm` capability, the watchdog's two registers; no other function may.
  It is due 50 ticks after it is asked (k[4261]; `getc` answers -6), so that what was said has left.
- All shell output goes through `putc`: never write to the UART elsewhere. Over SSH it is queued in `k`.
- `put` (docs/update.md): `sshd.step` answers 4 with file bytes in `rline` while k[4258] > 0; the kernel moves
  them to the staging memory and `disk.store` writes them. The hash is checked twice (what came, what the disk
  gives back) before the directory entry changes: keep both. `disk.boot_name` lists what the firmware reads;
  over SSH only `put` changes those. Never `put` a kernel to the real board that has not booted in QEMU.
- Three boards, two links. `MACHINE=virt` is QEMU's own board (RAM at 1 GB: every RAM address in the kernel
  is `k[14] +` an offset, and each capability's bound lists the Pi's addresses and virt's). build.sh links
  `build/kernel-virt.elf` for it. The virtio card's memory is the `dma` capability, 64 KB the link script
  reserves; `narrow` cuts at most eight pieces, so `main` cuts the last one again.
