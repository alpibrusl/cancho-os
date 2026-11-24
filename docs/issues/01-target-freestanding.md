# `--target aarch64-none-elf` (and x86_64-unknown-uefi): freestanding code generation

> **Done (2026-11-24):** `cancho build --target aarch64-none-elf --emit obj|ll` (cancho `docs/freestanding.md`, alpibrusl/cancho#826). Not done from the list below: `x86_64-unknown-uefi`, `--entry`. What follows is the issue as drafted.

**Today:** `--target` must equal the host triple. cancho-os works around it by capturing the IR via a
`--clang` wrapper and recompiling with `clang --target=aarch64-none-elf`.

**Found:** the IR is target-neutral except `cancho_trap`, whose inline asm follows the host
(`compiler/driver.cho` ~L342: `ud2` on x86-64, `udf #0xc11f` on aarch64). Built on x86-64, the IR
does not compile for aarch64.

**Ask:**
- Accept freestanding triples (`aarch64-none-elf`, `x86_64-unknown-uefi`) for `--emit obj`/`--emit ll`.
- Pick the trap instruction from the *target*, or use `llvm.trap`.
- `--emit ll` so tools don't need a clang wrapper.
- Optional: no `main(argc, argv)` wrapper; let the program name its entry (`--entry kmain`).

**Deletes in cancho-os:** `build/keepll.sh` wrapper and the `sed` on `ud2`.
