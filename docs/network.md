# The network: IPv4 over a serial line first

> **Status: built, five slices.** The kernel answers `ping`, a UDP echo and a TCP echo, gives its
> shell to a TCP connection when the console says so (section 8), and can end a connection and open
> one (section 9), over two links:
> SLIP on the second serial port of a Pi 3 or Pi 4, and Ethernet through a virtio network card on QEMU's
> `virt` machine (section 6). It can ping (section 7). All of it in QEMU. Every number below was produced
> by the command next to it, at the commit that adds its section. Nothing here has run on a real board.

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
| `cancho test tests/inet_test.cho src/inet.cho --std` | 21 tests | two published checksum vectors (RFC 1071 section 3; a worked IPv4 header); requests and replies built by a second implementation in another language (Python's `struct`, its own checksum); RFC 1055's escape bytes |
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

## 7. TCP, and the kernel speaking first

*(Third slice. Sections 5 and 6 say "no TCP" and "the kernel only answers" of the slices they describe.)*

### What is wanted

A connection: bytes that arrive in order or not at all, which is what everything above a ping needs. And
the kernel starting an exchange instead of only answering one, which so far it could not.

### The shape

- **TCP is in `inet`, and `inet` stays pure.** A connection is state, and a pure function cannot keep
  any, so the caller owns it: a slice of ints (16 per connection) and a slice of bytes (one segment per
  connection). The clock is an argument too. So the same file is still tested on the machine that
  builds it, a whole conversation at a time, with the time made up.
- **Passive only, one service.** The kernel listens on port 7 and sends back what it is sent (RFC 862).
  It opens no connection of its own. Four connections at once.
- **One small buffer for each connection, and the window is its room.** What a connection has sent
  and not had acknowledged it keeps, in a buffer of one segment's size (966 bytes), to send again. What
  arrives is echoed from the same buffer, so the window it advertises is the room left: it never takes
  what it could not send back, and never takes back room it has offered. (The first design held one
  segment and advertised zero while it was out. Linux showed why not: see below.)
- **Sent again on a timer.** 1 s, then 2, 4, 8, 16; after that the connection is dropped. No round-trip
  measurement and no congestion window: at most 966 bytes are ever in flight.
- **Only the next byte is taken.** A segment that does not start where the last one ended gets an
  acknowledgement saying what is expected, and its data is dropped: no reassembly queue. What it
  acknowledges still counts.
- **A segment to anything else gets a reset** (RFC 9293 section 3.10.7.1), so the other end hears "no"
  at once instead of waiting.

### Speaking first

`ping <address>` in the shell: the kernel sends an echo request and reports the time to the reply. Over
Ethernet it must first ask who has that address (an ARP request, to every card) and remember the answer:
a table of one neighbour.

### What it will not do

- No connection opened from the kernel, no listening on other ports, no urgent data, no options but the
  maximum segment size, no window scaling, no selective acknowledgement, no timestamps.
- **The first sequence number was a counter's value, not a secret,** when this was written. It is now
  a random word where the board has a generator ([`random.md`](random.md)): QEMU's `virt` and the
  Pi 3, not yet the Pi 4, where it is still the counter and `net` says so.
- **A reset is believed if its sequence number is the next one expected**, and ignored otherwise; the
  challenge acknowledgement of RFC 5961 is not sent.
- **A connection that goes silent stays** until a fifth one is asked for and it has been idle a minute.

### What is built, and how it is checked

`src/inet.cho`: `serve` and `eth_serve` (what `answer` and `eth_answer` do, and TCP), `tcp_tick` and
`eth_tick` (time passing), `echo_request`, `is_echo_reply`, `arp_request`, `arp_answer_from`. It still
holds no capability and its functions still have the empty row. In `src/kernel.cho` the two links are now
one pair of functions (`link_recv`, `link_send`), and `net_ping` is the shell's `ping`. The connections'
state is two slices the shell allocates. No new register is touched: `./authority.sh` says "as recorded".

| | what | against |
|---|---|---|
| `cancho test tests/tcp_test.cho src/inet.cho --std` | 21 tests | segments built by the second implementation (Python's `struct`, its own checksum), a conversation at a time: open, echo, close; data and FIN together; a segment from further on; a segment seen before; a second echo while the first is out, and half of it acknowledged; a full buffer; resets; a fifth connection; the timer, with the time made up, to the second it gives up. Both first sequence numbers are just under 2^32, so every conversation wraps |
| the same, two tests | 58,880 damaged data segments and 12,288 damaged SYNs | none traps: each is answered, taken or dropped |
| `MACHINE=virt TCP=... TCPFILE=big.bin ./test.sh 'net up' 'ping 10.0.0.1' net` | the kernel on `virt`, the connection opened by QEMU's own TCP (libslirp) | a line back unchanged, then 200,000 random bytes back unchanged over one connection; "tcp: 0 open ... 0 sent again" after it; "reply from 10.0.0.1" to the kernel's ping, which had to ask who has that address first |
| `NET=1 ./test.sh 'net up' ... 'ping 10.0.0.1' net` | the kernel as a Pi 3, the serial peer | the kernel's ping answered over SLIP |
| `sudo ./ping.sh`, `sudo MACHINE=virt ./ping.sh` (Linux, CI) | both links against Linux's own TCP | a line back unchanged; random bytes back unchanged over one connection (16,384 over SLIP in 1 to 2 s, 65,536 over Ethernet in under 1 s, on GitHub's `ubuntu-24.04` runner, two runs each); `Connection refused` from port 9; the kernel's ping answered by Linux (2 to 4 ms over SLIP, 0.4 ms over Ethernet); "tcp: 0 open ... 0 sent again" after each |

**What real stacks found that the vectors did not.** Twice all the tests passed and the code was wrong.

1. *QEMU's TCP.* The first connection took a second too long to close. The other end sent its FIN before
   our echo had reached it, then sent the FIN again with the acknowledgement of the echo. A FIN seen
   before was "not the next byte", so the segment was dropped whole, acknowledgement and all, and the
   kernel sent its data again on the timer.
2. *Linux's TCP.* A line came back, and 16 KB stalled after 4,347 bytes. Linux sends segments of half
   the largest window it has seen, so two fitted in the 966 bytes offered. The kernel took the first,
   had its one segment out, and advertised zero: the room it had offered for the second was gone.
   Linux treats a window taken back as a fault and backs off, longer each time. The design was wrong,
   not a line of it, and it was replaced by the buffer described above; partial acknowledgements and
   the acknowledgement of a segment that has overtaken another count now too.

Tests hold both exchanges. They could not have found either: the vectors were written from the same
reading of the specification as the code. That is what the last row of the table is for.

Limits of this slice, besides "What it will not do" above:

- **Small by construction.** At most 966 bytes are unacknowledged at once, so the other end sends a
  little and waits. The times in the table are QEMU on a CI runner, and say nothing of a real line.
- **`ping` goes only to a machine on the same network**: there is no route and no gateway. On the card
  it asks for the address itself and gives up after a second.
- **While `ping` waits, the shell does not read keys** (packets are still answered).
- **The echo service is the only one.** Nothing useful listens yet.
- **Not on a real board,** like everything here.

## 8. The shell over a connection

> **Removed in 0.0.28** ([`update.md`](update.md)). This section is kept as the account of a step: the
> shell's queue and `putc` it describes are what SSH uses now; the port, the command and the session code
> are gone.

*(Fourth slice.)*

### What is wanted

The shell from another machine: `nc 10.0.0.2 23`, type `about`, read the answer. It is the step before
SSH, and the part of SSH that is not cryptography: a service the kernel itself reads and writes, and a
shell that does not assume it is talking to the serial port.

### The shape

- **`inet` gains one port that is the caller's.** Port 7 stays as it is, echoed inside `inet`. For the
  other, what arrives waits in a third slice the caller owns (256 bytes for each connection), and the
  caller takes it with `tcp_read`, answers with `tcp_write`, and `tcp_flush` makes the segment. The
  window of such a connection is the room in those 256 bytes.
- **Which port, and whether any, is an argument** (0: none, and a SYN to it is reset like any other).
  So `inet` does not decide that a shell listens: the kernel does.
- **The other end may finish first and still be answered.** `printf 'about\n' | nc ...` sends its FIN
  with the line. The connection then stays half open until the kernel has written what it had to say,
  and `tcp_close` ends it. The kernel cannot hang up on a connection that has not finished.
- **In the kernel, output has one way out, `putc`.** While a line from the network is being run, what
  `putc` is given goes to a queue in the kernel's state instead of the serial port, and from there to
  the connection as it has room. No command had to change.
- **One session.** A second connection is opened and waits, unread, until the first has gone.
- **Off until asked for.** `net shell on`, typed at the serial console, opens port 23; `net shell off`
  closes it. It cannot be turned on from the network.

### What it is not

- **Not encrypted and not authenticated.** Whoever can reach port 23 has the shell, and everything
  typed is readable on the wire. That is tolerable only because this shell cannot move anything yet
  (the servo commands read), and only on a cable you trust. It is here to be replaced by SSH, and it
  must be gone, or behind SSH, before the kernel can move a servo.
- **Not a terminal.** No echo, no line editing from the kernel's side, no telnet options: the client's
  own line mode does that. A telnet client's option requests are skipped, unanswered.

### What is built, and how it is checked

`src/inet.cho`: `tcp_read`, `tcp_write`, `tcp_flush`, `tcp_close`, and a `port` argument to `serve`. Still no
capability, still the empty row. `src/kernel.cho`: `session` (no hardware either) moves bytes between the
connection, the line being typed and the output queue; `putc` writes to that queue while a line from
the network runs. `net shell on` and `net shell off`. `./authority.sh` says "as recorded": the shell
reached over the network can touch exactly what the shell at the console can.

| | what | against |
|---|---|---|
| `cancho test tests/tcp_test.cho src/inet.cho --std` | 26 tests (21 before) | segments from the second implementation: a line read and an answer written; the port closed unless named; a full inbox, and the window said again after a read; the other end finishing first and still answered; an answer and a FIN in one segment |
| `MACHINE=virt RSH='about\n...' ./test.sh 'net up' 'net shell on' net` | the kernel on `virt`, the connection from QEMU's own TCP | six commands typed from the host, each answered: `about`, `ticks`, `net` ("a session is open"), `net shell on` ("only from the serial console"), `ping 10.0.0.1`, `mem`; "tcp: 0 open" after it |
| the same without `net shell on` | | no answer at all: the port is closed |
| `sudo ./ping.sh`, `sudo MACHINE=virt ./ping.sh` (Linux, CI) | both links, Linux's TCP | `Connection refused` from port 23 before `net shell on`; after it, two commands a second apart answered while the connection is open, then closed from Linux's side |

Limits of this slice, besides "What it is not" above:

- **A command's output is kept whole before it is sent, up to 4,096 bytes;** more is cut, and says so.
- **A second connection waits in silence** until the first has gone.
- **The kernel could not hang up** when this was written; section 9 adds `exit` and five minutes of
  silence.
- **`crash` from the network halts the machine** as it does from the console, and the report goes to
  the serial port.

## 9. Ending a connection, and opening one

*(Fifth slice.)*

### What is wanted

Two things section 8 lists as limits. The kernel could not hang up, so a client that never left held the
shell for ever. And it could not open a connection, so it could ask nothing of another machine.

### The shape

- **`tcp_close` works on an open connection too.** Our FIN goes out after what is still to be sent; the
  connection then waits for the other end's FIN (state 5), acknowledges it, and is gone. What the other
  end still sends meanwhile is acknowledged and thrown away. If its FIN never comes, the connection is
  dropped after a minute of silence.
- **`tcp_dial` opens one**: a SYN to an address and port, from a port the caller chooses. When the
  SYN and ACK come back the connection is open and is the caller's to read and write, like one on its
  own port. A reset means refused; no answer means five more tries and then nothing.
- **In the kernel:** `exit` in the shell over a connection hangs up, and so does five minutes of
  silence there. `http <address> <port>` opens a connection, asks for `/` in HTTP/1.0, and prints what
  comes back: the smallest thing that shows a connection opened from here doing something.

### What it does not do

- **No waiting after the last acknowledgement** (TCP's TIME-WAIT, two minutes in which a late segment
  of the old connection is still recognised). If our acknowledgement of the other end's FIN is lost, its
  FIN comes again and is answered with a reset.
- **No two machines opening to each other at once** (a SYN answered by a SYN).
- **`http` is not a client to rely on:** one request, no headers of its own but the first line, no name
  lookup (an address only), no TLS, and the shell waits while it runs.
- **Only the same network**, as for `ping`: no gateway.

### What is built, and how it is checked

`src/inet.cho`: `tcp_close` on an open connection, `tcp_dial`, `tcp_quiet`, two more states. `src/kernel.cho`:
`exit` and the five minutes, `http`, and `resolve` (the ARP question `ping` asked, now shared).
`./authority.sh`: "as recorded".

| | what | against |
|---|---|---|
| `cancho test tests/tcp_test.cho src/inet.cho --std` | 34 tests (26 before) | segments from the second implementation: finishing first; what was written going out with our FIN; both ends finishing at once; an end that never finishes; a connection opened, asked and answered; refused; an answer to another SYN; no room |
| `MACHINE=virt ./test.sh 'net up' 'http 10.0.0.1 8099'` with Python's `http.server` on the host | the kernel's connection through QEMU's TCP | the server's headers and its page printed, "[219 bytes]"; a port with no server: "refused, or no answer" |
| the same typed over the shell's connection, then `exit`, then `about` | | the page, "bye", and no answer to `about`: the kernel had hung up |
| `exit` with the client's input held open 8 s (by hand) | | the console's `net` says "nobody connected" and "0 open" while the client is still there |
| `sudo ./ping.sh`, `sudo MACHINE=virt ./ping.sh` (Linux, CI) | both links, Linux's TCP and Python's `http.server` on Linux | the page fetched; a port with no server refused; after `exit`, "nobody connected" while Linux's end is still open |

**A third thing a real stack found.** The first version passed its tests and QEMU's TCP, and against
Linux the connection the kernel hung up on never ended. While waiting for the other end's FIN the
kernel advertised a window of zero (it takes nothing more), and Linux does not send a FIN into a window
of zero: it probes, for ever. The window in that state is now what the kernel is in fact willing to
receive and throw away, and the Linux check ends by insisting that no connection is left open.

## 10. Addresses, a gateway and names

Sixth slice, in its own file: [`addresses.md`](addresses.md). The kernel's address is no longer a constant;
`net dhcp` asks for one; machines outside its network are reached through a gateway; `lookup`, `ping`
and `http` take names. The kernel's network code moved from `src/kernel.cho` to `src/network.cho` with it
(the file had reached its 2,000 lines), so where sections 6 to 9 say `src/kernel.cho`, read that.

## 11. A real card

Seventh slice, in its own file: [`genet.md`](genet.md). The Pi 4's Ethernet controller, on a real board
and a real network. Everything above the driver is the code the earlier sections describe.

## 12. SSH

Eighth slice, in its own file: [`ssh.md`](ssh.md). The shell behind SSH on port 22, with cancho-ssh.

## 13. Next

The order, the boards and what each driver is written from are in [`drivers.md`](drivers.md).

1. What a real network also asks: the lease renewed, answers remembered, more than one gateway.
1. SSH, as its own package (the cryptography is in cancho's standard library; the kernel needs a source
   of randomness first), to replace the open port 23. Then connections opened from the kernel.
2. A link the console does not share pins with (another UART), so the serial line works on a real Pi 4.
3. The Pi 4's Ethernet controller as a third link; only testable on the board.
