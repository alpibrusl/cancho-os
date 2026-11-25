# cancho-os — context for agents

Goal: an OS written in cancho (https://github.com/alpibrusl/cancho), no Linux underneath.
Read README.md (build, layout) and docs/ROADMAP.md (decisions, tracks, milestones) first.

Rules of the road
- Everything is cancho (`src/`), drivers included. `board/boot.S` holds only boot and the exception
  stub, and exports nothing to cancho: never add logic or a callable symbol there. The kernel has no
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
