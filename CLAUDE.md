# cancho-os — context for agents

Goal: an OS written in cancho (https://github.com/alpibrusl/cancho), no Linux underneath.
Read README.md (build, layout) and docs/ROADMAP.md (decisions, tracks, milestones) first.

Rules of the road
- Everything is cancho (`src/`), drivers included. `board/boot.S` holds only boot, the exception
  stub and one-or-two-instruction primitives (load/store, system register, wfi) that cancho cannot
  spell yet; never add logic there. `board/board.c` is libc stubs for the runtime, not hardware,
  and is deleted by docs/issues/03. No new C.
- Hardware is a capability: the primitives are foreign library "board" until cancho has MMIO builtins.
  `cancho authority src/kernel.cho` must list exactly the board symbols in use — check it in review.
- Interrupts stay masked and are polled after `wfi`; a fault re-enters `main`, which reports it.
  So no code runs behind cancho's back and there is no shared mutable state (docs/issues/04).
- Every milestone must boot in QEMU in CI (.github/workflows/qemu.yml) with a scripted shell check.
- Build compiler from seed: `sh scripts/seed-build.sh --out /tmp/cseed` in the cancho repo;
  `CANCHO=/tmp/cseed/cancho0 ./build.sh`.
- QEMU 8.x has only raspi3b; raspi4b needs QEMU ≥ 9. One kernel8.img serves both: the kernel reads
  MIDR_EL1 (`detect` in kernel.cho). A new board is a new branch there, from its datasheet.
