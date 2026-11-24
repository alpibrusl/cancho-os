# cancho-os — context for agents

Goal: an OS written in cancho (https://github.com/alpibrusl/cancho), no Linux underneath.
Read README.md (build, layout) and docs/ROADMAP.md (decisions, tracks, milestones) first.

Rules of the road
- Kernel logic is cancho (`src/`). C/asm (`board/`) only for what cancho cannot express yet;
  each shim names the compiler issue (docs/issues/) that would delete it.
- Hardware is a capability: drivers are foreign library "board" until cancho has MMIO builtins.
  `cancho authority src/kernel.cho` must list exactly the board symbols in use — check it in review.
- Every milestone must boot in QEMU in CI (.github/workflows/qemu.yml) with a scripted shell check.
- Build compiler from seed: `sh scripts/seed-build.sh --out /tmp/cseed` in the cancho repo;
  `CANCHO=/tmp/cseed/cancho0 ./build.sh`.
- QEMU 8.x has only raspi3b; raspi4b needs QEMU ≥ 9. Pi 4 images are built with BOARD=pi4.
