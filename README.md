# cancho-os — a cancho shell on bare-metal Raspberry Pi

No Linux and no C: the firmware loads `kernel8.img`, a page of assembly
drops to EL1 and calls `main`, and everything after that is cancho — the PL011 UART
driver, the timer and interrupt controller, the page tables, the fault report, the shell.

```
src/kernel.cho   the kernel, drivers included (cancho)
board/boot.S     boot (park cores 1-3, EL2 -> EL1, stack, zero .bss), the exception stub,
                 and the primitives cancho cannot spell yet, one or two instructions each:
                 load/store a byte, word or doubleword, read/write a system register, wfi
board/link.ld    load at 0x80000; code, constants and data on page boundaries
build.sh         cancho build --target aarch64-none-elf, assemble boot.S, link, objcopy
run.sh           boot it in QEMU
test.sh          boot it in QEMU, type the given lines, print the UART (what CI runs)
```

Hardware is a capability: the primitives are the foreign library `"board"`, so
`cancho authority src/kernel.cho` lists exactly the eleven `board:` symbols the kernel
is built on and says it never touches anything else. They are coarse (`board_w32`
reaches any address); docs/issues/02 replaces them with builtins bounded by address range.

Two choices keep everything in cancho without the compiler's help:

- **Interrupts are polled.** They stay masked in the CPU; the timer still raises its line,
  which wakes `wfi`, and the kernel then asks the interrupt controller what happened. No
  handler runs behind the program's back, so there is no state shared with one.
- **A fault enters `main` again.** The exception stub records ESR/ELR/FAR, resets the
  stack and calls `main`, which sees the record, reports it on the UART and halts.

## Build and run

Needs a `cancho` with the bare-metal target (cancho `docs/freestanding.md`; in the cancho
repo, `sh scripts/build-standalone.sh --out /tmp/cancho-out --rev $(git rev-parse HEAD)`, then
`CANCHO=/tmp/cancho-out/cancho`), clang, ld.lld, llvm-objcopy, qemu-system-aarch64.

```sh
./build.sh && ./run.sh            # QEMU raspi3b
./test.sh about ticks crash       # scripted: type three lines, print what came back
MACHINE=raspi4b ./test.sh about   # the same image as a Pi 4 (QEMU >= 9)
```

On macOS: `brew install llvm lld qemu` and put `$(brew --prefix llvm)/bin` on `PATH`
(Apple's clang has no `llvm-objcopy`).

Shell: `help`, `about`, `echo <text>`, `uptime` (from the ARM counter), `ticks` (timer
interrupts taken), `mem` (the memory map), and three ways to fault on purpose, each named
by the kernel with ESR/ELR/FAR before the core halts: `crash` (out-of-bounds
read, caught by cancho's own check), `crash null` (page 0 is unmapped), `crash write`
(kernel code is read-only).

## Real Pi 4

SD card, FAT32, with `start4.elf` and `fixup4.dat` from
https://github.com/raspberrypi/firmware/tree/master/boot, plus `kernel8.img` and this `config.txt`:

```
arm_64bit=1
kernel=kernel8.img
enable_uart=1
dtoverlay=disable-bt
```

`disable-bt` puts the PL011 on GPIO14/15. USB-serial cable (3.3 V!): GND→pin 6,
RX→pin 8 (GPIO14, TXD), TX→pin 10 (GPIO15, RXD). Then `picocom -b 115200 /dev/ttyUSB0`.

## How it is built, and what is left to remove

- `cancho build --target aarch64-none-elf --emit obj` writes an ELF object with no libc in
  it: regions take their 64 KB chunks from the memory `board/link.ld` names
  (`__cancho_heap_start` to `__cancho_heap_end`), and `memset`/`memcpy` are the module's
  own. `nm -u` on the kernel object lists the eleven `board_` primitives, those two
  symbols, and nothing else.
- What is left outside cancho is `board/boot.S`: boot, the exception stub, and the
  primitives. The primitives become builtins behind a capability (docs/issues/02), which
  also lets the authority report name the address ranges a driver touches.

Context and decisions: [`docs/ROADMAP.md`](docs/ROADMAP.md). Compiler issues to file in cancho: [`docs/issues/`](docs/issues/).

## Next milestones

3. (identity map done) kernel/user split, together with
4. tasks, scheduler, capability IPC
5. framebuffer via the firmware mailbox
6. SD card + FAT
