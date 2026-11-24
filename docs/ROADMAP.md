# Roadmap and decisions (2026-11-24)

## Decisions
- **Pure cancho, no Linux kernel.** First target: Raspberry Pi 4 (bare metal), developed on QEMU raspi3b.
  Pi 5 avoided for bare metal (I/O behind RP1 over PCIe, poorly documented).
- **Terminal = UART.** USB keyboard on the Pi (DWC2 / VL805 xHCI) is deferred indefinitely.
- **Toolchain:** `cancho build --target aarch64-none-elf --emit obj`, then the boot stub and `ld.lld`
  with our own link script.

## Tracks
1. **Pi kernel (this repo, active).**
2. **LG Gram (x86-64, later):** cancho as a UEFI application (PE/COFF). UEFI ConIn/ConOut give a
   terminal immediately; after ExitBootServices: GOP framebuffer + bitmap font + i8042 keyboard
   (Gram internal keyboard is very likely PS/2 via the EC; touchpad is I2C-HID). Same compiler
   gaps as the Pi, on x86-64.
3. **Not chosen, for reference:** cancho as PID 1 on a Linux kernel (Android model) — fastest way to
   a cancho-owned userland on real laptops/phones; rejected for now in favour of "no Linux".

## Direction (2026-11-24)
- **Independent of C and Linux, and only cancho runs here.** Bare metal on few boards rather than a
  guest of someone else's kernel. The loader, when there is one, accepts checked cancho and nothing else.
- **First real job: a robot's safety controller** (cancho-robot's SO-101 arms). The claim to earn: the
  only program that can move the arm is the safety core, for the whole machine and not for one process.
- **The human is the source of authority, not the operator:** grants, approves what cannot be undone,
  reads the record, holds the off switch.
- **Board for the robot: Pi 5.** Developed in QEMU on the Pi 3/4 models with a simulated servo bus, then
  moved. Needs from hardware: the debug UART for the console, a header UART behind RP1 for the bus.
- **The model stays on another machine** (cancho-gpu needs Metal or CUDA, which need macOS or Linux).

### Robot steps
1. ✅ Read-only bus in QEMU: second UART, Feetech PING and READ, six simulated servos (`servo scan`,
   `servo pos`).
2. ✅ Calibration and forward kinematics from cancho-robot, unchanged, on the bare target (`arm zero`,
   `arm pose`). `std.math` is pure cancho, so it needed nothing from a libc; what it did need was two
   fixes to the compiler's bare target (hosted support modules were written whenever `--std` was given,
   and statics are made with `calloc`). Inverse kinematics is not here yet: it comes with step 3.
3. The safety core as the only holder of the bus; a motion request that goes through it or not at all.
4. Pi 5: console on the debug UART, addresses from the board's own device tree, then the bus behind RP1.
5. The real arm, read-only first, checked against LeRobot reading the same bus.

## No C (2026-11-24)
- There is no C in the repository. Every driver is cancho; `board/boot.S` keeps boot, the exception
  stub and eleven primitives of one or two instructions.
- The compiler has a bare-metal target (`--target aarch64-none-elf`, cancho `docs/freestanding.md`):
  no libc in the object, regions from the memory the link script names. That closed issues 01 and 03.
- One `kernel8.img` for Pi 3 and Pi 4: the kernel reads MIDR_EL1 to tell them apart.
- Next in the compiler: MMIO builtins behind a capability (issue 02) delete the primitives; a rule
  that refuses a hosted builtin on the bare target instead of leaving it to clang.
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
