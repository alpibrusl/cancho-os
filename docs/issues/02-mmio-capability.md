# Volatile MMIO as a capability: `Mmio(base, len)`

**Today:** cancho has no volatile load/store, so every driver needs C (`board/board.c` in cancho-os).

**Proposal:**
- A capability `Mmio(base, len)` obtained only by narrowing a root hardware capability (on bare metal,
  what `split(world)` hands the kernel; absent on hosted targets).
- Builtins `mmio_read32/64(m: &Mmio, off: int) -> [mmio] int`, `mmio_write32/64(m: &!Mmio, off, v)`,
  bounds-checked against `len` (trap, consistent with defined-behaviour.md), emitted as LLVM
  `load/store volatile`.
- Barriers: `dmb`/`dsb` equivalents as builtins (or `fence` in IR).
- `cancho authority` reports the exact ranges: `mmio(0xFE201000..0xFE201048)`.

**Why it matters:** the authority report then says which hardware a driver can touch — a property no
mainstream kernel language gives you at compile time.

**Deletes in cancho-os:** the UART/GPIO parts of `board.c`; drivers become cancho.
