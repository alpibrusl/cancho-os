# The Pi 4's Ethernet

> **Status: works on a real Raspberry Pi 4** (one board, one session, 2026-11-26). It cannot be tested
> in QEMU, whose Pi 4 has no such card: there `net eth` is a fault, and CI never types it.

## What it is

BCM2711's Ethernet controller, "GENET" version 5, at `0xfd580000`, with a Broadcom BCM54213PE
transceiver beside it, reached through the controller's MDIO register. The driver is `genet_*` in
`src/network.cho`, about 230 lines, written from NetBSD's `bcmgenet.c` and FreeBSD's `if_genet.c`
(both BSD-2-Clause), which are the references `drivers.md` chose. Nothing was copied; the register
offsets and the order of initialisation are theirs.

## The shape

- **`net eth` brings it up**: reset, two rings of sixteen 2 KB buffers, the transceiver told how it is
  wired (RGMII, with the receive clock delayed in the transceiver), negotiation restarted, then up to
  five seconds for the cable. The MAC is set to the speed the two ends agreed.
- **Polled, like everything here.** Its interrupts are all masked.
- **No new capability for the card.** The card's registers were added to the bound of `vio`, which was "the virtio
  slots" and is now "the network card's registers, whichever the board has". Its buffers are in `dma`,
  the 64 KB the virtio card already used.
- **`dma` is now mapped as device memory**, on every board. A card writes that memory behind the
  processor's back, so the kernel must not read it through a cache; and the cache-maintenance
  instructions a driver would otherwise use are not ones the `Cpu` capability offers. Uncached memory
  needs neither. It costs speed on every packet byte, which has not been measured.
- **Every frame is taken** (promiscuous), and `inet` drops what is not for this card. A filter in the
  card is not set up.
- **Above the driver nothing changed.** `inet`, DHCP, DNS, TCP and the shell are the code QEMU's virtio
  card has been running.

## What was measured

On the board, with the Pi 4 cabled to a home router and its console on a second Pi's UART. Each build
was sent with `load` (docs/load.md): five builds, about 12 s each.

| | result |
|---|---|
| `net eth` | "GENET, transceiver 600d84a2" (a BCM54213PE), "cable in, 1000 Mb/s" |
| before any address was set | the counters in `net` rose: about a hundred frames of the house's own traffic taken and dropped as not ours |
| `net address 192.168.1.222`, then `ping` of two machines on the network | "reply from 192.168.1.5 in 2778 us", "reply from 192.168.1.184 in 1374 us" |
| from one of them, `ping -c 3 192.168.1.222` | 3 of 3, 3 to 7 ms; its ARP table and the other machine's both list the card's address |
| `net dhcp` | "address 192.168.1.69, mask 255.255.255.0, gateway 192.168.1.254, names from 192.168.1.254", lent for 43,200 s |
| `lookup example.com`, `http example.com 80`, `ping 1.1.1.1` | an address; "HTTP/1.1 200 OK" and the page; "reply from 1.1.1.1 in 2086 us" |
| from a Mac on the network: `nc 192.168.1.69 7` | a line back unchanged; then 200,000 random bytes back unchanged in 1 s |
| the same Mac, `nc 192.168.1.69 23` after `net shell on` | the kernel's shell: `about`, `uptime`, `mem`, `exit` |

## What it took, besides the driver

- **The card had no address.** The firmware on this card (April 2021) leaves the controller's address
  registers at zero, and the first version made one up (`02:63:61:6e:63:04`), so two such boards on
  one network would have collided. The driver now asks the firmware (`fw_ask`, below) and the card
  has the board's own: on the board tried, one in Raspberry Pi's range (`dc:a6:32:...`), under which
  the router then lent it another address. The made-up one is kept for a firmware that does not answer.
- **DHCP waited too little.** The router offered an address at once and took more than two seconds to
  acknowledge the request for it; the kernel now waits five. The message that found it ("192.168.1.69
  was offered ..., but asking for it got no answer") stays.
- **A received frame's length.** The first guess took six bytes off what the card reports (two in
  front, four of the check behind); the driver now takes off the two and leaves any check as padding,
  which `inet` ignores.

## The firmware, asked three things

A Pi's firmware answers questions about the board through a "mailbox": the address of a message is
written to one register and read from another when it has been answered in place. `fw_ask` does that,
with the message in `dma`, and a new capability, `fw`, bounds the three registers it uses
(`0x3f00b880..0x3f00b8a4` on a Pi 3, `0xfe00b880..0xfe00b8a4` on a Pi 4). The interface can also *set*
things (clocks, power, the display); the kernel sends three tags, all questions: the board's revision,
its serial number, its card's address. `board` prints them. QEMU's Pi 3 and Pi 4 answer too, so this
part is tested in CI: "revision 00a02082 ... card address 52:54:00:12:34:57" as a Pi 3.

On the real board `board` said revision `00c03111` (a Pi 4 Model B, 4 GB), a serial number, and the
address the card then used.

## What it does not do

- **No link changes after `net eth`.** A cable pulled, or a speed renegotiated, is not noticed.
- **No multicast filter, no pause frames, no checksum offload, one queue.**
- **Nothing was timed** beyond what the table says, and nothing ran for long.
- **`net shell on` on a real network is an open door** to whoever is on it: no password, no encryption
  (docs/network.md, section 8). It was opened for one test and closed again.
