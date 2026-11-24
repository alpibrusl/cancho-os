# Roadmap and decisions (2026-11-24)

## Decisions
- **Pure cancho, no Linux kernel.** First target: Raspberry Pi 4 (bare metal), developed on QEMU raspi3b.
  Pi 5 avoided for bare metal (I/O behind RP1 over PCIe, poorly documented).
- **Terminal = UART.** USB keyboard on the Pi (DWC2 / VL805 xHCI) is deferred indefinitely.
- **Toolchain:** cancho emits target-neutral LLVM IR; clang compiles it for `aarch64-none-elf`.
  The only host-specific line is the trap (`ud2` on x86 hosts), patched in build.sh.

## Tracks
1. **Pi kernel (this repo, active).**
2. **LG Gram (x86-64, later):** cancho as a UEFI application (PE/COFF). UEFI ConIn/ConOut give a
   terminal immediately; after ExitBootServices: GOP framebuffer + bitmap font + i8042 keyboard
   (Gram internal keyboard is very likely PS/2 via the EC; touchpad is I2C-HID). Same compiler
   gaps as the Pi, on x86-64.
3. **Not chosen, for reference:** cancho as PID 1 on a Linux kernel (Android model) — fastest way to
   a cancho-owned userland on real laptops/phones; rejected for now in favour of "no Linux".

## No C (2026-11-24)
- Every driver is cancho. `board/boot.S` keeps boot, the exception stub and eleven primitives of one
  or two instructions; `board/board.c` is 27 lines of libc stubs for cancho's hosted runtime.
- One `kernel8.img` for Pi 3 and Pi 4: the kernel reads MIDR_EL1 to tell them apart.
- Next: the compiler's bare-metal target and freestanding runtime (issues 01, 03) delete `board.c`
  and the build's workarounds; MMIO builtins (issue 02) delete the primitives.
- Pi 5: the SoC debug UART, GIC and timer would work the same way; needs its addresses from the
  BCM2712 documentation and a board to test on (QEMU has no model). Not started.

## Milestones
1. ✅ UART shell (help/about/echo) — boots in QEMU; not yet tried on real hardware.
2. ✅ Exception vectors, GIC-400 (Pi 4) / local IRQ controller (Pi 3), ARM generic timer — 100 Hz tick,
   `uptime`/`ticks`/`crash` in the shell; boots in QEMU raspi3b and raspi4b; not yet tried on real hardware.
   Since 0.0.4 interrupts are masked and polled after `wfi`, and a fault re-enters `main`: no handler
   outside cancho. Preemption (milestone 4) will need real interrupt entry (docs/issues/04).
3. MMU: identity map, then kernel/user split.
   - ✅ Identity map with the MMU and caches on: code read+execute, constants read-only, data/heap/stack
     read+write and never executable (WXN), peripherals as device memory, page 0 unmapped. The map is
     decided and the tables are filled in cancho (`memory_map`, `map` in `src/kernel.cho`). `mem`,
     `crash null`, `crash write` in the shell. QEMU raspi3b and raspi4b; not yet on real hardware
     (the data cache is enabled without an invalidate first — check on a real Pi).
   - Kernel/user split (TTBR1 for the kernel, EL0, per-task tables): with milestone 4, which gives it a user.
4. Tasks, scheduler, capability-based IPC (seL4-like; cancho's effect rows ≈ capabilities).
5. Framebuffer via firmware mailbox + bitmap font (text on HDMI).
6. SD card (EMMC2) + FAT; load programs.
7. Userland ABI + small libc (or a Linux-syscall compatibility layer à la Asterinas) — needed
   before any clang-compiled C program can run. Until then, C only links *into* the kernel.

## Prior art
seL4 (capabilities), Redox, Theseus, Hubris, Asterinas (Linux ABI in a Rust kernel),
rust-raspberrypi-OS-tutorials, bztsrc/raspi3-tutorial, Circle.

## Cautions
- Don't have agents translate Linux drivers: the result is likely a GPL derivative. Write from
  datasheets (BCM2711 peripherals, PL011, GIC-400, virtio spec).
