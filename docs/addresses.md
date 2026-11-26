# An address that is given, a way out, and names

> **Status: built, in QEMU.** On the virtio card only: the serial line has nobody to ask.

## What is wanted

Three things a machine needs before it can be put on a network that was not set up for it. Until now
the kernel's address was `10.0.0.2`, written in the source; it could reach only machines on its own
network; and it knew other machines by number only.

## The shape

- **The address is state, not a constant.** Four numbers in the kernel's state: its address, the mask
  of its network, the gateway, the name server. They start as before (`10.0.0.2`, `/24`, gateway
  `10.0.0.1`, no name server), so everything that worked still does.
- **A gateway.** A packet for a machine outside the kernel's network goes to the gateway's card, not
  the machine's own: `inet.next_hop` says which, and the ARP question is asked about that. On the
  serial line there is no such choice: everything goes down the line.
- **DHCP (RFC 2131), on the card only.** `net dhcp` asks: DISCOVER, the server's OFFER, REQUEST, its
  ACK. `inet` builds the two frames and reads the two answers; the kernel waits five seconds for each
  and tries twice (two seconds at first: a real router took longer to acknowledge, docs/genet.md). The answer's address, mask, gateway and name server become the kernel's.
- **DNS (RFC 1035).** `lookup <name>` asks the name server for the name's IPv4 address, over UDP, and
  `ping` and `http` take a name where they took an address. `inet` builds the question and reads the
  answer: the first address in it, whatever aliases come before.
- **`inet` stays pure.** All of this is frames in and frames out; the waiting is the kernel's.

## What was measured

At the commit that adds this file. `inet` still holds no capability; `./authority.sh` says "as recorded".

| | what | result |
|---|---|---|
| `cancho test tests/addr_test.cho src/inet.cho --std` | 10 tests, against messages a second implementation built (Python's `struct`) | the two DHCP frames byte for byte; an OFFER, an ACK and a refusal read; the DNS question byte for byte; an address read behind an alias and an IPv6 record; 87,552 damaged OFFERs and over 400,000 damaged DNS answers, none traps |
| `MACHINE=virt ./test.sh 'net up' 'net dhcp' net` | QEMU's own DHCP server (libslirp) | "address 10.0.0.15, mask 255.255.255.0, gateway 10.0.0.1, names from 10.0.0.3", lent for 86,400 s |
| `... 'lookup example.com'` | QEMU's name server, which asks the host's | "example.com is 104.20.23.154" on this machine, 2026-11-26; "no such name" for a name under `.invalid` |
| `... 'http example.com 80'` | the real internet: the name looked up, the connection through the gateway | "HTTP/1.1 200 OK" and example.com's page, 888 bytes printed in the five seconds |
| `sudo MACHINE=virt ./ping.sh` (Linux, CI) | dnsmasq as DHCP and name server on a second network of the tap interface | dnsmasq's own log: DISCOVER, OFFER 172.31.77.58, REQUEST, ACK; then the kernel says "address 172.31.77.58, mask 255.255.255.0, gateway 172.31.77.1", "www.cancho-os.test is 172.31.77.1", "no such name: nothing.cancho-os.test", fetches the page by name, and pings 10.0.0.1, now outside its network, through the gateway |

In that run dnsmasq logged two DISCOVERs: it tests an address before offering it, which took longer
than the two seconds the kernel waits, and the second try was answered at once.

The first try at example.com got "403 Forbidden": the request named no host, and the server answers for
many. The request now carries a `Host` line with the name as it was typed.

## What it does not do

- **A lease is not renewed.** The kernel says how long the address is its, and keeps it after.
- **No answer is remembered:** every `lookup` asks again. No IPv6 addresses, no answers over TCP (a
  truncated one is "no address").
- **Whoever answers first is believed.** DHCP and DNS have no authentication, and nothing here adds
  any: a machine on the same cable can hand the kernel a false address or a false name.
- **One gateway, no other routes.**
