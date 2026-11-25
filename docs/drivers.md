# Drivers: which hardware, and what each driver is written from

> **Status: a plan.** Nothing in this file is built except where it says so. The licence facts were read
> from each file's own header on 2026-11-26; the sizes are estimates from the file's size, not counts.

## 1. The rule

cancho-os does not try to run on everything. It supports **named boards**, each with a short list of
devices, and a driver exists only for a device on that list. A driver is written in cancho from two
things: the device's own documentation, and one existing driver read as a reference for the sequences the
documentation leaves out. It is not a line-by-line translation, and it is checked against something that
is not itself (for the network: another system's stack on the other end, as `ping.sh` does).

## 2. The licence decides which reference

cancho-os is under the EUPL-1.2 ([`LICENSE`](../LICENSE)).

- **A driver written from a BSD, ISC or MIT source stays EUPL.** Those licences ask that their copyright
  notice and permission text be kept: a file here that follows such a source says so at its top and
  carries the notice.
- **A driver written from a GPL source would not.** The EUPL's Article 5 lets a work that combines EUPL
  code with code under a listed compatible licence (GPL v2 and v3 are listed) be distributed under that
  licence, and says the compatible licence's obligations prevail. So following a Linux driver is allowed,
  and the price is that the combined kernel is distributed under the GPL.

So the reference is a permissively licensed driver wherever one exists, and for every device below one
does. This is a reading of the licence texts by the project, not legal advice.

## 3. The boards

| | Pi 4 | Pi 5 | LG Gram |
|---|---|---|---|
| state | boots in QEMU; not tried on the board | not started | not started |
| boot | the Pi firmware loads `kernel8.img` | the same, and `pciex4_reset=0` so the firmware's PCIe set-up for RP1 is kept | a UEFI application (docs/ROADMAP.md) |
| console | PL011 on the header (built) | the PL011 of the debug connector | UEFI's console first |
| Ethernet | GENET, memory-mapped | Cadence GEM inside RP1, behind PCIe | **not known: read the machine** (many models have none, and use a USB adapter) |
| Wi-Fi | Broadcom CYW43455, on SDIO | the same chip family, on SDIO | **not known: read the machine** (likely Intel, on PCIe) |

The Gram's row waits for the machine itself: it was off when this was written. One command on it, under
any Linux, answers both cells: `lspci -nn | grep -Ei 'net|wireless|ethernet'` (and `lsusb` for an adapter).

## 4. The drivers, in order

| # | device | board | reference read | its licence | size of the reference | can CI test it |
|---|---|---|---|---|---|---|
| 1 | virtio-net (**built**, [`network.md`](network.md) section 6) | QEMU `virt` | the VIRTIO specification | an OASIS standard | — | **yes** |
| 2 | GENET Ethernet | Pi 4 | NetBSD `sys/dev/ic/bcmgenet.c` (FreeBSD's `if_genet.c` beside it) | BSD, 2 clauses | about 900 lines (1,450) | no: QEMU's Pi 4 has no such device |
| 3 | Cadence GEM Ethernet | Pi 5 | OpenBSD `sys/dev/fdt/if_cad.c` (FreeBSD's `if_cgem.c`, BSD-2-Clause) | ISC | about 1,600 lines | no |
| 4 | CYW43455 Wi-Fi | Pi 4, Pi 5 | OpenBSD `bwfm.c` and `if_bwfm_sdio.c`; 9front's `ether4330.c` | ISC; MIT (the repository's, the file has no header) | about 2,800 + 1,200; about 1,500 | no |
| 5 | the Gram's own | Gram | to be chosen once the hardware is read | | | no |

Why this order:

1. **virtio-net first**, because it is the only Ethernet device a CI run can exercise. Ethernet framing,
   ARP and, later, TCP are built and tested there, under the stack `src/inet.cho` already is. It needs a
   new board in the kernel: QEMU's `virt` machine (another UART address, another interrupt controller).
2. **GENET second**, on a Pi 4 that boots. It is the first driver the controller reads and writes memory
   for on its own (DMA), which needs two things the kernel does not have: memory for packets at addresses
   the driver may hand out, as a capability, and the processor's cache-maintenance instructions, which
   `Cpu` does not offer yet (a change to the compiler).
3. **The Pi 5's Ethernet third**: the same kind of driver, after RP1 is reachable, which the robot's
   serial ports need anyway.
4. **Wi-Fi last, and with a known cost.** The chip is a computer of its own: the driver loads a closed
   firmware file into it at start-up and then talks to that firmware. So cancho-os with Wi-Fi is no longer
   "only cancho runs", in the same way it already is not on a Pi, whose boot firmware is closed too. It
   also needs an SD-interface driver first. A cheaper Wi-Fi exists meanwhile: a small Wi-Fi module on a
   serial port speaking SLIP, which the kernel already answers.

## 5. What is not planned

USB network adapters (they need a USB host stack first), Bluetooth, and any device nobody here owns.
If the Gram's only Ethernet is a USB adapter, its network is its Wi-Fi card, and an Intel card's reference
driver (OpenBSD `if_iwx.c`) is about 11,000 lines: the largest item on this page by far.
