# cancho-os — milestone 1: a cancho shell on bare-metal Raspberry Pi

No Linux. The firmware loads `kernel8.img`, 40 lines of assembly drop to EL1
and call `main`, and the rest is cancho talking to the PL011 UART.

```
src/kernel.cho   the kernel: line editor + shell (cancho)
board/boot.S     park cores 1-3, EL2 -> EL1, FP on, stack, zero .bss
board/board.c    UART driver (volatile MMIO) + the few libc symbols cancho's runtime calls
board/link.ld    load at 0x80000
build.sh         cancho -> LLVM IR -> clang --target=aarch64-none-elf -> kernel8.img
run.sh           boot it in QEMU
```

Hardware is a capability: the board is the foreign library `"board"`, so
`cancho authority src/kernel.cho` lists exactly `board:board_putc` and
`board:board_getc` and says the kernel never touches anything else.

## Build and run

Needs `cancho` (or the seed: `sh scripts/seed-build.sh --out /tmp/cseed` in the cancho repo,
then `CANCHO=/tmp/cseed/cancho0`), clang ≥ 15, ld.lld, llvm-objcopy, qemu-system-arm.

```sh
./build.sh && ./run.sh            # QEMU raspi3b
BOARD=pi4 ./build.sh              # real Pi 4
```

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

## Next milestones

2. exception vectors + GIC + ARM generic timer (needs `msr`/`mrs`: more asm or intrinsics)
3. MMU, identity map then kernel/user split
4. tasks, scheduler, capability IPC
5. framebuffer via the firmware mailbox
6. SD card + FAT
