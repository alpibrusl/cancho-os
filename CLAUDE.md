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
- A real Pi 4 has booted it (README, "On a real Pi 4"): one board, one session. Say exactly that, and
  keep "measured in QEMU" on everything that was not seen on the board.
- The Pi 5 (docs/pi5.md) is the one board whose code no test runs: QEMU has none. Do not describe it as
  working, and do not add a Pi 5 driver (RP1, the RNG200, USB) before the console has been seen on a real board.
- Three files, none near 2,000 lines: `src/kernel.cho` (boot, memory, shell, servo and arm), `src/base.cho`
  (console output, clock, bus bytes), `src/network.cho` (links, generator, session, network commands). A
  new network command goes in `network.net_command`, never in the shell's loop.
- The kernel's address, mask, gateway and name server are k[4154..4157] (docs/addresses.md); nothing may
  assume 10.0.0.2. DHCP and DNS answers are parsed by `inet` and must have a no-trap test like the others.
- `tcp_connect` is a name of cancho's prelude, and `where` a keyword: `inet` says `tcp_dial`.
  A command that waits on the network (`http`) sets k[39] so `session` leaves the shell's connection alone.
- Randomness (docs/random.md): `rng_word` reads the generator, the pool at k[4136..] is what other code takes
  from. QEMU's raspi4b has no RNG200 and reading 0xfe104000 there faults: do not add the Pi 4 driver without
  a real board to try it on. Never print or reuse a word taken from the pool.
- The shell on port 23 (`net shell on`, docs/network.md section 8) has no password and no encryption. It must
  stay off by default and openable only from the serial console, and it must be removed or put behind SSH
  before any command can move a servo. All shell output goes through `putc`: never write to the UART elsewhere.
- Three boards, two links. `MACHINE=virt` is QEMU's own board (RAM at 1 GB: every RAM address in the kernel
  is `k[14] +` an offset, and each capability's bound lists the Pi's addresses and virt's). build.sh links
  `build/kernel-virt.elf` for it. The virtio card's memory is the `dma` capability, 64 KB the link script
  reserves; `narrow` cuts at most eight pieces, so `main` cuts the last one again.
