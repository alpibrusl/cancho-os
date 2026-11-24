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

## Milestones
1. ✅ UART shell (help/about/echo) — boots in QEMU; not yet tried on real hardware.
2. Exception vectors, GIC-400 (Pi 4) / local IRQ controller (Pi 3), ARM generic timer.
3. MMU: identity map, then kernel/user split.
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
