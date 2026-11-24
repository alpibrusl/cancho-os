# A freestanding runtime profile (no libc, no pthreads)

> **Done (2026-11-24):** `compiler/runtime/bare.ll` in cancho (`docs/freestanding.md` §4): regions from `__cancho_heap_start`..`__cancho_heap_end`, no pthreads, none of the hosted runtime in the module. `board/board.c` is deleted. Not done: a `World` shaped for a machine with no files, and a heap. What follows is the issue as drafted.

**Today:** after `--gc-sections`, what a minimal kernel still needs from libc is: `malloc`/`free`
(region chunks of 64 KB, `cancho_region_take/give`), `memset`/`memcpy`/`memmove`, and
`pthread_key_create/getspecific/setspecific` (the per-thread region-chunk stack). cancho-os stubs
them in `board.c` (bump allocator, single TLS slot).

**Ask:**
- A runtime profile for freestanding targets: regions backed by a caller-supplied arena
  (or an allocator capability), single-threaded region stack without pthreads.
- No references to the hosted runtime (`os_linux.ll`, spawn, signals, files) in the module at all,
  rather than relying on the linker to drop them.
- The `World` a freestanding `main` receives: which fields exist (no fs/net/args; a hardware root
  capability instead).

**Deletes in cancho-os:** the libc section of `board.c`.
