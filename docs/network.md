# The network: IPv4 over a serial line first

> **Status: built, two slices.** The kernel answers `ping` and a UDP echo over two links: SLIP on the
> second serial port of a Pi 3 or Pi 4, and Ethernet through a virtio network card on QEMU's `virt`
> machine (section 7). All of it in QEMU. No TCP. Every number below was produced by the command
> next to it, at the commit that adds this file. Nothing here has run on a real board.

## 1. What was wanted, and what is in the way

A robot's controller that nothing can talk to is of little use, so the kernel needs a network. Three facts
decide where to start:

- **The Pi 4's Ethernet is the easy controller.** It is memory-mapped (GENET, at `0xfd580000`), so it fits
  the `Mmio` capability like every driver here. The Pi 3's sits behind USB and needs a USB host stack; the
  Pi 5's sits behind RP1, as the robot's serial ports do.
- **QEMU does not model it.** `info mtree` on `-M raspi4b` (QEMU 11.1.3) lists the USB controller and no
  Ethernet. A driver for it could only be tried on a real board, and this repository's rule is that every
  milestone boots in QEMU in CI.
- **The stack does not care what carries it.** Checksums, the IPv4 header, ICMP and UDP are the same over
  any link.

So the first slice is the stack, over the simplest link there is: SLIP (RFC 1055), IP packets on a serial
line with one byte marking the end of each. QEMU gives the board a second serial port, and a program on
the host can be the other end. The Ethernet driver is a second link under the same stack, for when a real
Pi 4 boots.

## 2. What is built

```
src/inet.cho     SLIP, Ethernet and ARP, the IPv4 header, ICMP echo, UDP echo. Pure: no capability, no trap
src/kernel.cho   net_poll: bytes from the port to inet, the reply back. `net up`, `net down`, `net`
sim/netpeer.cho  the other end of the line in QEMU: a program for the host
tests/inet_test.cho  inet on the machine that builds it
ping.sh          the kernel against Linux's own SLIP driver and the system's `ping` (CI)
```

- **The address is fixed:** the kernel is `10.0.0.2`. A serial line has two ends and no addresses on the
  wire, so there is no ARP.
- **Two things are answered.** An ICMP echo request gets an echo reply with the same identifier, sequence
  number and data. A UDP datagram to port 7 gets its data back. Everything else is dropped, and `net` says
  how many and why the last one was.
- **A packet is taken only if it is whole:** version 4, a header whose checksum holds, a length that fits
  what arrived, not a fragment, addressed to the kernel, and for ICMP and UDP a checksum that holds.
- **The port is shared with the servo bus.** The emulated boards have two serial ports and the second is
  the bus. `net up` gives it to the network and the servo commands then refuse; `net down` gives it back.
- **While the link is up the core does not sleep.** Interrupts are polled here and the tick is every
  10 ms, so a core in `wfi` would look at the port a hundred times a second. With `net up` the shell's
  wait loop polls the port instead of sleeping.

## 3. No new authority

`inet` holds no capability at all: its functions have the empty row, so the compiler says the code that
parses packets from outside cannot touch a register, a servo or memory it was not handed. The kernel's
part uses the capability the servo bus already had. `docs/authority.txt` is unchanged by this slice
(`./authority.sh`: "as recorded").

## 4. How it is checked

| | what | against |
|---|---|---|
| `cancho test tests/inet_test.cho src/inet.cho --std` | 20 tests | two published checksum vectors (RFC 1071 section 3; a worked IPv4 header); requests and replies built by a second implementation in another language (Python's `struct`, its own checksum); RFC 1055's escape bytes |
| the same, one test | 56,320 calls of `inet.answer` | every value of every byte of a good datagram, cut at five lengths: none traps, each is answered or dropped |
| `NET=1 ./test.sh 'net up' 'echo wait' 'echo wait' net` | the kernel in QEMU, `sim/netpeer.cho` on the port | three replies the peer insists on byte for byte, and one corrupted packet that must get none: "3 packets answered, 1 dropped (the last: checksum)" |
| `sudo ./ping.sh` (Linux, CI) | the kernel in QEMU, the port as a pty | Linux's SLIP driver and the system's `ping` and `nc`: not our packets and not our framing |

The fourth row on GitHub's `ubuntu-24.04` runner (QEMU as a Pi 3), on the commit before this file:
`5 packets transmitted, 5 received, 0% packet loss`, the datagram `cancho-os over udp` back unchanged, and
the kernel's own count after it, `6 packets answered, 0 dropped`.

The peer and the tests share their vectors, and the peer shares `inet`'s SLIP framing with the kernel: a
misreading of SLIP common to both would pass the third row. The fourth row is there for that.

## 5. What this does not do

- **No Ethernet, so no ARP and no cable.** The link is a serial line.
- **No TCP.** So no HTTP, no SSH, nothing with a connection.
- **The kernel never speaks first.** It answers; it cannot ping, resolve a name or send a datagram of its own.
- **No fragments, no IP options in a reply, no ICMP errors.** A datagram to a port nothing listens on is
  dropped in silence, where a full stack would say "port unreachable".
- **One address, written in the source.** No DHCP.
- **Not tried on a real board.** On a Pi the second serial port is the mini UART, whose only header pins
  are the console's (README, "On a real Pi 4"). And at a real line speed, polling may lose bytes that
  QEMU's flow control never loses here: the mini UART holds eight.
- **Nothing is timed.** No throughput or latency was measured; in QEMU it would say little.

## 6. Ethernet: a virtio card on QEMU's `virt` machine

*(Added with the second slice. Sections 2 to 5 describe the first and are still true of the Pi boards;
"no Ethernet, so no ARP" in section 5 is no longer true of the kernel as a whole.)*

The one Ethernet device a CI run can exercise is not on a Pi: it is virtio-net, on QEMU's own board. So
the kernel gained a third board and its first network card.

- **The board.** `virt` has a PL011 and a GIC like a Pi 4's, at other addresses, no second serial port,
  and RAM that starts at 1 GB instead of 0. The same two objects are linked twice (`build/kernel8.img`
  for a Pi, `build/kernel-virt.elf` for `virt`); the kernel knows the board from the processor QEMU is
  told to be (a Cortex-A57, which no Pi has) and keeps where RAM starts in its state. Each capability's
  bound gained the `virt` addresses beside the Pi's.
- **The driver** (`vnet_*` in `src/kernel.cho`, about 170 lines) follows the VIRTIO specification: find
  the card among 32 slots, accept two features (its address, and the current interface), set up two
  queues of eight entries, offer eight receive buffers, poll the ring of finished ones.
- **Two new capabilities, and nothing else new.** `vio` is the virtio slots' registers. `dma` is 64 KB of
  memory the card reads and writes on its own: the queues and the packet buffers, at a place the link
  script reserves, and every address the driver hands the card is inside it (the limits below say what
  that does and does not bound).
- **In `inet`:** `eth_answer` takes a frame. An ARP request for the kernel's address gets the card's
  (RFC 826); an IPv4 packet sent to the card gets what `answer` gives it, back to the card it came from.
  The kernel only replies, so it keeps no table of who is where.

Checked, at the commit that adds this section:

| | what | against |
|---|---|---|
| `cancho test tests/inet_test.cho src/inet.cho --std` | 29 tests (20 before) | frames built by the second implementation: an ARP request and reply, a ping and a datagram inside frames, padding to 60 bytes; 92,160 damaged frames, none traps |
| `MACHINE=virt ./test.sh about ticks mem 'crash null'` | the kernel on `virt` | the shell, the timer, the memory map at 1 GB, a fault reported |
| `MACHINE=virt UDP=... ./test.sh 'net up' net` | a datagram from the host through QEMU's user network | the same bytes back; the kernel counts two packets, the ARP answer and the echo |
| the same traffic captured (`-object filter-dump`) and read with `tcpdump` | by hand, once | "Reply 10.0.0.2 is-at 52:54:00:12:34:56", and `[udp sum ok]` on the kernel's datagram |
| `sudo MACHINE=virt ./ping.sh` (Linux, CI) | the card on a tap interface | Linux's ARP, the system's `ping` and `nc` |

The last row on GitHub's `ubuntu-24.04` runner: `5 packets transmitted, 5 received, 0% packet loss`, the
datagram back unchanged, Linux's own table saying `10.0.0.2 lladdr 52:54:00:12:34:56 REACHABLE`, and the
kernel's count `7 packets answered, 5 dropped`: one ARP answer, five echoes, one datagram, and five IPv6
frames Linux sends on any new interface, which nothing here answers.

That row failed three runs out of four before it passed, and the kernel was not why: the runner's own
network is sometimes `10.0.0.x`, the test gave the tap a `/24`, and the ping left by the other interface
(the tap's counters said seven packets out, none of them ARP). The test now routes the one address.

Limits of this slice:

- **A virtual card.** No real machine here has it; it exists so that Ethernet and ARP can be tested, and
  it is what the kernel would use as a guest of a hypervisor.
- **The card is trusted with memory.** `dma` bounds what the *driver* can write, and the driver only
  writes addresses inside it into the queues. The card itself is hardware: nothing stops a faulty one
  from writing elsewhere (an IOMMU would, and there is none).
- **One frame at a time, copied byte by byte, and sending waits for the card.** Nothing was timed.
- **The address is still fixed, and the kernel still only answers.**

## 7. Next

The order, the boards and what each driver is written from are in [`drivers.md`](drivers.md).

1. The kernel sending first (a datagram, an echo request), then TCP: both testable on `virt`.
2. A link the console does not share pins with (another UART), so the serial line works on a real Pi 4.
3. The Pi 4's Ethernet controller as a third link; only testable on the board.
