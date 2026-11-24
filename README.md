# cancho-os — a cancho shell on bare-metal Raspberry Pi

No Linux. The firmware loads `kernel8.img`, a page of assembly drops to EL1,
installs the exception vectors and calls `main`, and the rest is cancho talking
to the PL011 UART. A 100 Hz timer interrupt ticks underneath (milestone 2), and
the MMU is on with an identity map the kernel chose (milestone 3).

```
src/kernel.cho   the kernel: line editor + shell (cancho)
board/boot.S     park cores 1-3, EL2 -> EL1, FP on, stack, zero .bss, exception vectors
board/board.c    UART driver, timer + interrupt controller, page-table filler, fault
                 report, and the few libc symbols cancho's runtime calls
board/link.ld    load at 0x80000
build.sh         cancho -> LLVM IR -> clang --target=aarch64-none-elf -> kernel8.img
run.sh           boot it in QEMU
test.sh          boot it in QEMU, type the given lines, print the UART (what CI runs)
```

Hardware is a capability: the board is the foreign library `"board"`, so
`cancho authority src/kernel.cho` lists exactly the `board:` symbols the kernel
uses (ten today: UART, tick, memory map, and `board_peek`/`board_poke`) and says it
never touches anything else. `board_peek`/`board_poke` reach any address; they exist
only for the shell's `crash null` / `crash write` and go when there is a better test.

## Build and run

Needs `cancho` (or the seed: `sh scripts/seed-build.sh --out /tmp/cseed` in the cancho repo,
then `CANCHO=/tmp/cseed/cancho0`), clang ≥ 15, ld.lld, llvm-objcopy, qemu-system-arm.

```sh
./build.sh && ./run.sh            # QEMU raspi3b
BOARD=pi4 ./build.sh              # real Pi 4 (or MACHINE=raspi4b ./test.sh, QEMU >= 9)
./test.sh about ticks crash       # scripted: type three lines, print what came back
```

On macOS: `brew install llvm lld qemu` and put `$(brew --prefix llvm)/bin` on `PATH`
(Apple's clang has no `llvm-objcopy`).

Shell: `help`, `about`, `echo <text>`, `uptime` (from the ARM counter), `ticks` (timer
interrupts taken), `mem` (the memory map), and three ways to fault on purpose, each named
by the exception vector with ESR/ELR/FAR before the core halts: `crash` (out-of-bounds
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

## How it works, and what cancho would need to drop the shims

- cancho emits target-neutral LLVM IR; `build.sh` keeps it (a `--clang` wrapper)
  and compiles it for `aarch64-none-elf`. The one host-specific line is the trap
  instruction (`ud2` on x86), patched to `udf`. A real `--target aarch64-none-elf`
  in the compiler would remove both hacks.
- cancho's hosted runtime is still in the module; `--gc-sections` drops everything
  `main` doesn't reach. What's left needs malloc/free (regions take 64 KB chunks),
  memset/memcpy/memmove and three pthread TLS calls — stubbed in `board.c`.
- `board.c` exists because cancho has no volatile load/store. Adding
  `volatile_read32/write32` builtins gated by a capability (e.g. `Mmio(base,len)`)
  would let the UART driver itself be cancho — and the authority report would
  name the address ranges a driver can touch.

- The interrupt and fault handlers are C because nothing outside a cancho program can
  call into it, and it has no state that outlives a call (docs/issues/04).

Context and decisions: [`docs/ROADMAP.md`](docs/ROADMAP.md). Compiler issues to file in cancho: [`docs/issues/`](docs/issues/).

## Next milestones

3. (identity map done) kernel/user split, together with
4. tasks, scheduler, capability IPC
5. framebuffer via the firmware mailbox
6. SD card + FAT
