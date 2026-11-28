# A program connects out

> **Status: built**, in QEMU (0.0.53, cancho-os#51, part of the epic #60). Written before the code, after reading
> `src/network.cho`, `src/inet.cho`, `src/ksys.cho` and `src/keys.cho` in cancho-os 0.0.52, and `compiler/syscode.cho`,
> `compiler/runtime/net.c` and `docs/native-sockets.md` in the compiler at `133973f6`. What building it changed is
> marked "(built)". What it measured is at the end.

## What is missing

Only the kernel can reach another machine. `ping`, `lookup`, `http` and `net time` are its own commands; a program
run through the system block (`docs/bare-system.md` in the compiler) has a console, files, the clock and random
bytes, and no network. So a fetch tool, an agent that calls a model on another machine, and `ping` or `http` as
programs instead of kernel code cannot be written.

## What a program writes

Nothing new. A cancho program connects as it does on Linux, with the builtins of the compiler's
`docs/native-sockets.md`:

```
match tcp_connect(up, "10.42.0.1", 8000) {
    Dialed::Ok(conn) => { conn_write(&!conn, request); ... conn_read(&!conn, into); ... conn_close(conn); }
    Dialed::Failed(why) => ...
}
```

The same source builds for Linux and for the board. On the board the lent system answers the four builtins
`tcp_connect`, `conn_read`, `conn_write` and `conn_close`, over the kernel's own TCP (`src/inet.cho`), as it
already answers `open`, `read` and `close` over its own FAT.

## Two checks, and who makes each

- **The language's.** An `Out` narrowed to `"10.42.0.1:8000"` cannot dial anything else: the compiler checks the
  host and the port against the bound before the system is asked, and traps on a mismatch, as Linux's runtime
  does (`netrt_checked_host`, exact matching from edition 10, `*.` for one label). That is the program's own promise,
  and its row says it: `net_out("10.42.0.1:8000")`.
- **The system's.** Whether *this key* may reach that host is the kernel's to say: a grant on the key's line of
  `KEYS.TXT`, checked in `may`, the one place grants are checked. A program is lent the board's whole `Net`; what
  it reaches is what both checks allow. (built: the kernel's edition splits the network into `Out` and `Ports`, so
  a program is lent the board's whole `Out("")`, and `fetch`'s row says `net_out("")`.)

## Grants

An agent's line gains a third right:

```
agent ssh-ed25519 AAAA... read:DOCS write:WORK/OUT net:10.42.0.1:8000 the builder
```

- `net:<host>:<port>`: the host as the program names it, matched exactly, and the port. `net:*.example.org:443`
  covers one label in front of `example.org`, as the language's bound does. A name is matched as it was asked,
  before it is looked up; a grant by address covers that address, not every name that resolves to it.
- It takes one of the four grant places a key has, with the same 62 bytes of room (`keys.grant_room`), and ends
  with the key's `until:` like the others.
- **No grant, no network.** An agent with no `net:` grant reaches nothing. A reader's key reaches nothing: a reader
  watches. An owner's key and the console reach any host, as they may do everything else.
- A refusal is made before a packet leaves. The program gets `Dialed::Failed(13)` (`EACCES`, what Linux answers a
  connection a rule forbids), and its error output gets one line it can read:
  `refused: net.not-granted 10.42.0.9:80`. The record gets a line too.

## Names

`tcp_connect` takes a name. A dotted address is used as it is; anything else is asked of the name server the DHCP
lease gave, with the resolver the kernel already has for `lookup` (`docs/network.md`); what the resolver would say on
the console is kept quiet. A name with no answer, and an address nobody on the way to it answers for, is
`Failed(113)` (`EHOSTUNREACH`). (built: on Linux a name with no answer is `Failed(-1)`, `getaddrinfo`'s failure; a lent
system answers minus why, which cannot say -1, so the board says the nearest reason Linux has.)

## Waiting

The kernel has one thread of work, and while a program runs, the program is it. So a connection waits by turning
the network itself: `ksys` calls the same `net_pump` the shell's loop calls, which also keeps the SSH session the
program may have been started from answered.

- `tcp_connect` waits for the handshake for at most 5 seconds: then `Failed(110)` (`ETIMEDOUT`). A refused port is
  `Failed(111)` (`ECONNREFUSED`).
- `conn_read` waits until bytes come, or the other side closes (`End`), or 10 seconds pass with neither
  (`Failed(110)`). A connection is never non-blocking: `conn_nonblocking` is not answered, so `Again` is never the
  answer.
- `conn_write` takes all of it, waiting for room as long as some is made within 10 seconds, and says how much
  (`Wrote(n)`): what a blocking socket on Linux does. (built: the design said it would take what had room; taking all
  is what a program written for Linux expects of a blocking connection.)
- The watchdog's patience (15 seconds, `base.patience`) is longer than any one wait, so a program that waits on a
  slow machine is not stopped; one that loops forever is, as before.

## What is recorded

One line in `LOG.TXT` for every connection the program asked for, written when the program ends (built: the line has
the fields every line has, so `tests/checklog.py` reads it unchanged):

```
n ticks key:<16 hex> agent net 10.42.0.1:8000 - 62 3167 - <chain>
```

`who`, `role` and the line's chain are what every line has (`docs/permissions.md`); `action` is `net`, the target is
the host and port as asked, and where a change has its version and its size are the bytes sent and received. A
refused connection's action is `net-refused`, one that could not be made `net-failed`, with `-` for both counts. So
"what did the agent send, and to whom" has an answer on the board itself.

## Limits, on purpose

- **Four connections** a program at a time. The kernel's TCP had four places (`inet.tcp_count` of the tables
  `shell` makes), shared with SSH, which uses one for each session; it grows to eight, so a program's four never
  take the place of a session. The fifth `tcp_connect` is `Failed(24)` (`EMFILE`).
- **Connections end with the program.** One the program did not close is closed by the kernel when the block ends,
  and recorded like the others.
- **Out only.** A program cannot listen (`tcp_listen` stays refused on the bare target): that is #54.
- **No TLS**: a program that wants it has to bring it, and the board has no certificates yet (#56).
- **No UDP**: `udp_*` stay refused.
- **Over SSH, a program's output is cut at 4,096 bytes** (the queue `putc` fills for the session is emptied only when
  the program has ended): that is cancho-os#58, not this. A page fetched at the console comes whole.
- **A connection's inbox is 256 bytes** (`inet.tcp_inbox`), so the window it offers is that: a page comes a quarter of
  a kilobyte a round trip. On the board's own network that is fast enough to measure as nothing; across the world it
  would not be.

## What the compiler is asked for

In `compiler/syscode.cho`, three operations of a lent system, written like the file ones (built: `connect` is a
builtin's name, so the module's function is `dial`):

| builtin | the module's function | it answers |
|---|---|---|
| `tcp_connect` | `dial(host, port)` | a handle, or minus why |
| `conn_read` | `receive(handle, bytes)` | how many came, 0 at the end, or minus why |
| `conn_write` | `send(handle, bytes)` | how many were taken, or minus why |
| `conn_close` | `close(handle)` (the files' own) | 0 |

The host is checked against the capability's bound *before* `connect` is asked, in the same code on every target,
so the check is the language's and not the kernel's. The labels the block then discharges are `net_out(..)`,
`conn_read` and `conn_write`. The block lends more values than it can now (twelve): the network's state is eight
more, so the room grows to twenty. (built: cancho#874, the compiler's docs/bare-system.md §11c; the kernel lends seventeen, and the slots that hold them grew
from sixteen to thirty-two, since a slice takes two.)

## Shown when (written before the code)

- **A program fetches a page** from a machine on the network, and its bytes are what Python's `urllib` gets from the
  same server (CI: QEMU's virt machine, a Python HTTP server on the host side, the same page asked both ways and
  compared by hash).
- **A host that is not granted is refused before a packet leaves**: QEMU's `filter-dump` writes every frame the
  board sends to a file, and `tcp_connect` to a host the agent's key has no grant for adds no SYN to it; the same
  run with the grant does.
- **The record's lines** for both, checked by `tests/checklog.py`.
- **On the real Pi 4**, the same program fetches a page from the Pi 5.

## Measured (0.0.53, QEMU's virt machine)

`./netout.sh <image> <owner key> <agent key> 8765 <reader key>`, which CI runs on a volume Linux's `mkfs.fat` made and
then judges with `fsck.fat` and `tests/checklog.py`:

- The agent's key, granted `net:10.0.0.1:8765`, fetches a page of 2,979 bytes from Python's HTTP server there, and the
  body is the file byte for byte. The owner's key fetches it from port 8767, which the agent is not granted: the same.
  At the console `fetch` takes the whole page of 22,266 bytes, and it is the file.
- The agent's `fetch` of port 8766, where a server is listening too, says `refused: net.not-granted 10.0.0.1:8766` and
  ends with status 1. QEMU's `filter-dump` wrote every frame the board sent: connections asked of ports 8765, 8766 and
  8767 were 1, 0 and 2. A reader's key is refused the granted port the same way.
- `LOG.TXT` has a line for each: `agent net 10.0.0.1:8765 - 62 3167`, `agent net-refused 10.0.0.1:8766`, `owner net`,
  `reader net-refused`, `console net 10.0.0.1:8767 - 61 22455`; its chain holds.
- A kernel built with `may_connect` saying yes to every port fails the same test: the capture shows a connection
  asked of 8766. So the test can tell.
- `tests/keys_test.cho` holds `net:` grants to what they name (port, host, one label for `*.`, letters in any case),
  to granting nothing on the disk, and to ten words that look like a grant and are not; three mutations of
  `keys.cho` (a `net:` grant read as a path, `*.` taking any number of labels, the port not compared) each fail it.
- `keys.sh`, `agents.sh` and `authority.sh` pass as before.

Not measured: the real Pi 4 (GENET), names looked up through a real name server, and a server that is slow or that
breaks the connection off.
