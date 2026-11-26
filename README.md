# cancho-os — an operating system written in cancho, on bare metal

Site: https://alpibrusl.github.io/cancho-os/

Raspberry Pi first: that is the board it boots on today (Pi 3 and Pi 4 in QEMU, and QEMU's own
`virt` machine, which is where the network card is; a Pi 5 is the
robot's board and is next). Nothing in the design is tied to it: the shell, the servo
protocol, the kinematics and the safety core are plain cancho, and what is specific to the
board is the boot assembly, three drivers and the page-table format. A PC with UEFI is the
planned second target (docs/ROADMAP.md).

No Linux and no C: the firmware loads `kernel8.img`, a page of assembly
drops to EL1 and calls `main`, and everything after that is cancho — the PL011 UART
driver, the timer and interrupt controller, the page tables, the fault report, the shell.

```
src/kernel.cho   the kernel, drivers included (cancho)
src/feetech.cho  the Feetech servo protocol, read side only        } vendored from
src/calibration.cho, kinematics.cho, so101.cho  ticks to degrees,  } cancho-robot,
                 and the SO-101's forward kinematics               } unchanged
src/safety.cho   the safety core: one `approve` every motion must pass }
src/inet.cho     the network: SLIP, IPv4, ping and UDP echo; holds no hardware
sim/servos.cho   six simulated servos for QEMU: a program for the host, not in the image
sim/expect.cho   what `arm pose` must print for them, computed on the host
sim/netpeer.cho  the other end of the network link for QEMU, also a program for the host
board/boot.S     boot (park cores 1-3, EL2 -> EL1, stack, zero .bss) and the exception stub.
                 Nothing in it is called by cancho
board/link.ld    load at 0x80000; code, constants and data on page boundaries; the
                 translation tables at 2 MB
build.sh         cancho build --target aarch64-none-elf, assemble boot.S, link twice (Pi, virt), objcopy
authority.sh     what the kernel can touch is docs/authority.txt, and a function lent one
                 device cannot use another (what CI runs)
run.sh           boot it in QEMU
test.sh          boot it in QEMU, type the given lines, print the UART (what CI runs)
```

Hardware is a capability. A register is reached through an `Mmio`, whose type names the
addresses it holds (cancho `docs/mmio.md`): `main` is given every address and cuts it into
eight pieces that share none (the console, its pin register, the interrupt controller, the
servo bus, the translation tables, the kernel's code to read, two bytes for the
`crash` commands, and the word where a fault is noted), and each function is lent the pieces it needs. So the function that
prints a character has this type, and the compiler holds it to it:

```
fn putc[&mc, &s](con: &!mc Mmio("0x3f201000..0x3f201048,0xfe201000..0xfe201048"), k: &!s [int], c: int)
    -> [mmio("0x3f201000..0x3f201048,0xfe201000..0xfe201048")] int
```

It cannot reach the servo bus: `./authority.sh` builds a copy of the kernel in which a
function lent only the console writes to the bus, and requires the compiler to refuse it.
The processor's own registers work the same way, through the `Cpu` capability (cancho
`docs/cpu.md`): `cpu_read(cpu, "cntvct_el0")` is one instruction, and the row of a function
names each register it reaches, so the one that advances the timer is
`fn tick(cpu: &!Cpu, ...) -> [cpu("cntv_cval_el0")]` and cannot turn the MMU off.

The kernel calls no foreign code at all. The same script holds `cancho authority` on it to
[`docs/authority.txt`](docs/authority.txt): every address and every system register the
kernel touches, and the line "never touches ... foreign code". The vendored robot modules
(protocol, kinematics, safety) take no capability at all.

What this does not show: that an address is the device the comment says it is (that is the
datasheet's word), that a value written to a register is a sane one, or anything about the
page of assembly that runs before `main`.

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
SERVOS=1 ./test.sh 'servo scan'   # with the simulated servo bus on the second serial port
```

On macOS: `brew install llvm lld qemu` and put `$(brew --prefix llvm)/bin` on `PATH`
(Apple's clang has no `llvm-objcopy`).

Shell: `help`, `about`, `echo <text>`, `uptime` (from the ARM counter), `ticks` (timer
interrupts taken), `mem` (the memory map), and three ways to fault on purpose, each named
by the kernel with ESR/ELR/FAR before the core halts: `crash` (out-of-bounds
read, caught by cancho's own check), `crash null` (page 0 is unmapped), `crash write`
(kernel code is read-only). `servo scan` and `servo pos` are described below.

## The robot

The first real job for cancho-os is the safety controller of a robot arm (the SO-101 arms
of [cancho-robot](https://github.com/alpibrusl/cancho-robot)): a machine where the only
program that can reach the servo bus is the one the kernel hands it to.

Today the kernel can talk to the bus and only read: `servo scan` pings ids 1 to 8,
`servo pos` reads each servo's position. It contains no packet that can move a servo.

It also knows where the arm is. `arm pose` reads the five joints, turns ticks into degrees
with the arm's calibration and runs the SO-101's forward kinematics; `arm zero` does the
same for the all-zero pose, with no bus. That code is cancho-robot's, where it is held to
LeRobot and to the placo solver. Two checks say it computes the same with no system under
it: `arm zero` prints the position placo gives (391361, -9, 226469 micrometres), and
`arm pose` prints, line for line, what the same sources print when built for the host
(`build/expect`). Both compare at the printed precision (a micrometre, a thousandth of a
degree), not bit for bit.

And it can judge a motion without making it. `arm check 5 14 33 -41 44` asks the safety
core (cancho-robot's `safety.approve`, unchanged) whether the arm may go to those five
angles from where it is: joint limits, the workspace, the jump bound, collisions with the
tower and the tray, then the speed clamp. It answers `approved` with the goals it would
send, or `refused:` with the rule, and always ends `nothing was sent`. CI sends four
requests with four different verdicts and compares them with the host, as above. Actually
sending a goal waits for cancho-robot's actuation core, which is still in review there.
In QEMU the bus is the board's second serial port, connected by `test.sh` to
`sim/servos.cho`. The simulator is a model written from the protocol, not a recording of
a servo, so it can share a misreading with the driver; the real check is the arm.

The target board is a Pi 5, which QEMU does not model. What changes there is the address
table and the four `bus_` functions (a PL011 behind the RP1 chip instead of the mini
UART); the protocol, and everything built on it, does not. Not verified in QEMU: timing at
1 Mbaud, half-duplex behaviour, RP1.

## The network

The kernel answers `ping` and a UDP echo over two links: a serial line (SLIP) on the second
serial port of a Pi, and Ethernet, with ARP, through a virtio network card on QEMU's `virt`
machine. No TCP yet, and no real network card: QEMU's Pi 4 has no Ethernet controller, so the
Pi's own is for the day a board boots. [docs/network.md](docs/network.md) has the reasoning and
what is checked; [docs/drivers.md](docs/drivers.md) the order of the drivers.

```
NET=1 ./test.sh 'net up' 'echo wait' 'echo wait' net   # sim/netpeer.cho is the other end of the line
sudo ./ping.sh                                          # Linux: the system's own ping, over a pty
MACHINE=virt UDP=hello ./test.sh 'net up' net           # Ethernet: a datagram from this machine to the kernel
sudo MACHINE=virt ./ping.sh                             # Linux: ping over a tap interface, ARP first
```

```
> net up
link up: SLIP on the second serial port, address 10.0.0.2
0 packets answered, 0 dropped
> net
link up: SLIP on the second serial port, address 10.0.0.2
3 packets answered, 1 dropped (the last: checksum)
peer: 3 replies to 4 packets, as it should be
```

In CI the system's `ping` on Linux gets 5 replies to 5 requests from the kernel in QEMU.

The code that reads packets from outside, `src/inet.cho`, holds no capability: its functions have
the empty row, so it cannot reach a register or a servo. The kernel's authority report did not
change when the network was added.

## On a real Pi 4

**Not tried yet.** Every claim in this file was measured in QEMU. The steps below are what
should boot it on a board; if you run them, what the serial console prints (or does not) is
worth an issue.

You need a Raspberry Pi 4, a microSD card and a USB-serial cable with **3.3 V** levels (a
5 V one damages the pins).

1. **Build the image** (above): `./build.sh` writes `build/kernel8.img`, about 64 KB.
2. **Put the firmware on the card.** The Pi's own firmware loads the kernel; it is not part
   of this repository. Either flash Raspberry Pi OS Lite with Raspberry Pi Imager, which
   leaves the firmware on the card's FAT partition (`bootfs`), or format the card FAT32 and
   copy `start4.elf` and `fixup4.dat` from
   https://github.com/raspberrypi/firmware/tree/master/boot.
3. **Copy two files** to that partition, replacing what is there: `build/kernel8.img` and
   `board/config.txt`. On a Mac with the card mounted as `bootfs`:

   ```
   cp build/kernel8.img board/config.txt /Volumes/bootfs/ && diskutil eject /Volumes/bootfs
   ```

   `config.txt` is four lines: 64-bit, this kernel, the UART on, and `disable-bt`, which
   puts the PL011 on GPIO14/15 instead of the Bluetooth chip.
4. **Wire the cable** to the 40-pin header: GND to pin 6, the cable's RX to pin 8 (GPIO14,
   the Pi's TXD), the cable's TX to pin 10 (GPIO15, the Pi's RXD). Leave the cable's power
   wire unconnected.
5. **Open the console, then power the Pi.** 115200 baud, 8N1:

   ```
   screen /dev/cu.usbserial-XXXX 115200      # macOS; the name depends on the cable
   picocom -b 115200 /dev/ttyUSB0            # Linux
   ```

   It should print ``cancho-os booted. type `help`.``, and `about` should say `(Raspberry Pi 4)`.
   Then `ticks`, `uptime`, `crash null`.

What QEMU does not model, so where a real board may differ:

- **The data cache.** The kernel turns it on with the MMU and does not invalidate it first.
  QEMU has no cache. A hang right after boot points here.
- **The UART clock.** The divisor is for 48 MHz, the Pi 4's default. Garbage on the console
  points here (`init_uart_clock=48000000` in `config.txt` pins it).
- **The servo bus does not work on a Pi 4 header yet.** It is the mini UART, whose only
  header pins are the two the console uses. It has to move to another PL011 (UART3, on
  GPIO4/5) before a real arm can be read.

## How it is built, and what is left to remove

- `cancho build --target aarch64-none-elf --emit obj` writes an ELF object with no libc in
  it: regions take their 64 KB chunks from the memory `board/link.ld` names
  (`__cancho_heap_start` to `__cancho_heap_end`), and `memset`/`memcpy` are the module's
  own. `nm -u` on the kernel object lists those two symbols and nothing else.
- What is left outside cancho is `board/boot.S`: boot and the exception stub, which run
  before `main` or instead of it. The eleven primitives it used to export are gone:
  cancho has loads and stores behind the `Mmio` capability (edition 13) and system
  registers behind `Cpu` (edition 14). What the kernel needs from the link is two words
  at a fixed place in the image, and the fault stub leaves one word saying which vector.

Context and decisions: [`docs/ROADMAP.md`](docs/ROADMAP.md). Compiler issues to file in cancho: [`docs/issues/`](docs/issues/).

## Next milestones

3. (identity map done) kernel/user split, together with
4. tasks, scheduler, capability IPC
5. framebuffer via the firmware mailbox
6. SD card + FAT

## Licence

[EUPL-1.2](LICENSE). Which hardware is supported, and what each driver is written from, is in
[docs/drivers.md](docs/drivers.md): a driver follows a permissively licensed reference so that
the whole stays under this licence.
