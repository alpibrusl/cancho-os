# Volatile MMIO as a capability: `Mmio(base, len)`

> **Done (2026-11-25):** cancho `docs/mmio.md`, edition 13. What was built differs from the draft below: the capability is
> `Mmio("lo..hi,lo..hi")`, its bound a literal of the type (as `Fs("/tmp")` is), not `Mmio(base, len)`; addresses are absolute; the
> builtins are `mmio_read8/32/64` and `mmio_write8/32/64`; the label is `mmio("<bound>")`. Not done: barriers, and system registers
> (see 04). The kernel's `board_r*`/`board_w*` are deleted. What follows is the issue as drafted.

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

**Also wanted by milestone 3 (page tables):** the same shape for RAM the kernel owns — a capability over
an address range with `read64/write64` — would let the page-table filler (`board_map`) be cancho, and
`msr` for `ttbr0_el1`/`tcr_el1`/`mair_el1`/`sctlr_el1` (see 04) would do the same for `board_mmu_on`.
