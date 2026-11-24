# Entering cancho from an exception: exported entry points and state that outlives a call

**Today:** nothing outside a cancho program can call into it (function symbols are internal names such
as `lexs_161`; `docs/function-values.md` §5 allows callbacks only with row `[]` and scalar parameters),
and there is no mutable state that outlives a call. So in cancho-os the IRQ handler, the tick counter
and the fault report are C (`board_irq`, `ticks`, `board_fault` in `board/board.c`); cancho can only
start the timer and poll what the handler counted.

**Ask:**
- A way to name a function as an entry point with a stable symbol and the C ABI
  (`export fn irq(frame: ...)`), so a vector stub can `bl` it.
- What such a function may hold: it is entered with no capability in hand. Either a capability placed
  at registration (`on_irq(hw, handler)`) or a kernel-owned static cell the handler is the sole borrower of.
- A rule for the data shared between handler and interrupted code (the tick count today, a run queue
  in milestone 4): the same question `threads.md` answers for threads, with "IRQs masked" as the lock.
- `mrs`/`msr` for a fixed list of system registers as builtins behind a capability (timer, `daif`,
  `esr_el1`, `elr_el1`, `far_el1`), so reading the counter is not a C function.
- Note for the backend: an entry point reached from an IRQ interrupts code that may be using FP/SIMD
  registers; either the entry saves them or the freestanding profile compiles without them.

**Deletes in cancho-os:** `board_irq`, `board_fault`, `board_ticks`, `board_uptime_ms`; the vector
stubs in `boot.S` stay but call cancho.
