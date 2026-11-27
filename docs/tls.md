# TLS with no system under it

> **Status: a spike. Numbers and a design, no kernel code** (task #56 of the epic, #60). cancho's TLS client was
> built for the bare target and run against OpenSSL's server on a Mac. Nothing here has made a handshake inside
> the kernel, in QEMU or on a board. Every figure in "Measured" says how it was got; what is an estimate is in
> "Estimated" and nowhere else. The compiler was cancho at `f1fa983b`, the kernel 0.0.48 (`83bc06e`).

## What was asked

cancho has TLS: `packages/tls` and `packages/x509` of the compiler's repository, over `std`'s X25519, P-256,
RSA, SHA-2, ChaCha20 and AES. It runs on Linux and macOS. Nobody knew what it costs where there is no system:
what it asks a system for, how large it is, how much memory and time a handshake takes, and what it does about
certificates on a board whose date is believed and not proved ([`clock.md`](clock.md)).

## What was found, in short

1. **The engine asks a system for nothing.** A connection is two slices the caller owns. Bytes from the network
   are given to it (`feed`) and bytes for the network taken from it (`take`). The random bytes, the date and the
   roots are arguments. Of the 1,039 functions of `packages/tls` and `packages/x509`, 1,029 have an empty row
   and ten have `heap`: the ones that open and close an engine of many connections. It is the shape `inet`,
   `fat` and cancho-ssh already have here.
2. **It does not build for the bare target today, for one reason.** `std.crypto` and `std.gcm` ask the processor
   whether it has SHA and AES instructions (`hw_sha256()`, `hw_aes_gcm()`), and those two builtins and the seven
   behind them are refused on the bare target. 21 places in three files. cancho-ssh met the same refusal and
   carries its own copy of SHA-256 for it. With those 21 places answered "no", the whole client builds, and the
   object asks for nothing but the two ends of the heap.
3. **It is not small and not slow.** About 312 KB of code and 111 KB of constants as an object of its own;
   338 KB more in the kernel's image, which already has half of the arithmetic for SSH. About 1.3 MB of memory
   for one connection. A connection is 5.3 to 5.7 million instructions: a few milliseconds of a Pi 4.
4. **The certificate checks are there and OpenSSL's server shows them**: a certificate that has ended, one for
   another name and one signed by nobody known are each refused, with a word for why. With no roots, nothing
   is trusted. With no date, every certificate is "not yet valid": refused, but by arithmetic and not by a rule.
5. **Two things nobody has listed** stand between this and a handshake on the board: the builtins of point 2
   (the compiler's), and a source of random bytes, which the language does not have as a builtin at all.

## What the client reaches

The probe is `tests/tls/bare.cho`: a store of roots loaded, a handshake started, bytes fed, a request sent, an
answer received, the end. Every call one connection makes, with nobody at the other end.

Built for the Mac to LLVM text and followed from `main` (`tests/tls/reach.py`, the method of cancho
`docs/bare-system.md` section 2), this is all of the runtime it reaches:

| what | the runtime's functions | on the bare target |
|---|---|---|
| regions and the heap | `cancho_region_take`, `_give`, `_init`, `_drop`, `cancho_arena_alloc`, `malloc`, `calloc`, `free`, `memmove` | there (cancho `docs/freestanding.md` section 8) |
| the trap | `cancho_trap` | there |
| does the processor have SHA-256 instructions | `cancho_hw_sha256` (asks macOS, `sysctlbyname`) | **refused** |
| SHA-256 by those instructions | `cancho_sha256_blocks`, `cancho_sha256_block_words` | **refused** |
| does it have AES and carry-less multiply | `cancho_hw_aes_gcm` | **refused** |
| AES-GCM by those instructions | `cancho_aes_ctr32`, `cancho_ghash_powers`, `cancho_gcm_tag`, `cancho_gcm_tag_diff` and what they call | **refused** |

No file, no clock, no socket, no argument, no stream. The compiler stops at the first refusal
(`std/crypto.cho:268`, `if hw_sha256() {`), so the list of all of them was made by reading: every call of the
nine builtins outside a comment.

| file | lines | what is there |
|---|---|---|
| `std/crypto.cho` | 268, 269, 284, 285 | SHA-256: the question, and the two builtins that hash by instruction |
| `std/gcm.cho` | 335, 434, 445, 494, 504, 577, 586 | AES-GCM: the question, seven times |
| `std/gcm.cho` | 340, 665, 666, 679, 683, 708, 709, 736, 740 | `ghash_powers`, `aes_ctr32`, `gcm_tag`, `gcm_tag_diff` |
| `packages/tls/server.cho` | 605 | the server choosing a suite (reached only through the engine of many connections) |

A call is refused if the function it is in is reached, whether or not the branch can be taken. So answering
"no" to the two questions is not enough by itself: the calls behind them must go too, or compile to something.

**Checked by doing it.** `tests/tls/soften.py` makes a copy of the library in which the two questions are
`false` and the seven other calls are taken out. It is the software path the library already has, alone. Built
from that copy with the compiler unchanged, the probe is an object for `aarch64-none-elf` whose only undefined
names are `__cancho_heap_start` and `__cancho_heap_end`. Linked into a copy of the kernel and called from its
`heap` command, it ran in QEMU as `virt`: the roots loaded, a key pair made, a ClientHello queued and fed back,
and the shell answered afterwards. That is the code running, not a handshake.

**What the compiler would have to change** (not done here; it is cancho's): on the bare target the two
questions are not a call into a system. Either they answer `false` there and the seven compile to a trap that
is never reached; or the instructions' support is written for the target and the question is answered by the
processor's own register (`id_aa64isar0_el1`, which the kernel may read: it is on `Cpu`'s list). The first is
a few lines and is all a Pi 4 can use. The second is what a Pi 5 would want. Either way `std.crypto.sha256`
builds, and cancho-ssh's copy of SHA-256 can go.

## What a lent system would have to answer

The host program, `tests/tls/client.cho`, is what a program on the board would be: it opens a connection, reads
the roots from a file, asks the date, draws random bytes, and carries bytes between the connection and the
engine. `cancho authority` gives its whole row: `args`, `clock`, `conn_read`, `conn_write`, `err_write`,
`fs_read("")`, `heap`, `io_write`, `net_out("")`. TLS adds no label to it: a program that speaks TLS to a host
has the row of a program that speaks to that host.

| what the program asks | the builtins | who plans it |
|---|---|---|
| a connection: open, read, write, close | `tcp_connect`, `conn_read`, `conn_write`, `conn_close` | #51, and these four are all the probe uses. A read that waits, a write that may take fewer bytes than it was given, and the end of the connection told apart from a failure. |
| the date | `clock_unix_ms` | #50. **Not said there:** what it answers when the board has not been told the date. It answers a whole number and nothing else. |
| how long something took | `clock_ms` | #50 |
| random bytes | **none** | #50 names "the source of random bytes", but the language has no such builtin and no effect for it. On a system a program reads `/dev/urandom` through its `Fs`, and so does the probe. **Nobody has listed this.** |
| the roots | `open_read`, `file_read`, `file_close` | lent today. (`fs_read`, which reads a whole file by its path and is what the probe uses, is not among what a lent system answers: a program for the board opens and reads.) |
| arguments, the two streams | `arg`, `write_bytes`, `write_err`, `flush_out` | lent today |
| memory | `box_slice`, regions | there. How much a program may have is #57. |
| more kinds of thing lent than three, and the row discharged at the block | | #49 |
| the hardware builtins on the bare target | the nine above | **nobody**: not #49, #50 or #51. It is the compiler's. |
| a name looked up | | #51 mentions it. The probe is given an address; the name is only what the certificate must say. |

Two more facts for those tasks:

- **Random bytes, how many.** One handshake takes 96 from its caller: 32 are the key of the exchange, 64 are
  public and must not be guessable. The kernel's pool holds 16 words, 64 bytes ([`random.md`](random.md)).
  So either the program is lent bytes as often as it asks and the pool refills between, or it is lent 32 once
  and stretches them itself, which `tls.seed` of the engine of many connections already does (ChaCha20, the key
  replaced after each block).
- **The loop of cancho's HTTP client** (`packages/http-client`, `examples/http_fetch_nb`) is written over the
  poller and connections that do not wait (read in its source, not built here). A fetch tool made from it asks
  for more than the four of #51. The probe's loop, which waits in `conn_read`, is about a hundred lines.

## Where TLS should run

In the program, not in the kernel.

- The engine holds no authority, so there is nothing of the kernel's to protect by keeping it there. A program
  lent a connection to one host can already send that host anything; that it encrypts first changes nothing the
  kernel decides.
- The kernel then never reads a certificate. Parsing what a stranger sends is the part most likely to be wrong,
  and a trap in the kernel is the board starting again.
- The grant stays what #51 says: `net:host:port`, checked before a packet leaves. What TLS adds is **which
  roots speak for that host**, and that is a file the grant names: `read:` on one directory of the card, with
  the roots in it. There is no store every program trusts. A program not granted the file trusts nobody, and
  the engine then refuses every server (`x509-unknown-issuer`, measured).
- What it costs: the record's line for a connection can say who, where to and how many bytes. It cannot say
  "and the certificate was checked", because the kernel did not check it. The program says so in its own answer.
  If that must be the kernel's word one day, the engine can be called from `ksys` instead: it is the same
  module either way.

## Certificates and the date

What the client checks, read in cancho `docs/x509-verify.md` and seen against OpenSSL's server (below): a path
from the server's certificate to a root of the store, every signature on it, that the name asked for is one the
certificate carries, and for every certificate of the path, the root too, that `notBefore <= now <= notAfter`
in whole seconds. `now` is an argument. It does not check whether a certificate was revoked, and says so.

What follows from a date that is believed ([`clock.md`](clock.md)): whoever can answer for the time server's
address can tell the board any date after 2023 that is not before the record's last line.

- A date told **too late** ends every certificate. Nothing is connected to. That is a refusal, not a breach.
- A date told **too early** makes a certificate that has ended good again. To use that, someone must also hold
  the key of such a certificate for the name, and stand between the board and the server. It is the same place
  on the network that answering for the time server needs. So on a board told the date by its neighbour, an
  ended certificate is only as dead as that neighbour is honest.
- The date not going back before the record's last line (0.0.47) is the one bound that does not depend on the
  neighbour. A fresh card has none.

So, proposed:

1. **With the date not known, nothing whose trust rests on dates is connected to**, and the program is told so
   by a rule (`tls.no-date`) before a packet leaves, as a grant with `until:` grants nothing then. Today's engine
   already refuses, but for the wrong reason: given 1 January 1970 it says `x509-not-yet-valid` (measured), and
   it says that after the connection is open and the server has answered.
2. **A connection made with a believed date claims that and no more.** The program's answer, and the record's
   line if the kernel is told, say "the chain held at the date the board believes", with where the date came
   from. Never "verified" alone.
3. **For a machine the owner knows, name its key and not its date.** A certificate named in the grant by its
   hash needs no date and no root, as an SSH key in `KEYS.TXT` needs none. This is what a board talking to a
   model on the next machine wants. cancho's client had exactly this before it had chains (cancho
   `docs/tls-core.md` section 5) and does not have it now: it is a change there, and until it exists such a
   server is reached with a root of the owner's own and rule 1.
4. **`clock_unix_ms`, lent with no date, answers 0**, and a program reads 0 as "not told". There is no pretend
   date (#50), and a whole number has no other way to say it.

## What it is not

- **Not a handshake on the board, or in QEMU.** The client ran on a Mac. In QEMU the bare build was called
  once with nobody at the other end.
- **Not a change to the compiler.** The bare build was got by changing a copy of the library, to find out
  whether anything else was in the way. Nothing else was.
- **Not reviewed.** cancho's TLS says of itself that it has had no independent review (cancho
  `docs/tls-pure.md`). Building it for another target does not change that.
- **Not a server.** A program that listens is #54. The engine of many connections (`tls.open`) holds the server
  too and is 88 KB larger; a client wants `tls_client` alone.
- **Not revocation**, and not a list of the world's roots on the card.
- **Not constant time by measurement.** The software AES is the bitsliced one and the library says which of its
  code is meant to be constant-time; nothing here tried it on an A72.

## Measured

On a Mac (Apple M4 Max, macOS 26.2), 2026-11-27. The other end is `openssl s_server` of OpenSSL 4.1.0 on the
same machine. `tests/tls/measure.sh` does all of it again but the rows marked (a), which need a tool that is
not kept here.

| what | result | how |
|---|---|---|
| the library as it is, for the bare target | refused at `std/crypto.cho:268` | `cancho build tests/tls/bare.cho ... --std --target aarch64-none-elf --emit obj` |
| the same with the 21 places answered "no" | builds; undefined: `__cancho_heap_start`, `__cancho_heap_end` | `soften.py`, the same command, `llvm-nm -u` |
| code the client adds, as an object | 311,924 bytes of code and 111,312 of constants (317,524 and 111,664 against 5,600 and 352 for `none.cho`) | `llvm-size -A` of the two objects, the `.text` and `.rodata` sections added up |
| the same for the engine of many connections, server included | 399,824 and 111,888 | the same, a probe over `tls.open` |
| what the kernel's image gains | 337,920 bytes: `kernel8.img` 779,600 without, 1,117,520 with | (a) a copy of this repository with the probe as a module called from `heap`, `./build.sh` |
| that kernel in QEMU as `virt` | boots; `heap` runs the probe and answers as before | (a) `MACHINE=virt ./test.sh about heap mem` |
| a handshake, `GET /hello.txt`, 72 bytes back | done; TLS 1.3, X25519, ECDSA P-256, AES-256-GCM (OpenSSL's choice) | `client 127.0.0.1 44331 board.test ca.pem 0 1 /hello.txt` |
| the same with the server offering ChaCha20-Poly1305 only, and with TLS 1.2 only | done | ports 44336 (`-ciphersuites TLS_CHACHA20_POLY1305_SHA256`) and 44337 (`-tls1_2`) |
| a file of 1 MiB | the same 1,048,621 bytes `curl` gets | `cmp` with `curl -i --http1.0` |
| a certificate that ended in 2021 | `refused x509-expired` | port 44332 |
| one for `elsewhere.test`, asked as `board.test` | `refused x509-name-mismatch` | port 44333 |
| one signed by a root the client was not given | `refused x509-unknown-issuer` | port 44334 |
| a good one, the file of roots empty | `refused x509-unknown-issuer` | `/dev/null` as the roots |
| a good one, the date given as 1 (1970), and as a day in 2020 | `refused x509-not-yet-valid` both | the fifth argument |
| instructions for one connection, software only | 5.70 million with AES-256-GCM, 5.34 million with ChaCha20-Poly1305 | macOS's `/usr/bin/time -l`, "instructions retired", 50 connections less a run of none, divided by 50 |
| the same with the processor's instructions | 5.23 million | the same, the library as it is |
| instructions to receive 1 MiB, software only | 342.5 million with AES-256-GCM, 105.3 million with ChaCha20-Poly1305 | 50 fetches of the file less 50 of the small one, divided by 50 |
| time for one connection, both ends on the Mac | 0.5 ms (500 in 0.25 to 0.26 s, software or not); the handshakes alone add up to 0.35 to 0.40 ms each | `time`; the probe's own clock, in whole milliseconds, summed |
| OpenSSL's client against the same server | 0.49 ms a connection (8,198 in 4 s) | `openssl s_time -new -time 3` |
| memory asked for at once, one connection | 1,760,990 bytes, the same after 1 MiB received and after 20 connections | (a) a counting `malloc` inserted into the program on the Mac |
| of which the connection's two slices | 81,960 and 187,703 bytes | the same; they are `tls_client.ints_len()` words and `bytes_len()` bytes |
| of which regions | 14 chunks of 64 KiB at the most at once, 917,504 bytes | the same: a chunk is asked for only when none is free, so the count is the most open at once |
| of which the probe's own rooms | 565,504 bytes: two of 256 KiB for the roots' file and store, 41,216 for bytes in and out | its source |
| the Mac's own file of roots, for scale | 128 certificates, 333,483 bytes of text | `/etc/ssl/cert.pem`; cancho's docs give 138,350 bytes for such a store once loaded |

## Estimated

None of this was measured. Each line says what it rests on.

- **Memory on the bare target, one connection: about 1.3 MB**, and the roots. The bare heap hands out blocks of
  32 bytes times a power of two with 16 bytes of header, so the two slices become 131,072 and 262,144; the 14
  region chunks are taken as they are. 1,310,720 bytes. A store for one root of the owner's own is a few
  kilobytes; the world's roots are 262,144 more as a block. The kernel's heap is 16 MB today
  ([`tools.md`](tools.md)), shared; a program's own block is #57.
- **A connection on a Pi 4: 2 to 6 ms of the processor.** 5.3 to 5.7 million instructions, measured, on a
  Cortex-A72 at 1.5 GHz retiring between 0.7 and 2 of them a cycle. That range is an assumption, not a figure
  for this code: it is long multiplications and checked arithmetic, and nobody has run it on the board. The
  Mac retires 4.6 a cycle on it (1.24 million cycles a connection).
- **Receiving on a Pi 4: 4 to 9 MiB a second with AES-256-GCM, 14 to 28 with ChaCha20-Poly1305**, by the same
  arithmetic with 1 to 2 instructions a cycle. Three times apart either way: a board without AES instructions
  should ask for ChaCha20 first. OpenSSL's server, left to choose, chose AES.
- **The Pi 4 has no AES or SHA instructions.** That is what is said of its processor (BCM2711) everywhere; it
  was not read from the board. `cpu_read(cpu, "id_aa64isar0_el1")` would say. The Pi 5's processor has them.
- **The time a handshake takes on the board will be the network's, not the arithmetic's**: two trips to the
  server and back, through a kernel that looks at its card when it wakes. Not estimated.

## Not measured, and it matters

- **The stack.** The verification of a chain is the deepest thing here and has never run on the bare target.
  The kernel's stack is 508 KiB. The first handshake in QEMU should be watched for it.
- **A chain with an RSA root, or a long one.** The test chain is one P-256 root and one certificate. RSA up to
  4,096 bits and P-384 are in the client and were not timed.
- **Resumption, a client's own certificate, ALPN.** In the client, not tried.
- **Anything on the Raspberry Pi.**

## The order of work for #56

1. **In cancho: the bare target builds `std.crypto` and `std.gcm`.** The two questions answer `false` there and
   the seven builtins behind them are not refused. Shown when `tests/tls/bare.cho` builds with `--std` and the
   library as it is, and cancho-ssh builds without its own SHA-256. Needs nothing of #49 to #51. Until then
   every step below has to carry a changed copy of the library.
2. **A handshake replayed in the kernel, with no network.** A program built in, lent only the heap and the
   console, given a server's bytes recorded from `openssl s_server` for a ClientHello made from fixed random
   bytes and a fixed date, as cancho's own TLS tests replay theirs. Shown in QEMU in CI: established; and the
   three refusals, each from its recording. On the board it gives the first true figures: the milliseconds, the
   stack, the memory. Needs nothing of #49 to #51.
3. **With #50: real random bytes and the real date.** The decision #50 owes first: what a random source is in
   the language (a builtin with an effect of its own, by this document's reading, since a path named
   `/dev/urandom` is another system's idea). Then rule 1 and rule 4 above, held by a test: with the date not
   known, `tls.no-date`, and no packet in the capture.
4. **With #51: `openssl s_server` on another machine**, in QEMU as `virt` and on the board, the roots a file
   under a directory the key is granted. Shown as #56 says: the handshake, its time and memory; the three
   refusals; a page whose bytes are what `curl` gets. `tests/tls/client.cho` is that program but for where it
   gets its random bytes and how it reads the roots.
5. **Afterwards, each its own change:** a server named by its certificate's hash (in cancho's client);
   ChaCha20 asked for first where there are no AES instructions; the connection's 270 KB made smaller for a
   client that makes one connection at a time (most of the 82 KB of words is the work area of one curve).

## What it needs of the tasks before it

- **#49**: that a block can lend a connection, a clock and a random source, and that a program is lent only
  those its row names. For TLS the row is the whole manifest: `net_out` to one host, `clock`, the roots' file.
  Nothing in it says "TLS", and nothing needs to.
- **#50**: the date, with 0 for "not told"; and a random source, which has to be invented in the language
  first. 96 bytes a handshake, or 32 once.
- **#51**: the four connection builtins and nothing more for a program that waits. The grant `net:host:port`
  as written there. A name looked up is wanted by whoever fetches from the world, not by a board talking to its
  neighbour.
- **#57**, though it comes later: 1.3 MB for a connection is a twelfth of today's heap. Two programs that each
  speak TLS fit; a database's cache beside them is where it starts to matter.

## The probe

`tests/tls/`, none of it part of the kernel or of CI:

| file | what |
|---|---|
| `bare.cho` | the client's calls with nobody at the other end, for `aarch64-none-elf`. Built, not run. |
| `none.cho` | the same program without them, for the sizes |
| `client.cho` | a client for the machine it is built on: `client <address> <port> <name> <roots.pem> <seconds> <times> <path> [quiet]` |
| `soften.py` | the copy of the library that never asks the processor |
| `reach.py` | what a module reaches from `main` |
| `certs.sh` | a root and four certificates, with OpenSSL |
| `measure.sh` | all of the above, run: `CANCHO=... CANCHO_SRC=<a checkout of cancho> sh tests/tls/measure.sh` |
