# The Pi 5

> **Status: written, never run.** QEMU has no Pi 5, so unlike everything else in this repository this
> was not booted anywhere. Every address below was read from a running Pi 5; that the kernel works at
> them is a claim nobody has tested. What a first boot needs is at the end.

## Where the facts are from

A Raspberry Pi 5 Model B Rev 1.1 running Raspberry Pi OS (Linux 6.18), read over SSH on 2026-11-26:
its device tree (`dtc -I fs /proc/device-tree`), `/proc/cpuinfo`, and its boot loader's settings
(`rpi-eeprom-config`). Nothing was written to it.

| what | on the Pi 5 | how it is known |
|---|---|---|
| the processor | Cortex-A76: `CPU part 0xd0b` | `/proc/cpuinfo`; it is how `detect` knows the board |
| where the chip's own devices are | child address `0` of `soc@107c000000` is `0x10_0000_0000` | the node's `ranges` |
| the console | a PL011 at `0x107d001000` ("UART10", the three-pin connector between the HDMI ports) | `serial@7d001000`, `arm,pl011` |
| its clock | 44,236,800 Hz, so 115,200 baud is a divisor of exactly 24 | `clk-uart`, `clock-frequency = <0x2a30000>` |
| the interrupt controller | a GIC-400: distributor `0x107fff9000`, CPU interface `0x107fffa000` | `interrupt-controller@7fff9000`, `arm,gic-400` |
| the timer | the virtual timer is private interrupt 11, which is number 27 | `timer`, third entry; the same as a Pi 4 |
| RAM | starts at 0; the first block ends at `0x3fc00000` | `memory@0` |

The Pi 4's interrupt controller is the same part at another address, and its console the same part
with another clock. So the Pi 5 is a new row in `detect`, two more ranges in two capabilities, and one
more divisor: no new driver.

## What the kernel has on a Pi 5

The console and the shell, the timer, the MMU with its memory map, the fault report, and the commands
that need no hardware (`arm zero`). Nothing else:

- **No servo bus.** On this robot the two servo adapters are USB devices (QinHeng CH343, `1a86:55d3`),
  behind a hub on the RP1 chip's USB controller. Reaching them needs a USB host stack, which does not
  exist here. The header's serial ports are behind RP1 too. So `servo scan` says the board has no
  second serial port, which for this kernel is true.
- **No network.** The Ethernet controller is a Cadence GEM inside RP1 (`ethernet@100000`, at
  `0x1f00100000` once the firmware has set up PCIe); [`drivers.md`](drivers.md) has the plan. Wi-Fi is
  further still.
- **No randomness.** The generator is there (`rng@7d208000`, an RNG200, at `0x107d208000`) and has no
  driver: the same one the Pi 4 is waiting for ([`random.md`](random.md)), and equally untestable here.

## The boot stub

One line was added to `board/boot.S`: before leaving EL2 it gives `SCTLR_EL1` a known value (the bits
that must be one, the MMU off). The architecture leaves that register undefined at reset, QEMU happens
to leave it zero, and a real processor need not. This matters as much on a Pi 4.

## What is not known, and a first boot will say

- **Where the firmware puts the image.** The kernel is linked for `0x80000`. Raspberry Pi's documentation
  does not state the Pi 5's default; `board/config.txt` asks for it with `kernel_address`.
- **Which exception level it is entered at.** The stub handles EL2 and EL1.
- **Whether the firmware insists on a device tree file** on the card. The documentation's summary says
  it checks for one (`os_check`); `config.txt` turns the check off, and the steps in the README copy the
  file anyway.
- **Whether the console's clock is running** when the kernel starts. The boot loader on this board
  prints on the same port (`BOOT_UART=1`), so it should be.
- **The data cache,** turned on without being invalidated first, as on the Pi 4.

If nothing at all is printed, the first three are where to look, in that order; garbage means the clock.

## What a first boot needs

- **A cable for the debug connector**: three pins (JST-SH, 1 mm), 3.3 V, 115,200 baud. Raspberry Pi's
  Debug Probe has one. SSH is no use: it is Linux's, and Linux is not running.
- **A microSD card.** This board's boot order is `0xf461`: the SD card first, then NVMe. So with a card
  in, the Pi boots the card, and with it out, the Linux on the NVMe drive, untouched.
