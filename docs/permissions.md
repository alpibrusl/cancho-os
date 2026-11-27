# Who may do what: keys, grants, versions and a record

> **Since 2026-11-27** the shell has no `write` and no `append`. A file's contents are written by cancho-tools' `write`,
> built into the kernel: `write --create --stdin NAME`, or `--if-sha256 HEX` for a file that is there, then the text and
> Ctrl-D at the console, or the text as the command's input over SSH ([tools.md](tools.md)). It goes through the same
> writer: the old contents to `OLD`, a line in the record. Where a table below says `write NAME text` or `append`, that
> is what was typed when it was measured.

> **Status: design, with three slices built**, in QEMU: adding a file and adding to one
> ([`storage.md`](storage.md)); the host key kept, the keys file read, and two roles; and versions and
> the record; and an agent's key with grants ("What is built" below, three times). Approval by a key is not built, and
> only the driver's own session ([`sdcard.md`](sdcard.md)) has run it on a real card. It was written before the kernel could write a single byte to a
> disk, because it decides how writing must work.

## What is wanted

cancho-os is meant to be worked on by agents as much as by people. The usual answer to "who may do
what", users and file permissions, gives a program everything its user may do: an agent that runs as
you can reach all that you can, and one wrong instruction reaches all of it. That is the thing to avoid.

## The shape

**Who is a key, not a name.** A person is an ed25519 key, the one they log in over SSH with. An agent is
a key too, with a statement signed by a person's key: what it may do, and until when. There are no
passwords, no table of users and no superuser. The serial console, which needs a hand on the board, is
above every key, as it already is for `net ssh on` and `load`.

**What is a grant, and nothing is had without one.** A grant names a part of the disk, the rights on it
and its limits:

| right | what it allows |
|---|---|
| read | `ls`, `cat`, `sum` |
| append | add to the end of a file; what is there stays |
| write | replace a file: the old contents are kept as a version |
| delete | remove a file: its contents are kept as a version |
| purge | remove a version for good |
| control | open and close ports, load a kernel: the console only |

A grant can be passed on narrower and never wider, which is what `narrow` does for hardware in cancho
today: the rule of the system and the rule of the language are one rule.

**Three things that users and permissions have no word for.**

- *Who asked, who acted, under which grant.* Every change is recorded with all three. "The agent did it"
  is not an answer; the chain back to a person's key is.
- *Undo, by default.* A write makes a new version and a delete leaves one. An agent's mistake is then
  something to revert, not something that happened.
- *Approval for what cannot be undone.* Purging, replacing the kernel, moving a servo: the one who wants
  it proposes, a person's key approves, then it happens. The roadmap already says the human "approves
  what cannot be undone".

**A record nobody can rewrite.** One file that is only ever added to. Each line names the key, the grant,
the action, what it was done to and a hash of the contents, and ends with a hash of the line before it
and itself, so that a line changed or removed afterwards breaks every hash after it. Agents get append
on it and nothing else.

## On the card

The card is FAT, so that the firmware can read the kernel from it and any other machine can read the
rest. FAT knows nothing of any of this: it is the kernel that enforces it, and only while the kernel is
what is running.

| file | what |
|---|---|
| `KEYS.TXT` | a line a key: `owner` or `reader`, then the key as `ssh-keygen` writes it. Read when SSH is turned on. The key built into the image stays as the first owner, so that a card with no file is not a locked door |
| `HOSTKEY.BIN` | the SSH host key's 32 bytes, written once, so that the kernel is the same host after a restart |
| `LOG.TXT` | the record, in text, a line an action |
| `OLD/` | the versions: what a file held before each write or delete, under a number the record names |

**A write never changes what is there.** The new contents go to clusters that were free, and the table
is made to chain them; then, last, the one directory sector that names them. A power cut before that last
sector leaves the file as it was and some clusters used by nothing, which any FAT checker frees. There
is no moment at which the file is half one thing and half another.

## What this does not give

- **Nothing against someone who takes the card out.** They read all of it. Protecting what is stored
  needs it encrypted on the card, which is another piece of work.
- **No time of day.** The kernel has no clock that knows the date. The record orders things by a count
  that goes up, and by how long the machine had been running.
- **No protection from the kernel itself,** or from whoever holds the console.
- **Not a sandbox for programs:** there are none yet. When there are, a program is handed its grants as
  capabilities, and that is where this design and cancho's own meet.

## cancho-forge

Forge keeps budgets, approvals and evidence for a company of agents. This is the part under it: the
kernel provides the mechanism (keys, grants, versions, the record, the step of approval) and forge the
policy (which company is given what). Neither should grow the other's half.

## What is built (slice 2)

- **The host key is kept.** When SSH is first turned on, `HOSTKEY.BIN` is read if the disk has it; if
  not, a key is drawn as before and written there. After a restart the kernel is the same host. The
  shell will not show, copy or add to that file, for anyone.
- **`KEYS.TXT` is read** when SSH is turned on, and again whenever the shell adds a file or adds to
  one. `src/keys.cho` reads it, and is pure like `inet` and `fat`. The keys built into the image come
  first and are owners; eight keys in all.
- **Two roles.** A session over SSH has the role of the key that logged in. An owner's runs anything
  the shell has. A reader's runs what changes nothing and reaches nowhere (`ls`, `cat`, `sum`, `disk`,
  `about`, `mem` and the like) and is told so for anything else.
- **A key is given by adding a line** to `KEYS.TXT`, `reader ssh-ed25519 AAAA...`: the file is written again with
  the line in it (`write --if-sha256 HEX --stdin KEYS.TXT`), by an owner or at the console. One is taken away by writing the file again without it, or by removing the file (slice
  3): the keys are read again after either, and what the file held stays in `OLD`.

Measured, at the commit that adds this section (`./keys.sh`, QEMU's `virt`, OpenSSH's client, three keys
`ssh-keygen` made; on a FAT32 and a FAT16 volume):

| who | what | result |
|---|---|---|
| the console | `write KEYS.TXT reader ssh-ed25519 ...`, then `net ssh on` | "keys built into this image that may log in: 1, and from KEYS.TXT on the disk: 1"; "ssh host key (new, and kept on the disk as HOSTKEY.BIN)" |
| the owner's key | `write O.TXT ...`, `cat O.TXT` | written, and read back |
| the reader's key | `ls` | the files, `KEYS.TXT` and `HOSTKEY.BIN` among them |
| the reader's key | `write R.TXT ...`, `ping 10.0.0.1` | "this key may only read: that needs an owner's key", twice; no `R.TXT` afterwards |
| either key | `cat HOSTKEY.BIN`, `copy HOSTKEY.BIN STOLEN.BIN` | "the host key is kept by the kernel", twice; no `STOLEN.BIN` afterwards |
| a key in neither place | `about` | "Permission denied (publickey)" |
| a second start of the same disk | `net ssh on` | "ssh host key (read from the disk: the same as before the restart)", and the same key, character for character |

and 4 tests of `keys.cho` on its own (a line's role and bytes against Python's `base64`; lines that are
not keys; 23,040 damaged lines, none traps). `./authority.sh` says "as recorded".

What it does not do: a reader can still read every file but the host key, `KEYS.TXT` included (it holds
only public halves); the role is the shell's doing, command by command, not a grant on part of the disk;
and (until [`update.md`](update.md) removed it) the port-23 shell asked nobody anything.

## What is built (slice 3): versions and the record

- **A write over a file keeps what was there.** The new contents go to free clusters. Then what the file
  held is given a name of its own in the directory `OLD`, a number and `.V` (`OLD/00000003.V`). Then the
  record gets its line. Last, the file's own directory entry is pointed at the new contents: one sector,
  written once.
- **`remove <name>`** is the same without new contents: the version's name, the line, then the file's
  name is taken away.
- **A version is read like a file**: `versions` lists them, `cat OLD/<name>` and `sum OLD/<name>` read one,
  and `copy OLD/<name> <new>` brings one back under a name that is free.
- **`purge <number>`** gives a version up for good and its clusters back. It is taken at the serial
  console only: an owner's key over SSH is told so. That is the place approval by a person's key will
  take (slice 5); until then the person is whoever holds the console.
- **`LOG.TXT` is the record.** A line a change, added before the change's last sector is written, so
  nothing takes effect that the record does not have:

  ```
  <number> <ticks> <who> <role> <action> <target> <from> <version> <bytes> <contents> <chain>
  3 809 key:da8e761b716a82a8 owner write O.TXT - - 20 8b318dc7f66b... 5942da9fc95a...
  ```

  `who` is `console`, `kernel` (the host key, written by the kernel itself), or `key:` and the
  first 16 hex digits of the SHA-256 fingerprint `ssh-keygen -l` shows for the key that logged in.
  `contents` is the SHA-256 of what was written; `chain` is the SHA-256 of the line before's chain and
  this line. `ticks` is how long the machine had been running: there is still no time of day.
- **The kernel checks it and so can anything else.** `record` walks the file and says how many lines it
  has and the first that does not follow from the one before. `tests/checklog.py` does the same with
  Python's `hashlib` and nothing of ours. While a line does not follow, changes are taken at the console
  only.
- **The shell will not write, add to, copy onto or remove `OLD` or `LOG.TXT`.** `src/record.cho` makes and
  checks the lines and is pure, like `inet`, `fat` and `keys`.

Measured, at the commit that adds this section (QEMU's `virt`; FAT32, FAT16, and FAT32 behind a
partition table; macOS's `fsck_msdos -n` and a mount here, Linux's `fsck.fat -n` and `mcopy` in CI):

| what was done | result |
|---|---|
| `write A.TXT one`, `write A.TXT two`, `append A.TXT more` | `A.TXT` reads `two`, `more` on another system; `OLD/00000001.V` reads `one` |
| `remove BIG.BIN` (300,000 random bytes), `copy OLD/00000002.V C.BIN` | `BIG.BIN` gone from the top directory; the version and `C.BIN` are the original, byte for byte |
| `write A.TXT` 70 times on FAT16 | 69 versions; `OLD` grew past its first cluster; the checker finds nothing wrong |
| `purge 1` at the console; `purge 2` by an owner's key over SSH | one cluster given back and the free count right; "taken at the serial console only" |
| `remove LOG.TXT`, `write OLD x` | "that name is the kernel's", twice |
| the record after those, by Python | every line follows; `C.BIN` and `A.TXT` hold what their lines say |
| the same disk started again, one more write | `record`: one line more, each following |
| one letter of line 1 changed by another machine | `record`: "line 1 does not follow"; a write over SSH refused and no file made; a write at the console taken |
| `./keys.sh`: the owner's key writes `O.TXT`, then removes `KEYS.TXT` | the record names the key by the digits `ssh-keygen -l` gives; the reader's refused write has no line; afterwards the reader is not let in |

and 5 tests of `record.cho` on its own (three lines Python chained are found whole; a line changed,
removed or cut short is found, and which; the lines it makes are Python's, byte for byte; every byte of
the file as 16 others and the file cut at every byte: none traps).

What it does not do:

- **It does not catch someone who rewrites the whole record.** The chain shows a line changed or taken
  out. Whoever holds the card can make a new file whose every line follows. Catching that needs the last
  chain kept somewhere the card's holder cannot reach, which is not built.
- **A power cut was not tried.** The order is argued, not measured. Cut between the version's name and
  the file's own, two names point at the same clusters until the file's is written (a checker reports
  it; no byte is lost). Cut between a line and its change, the record has a line for a change that did
  not happen: the file does not hold what the line's hash says.
- **A version's name is a number.** Which file it was of is in the record, not in `OLD`.
- **A file is written whole.** Nothing adds to one in place; `write` and `replace` take up to a megabyte.
- **Nothing is ever purged by itself**: a disk that is written over and over fills.
- **No grants.** An owner's key may still do everything but purge; there are no keys for agents yet.

## What is built (slice 5, first part): an agent's key and its grants

A third kind of line in `KEYS.TXT`:

```
agent ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... read:DOCS write:WORK/OUT the builder
```

- **A grant is a right and a directory**: `read:<path>` or `write:<path>`, the directory and everything under it;
  `/` is the whole disk. `write` is `read` too. The first word that is not one of those ends them, and the rest of
  the line is for people. Four grants a key, a path of 62 bytes at most. A key with no `agent` line is granted
  nothing, and one that is also an owner's is an owner's.
- **An agent runs the tools and nothing else**: `hash`, `peek`, `seek`, `list`, `write`, `replace`, `move`, and
  `help` and `about`. Every command of the shell's own is refused it, the ones that only read too (`ls`, `cat`):
  they do not ask about grants, and the tools do.
- **One place asks.** Everything a tool does with a file comes through `src/ksys.cho`, and each of its functions
  asks `may` first: to pass into a directory, to list one, to read a file, to ask what a name is, to make a file, to
  hold its lock, to rename. Reading needs a grant that covers the path; writing one of `write`. A directory above
  what is granted may be passed through and seen to be a directory, and nothing in it listed. What is refused is
  refused as a system refuses it (13), so a tool says `io.permission-denied`.
- **The grants are read when they are used.** Before each line of an agent's session the kernel reads `KEYS.TXT`
  again and takes that key's grants from it (`keys.grants_for`). A grant taken out of the file is gone at the next
  command, with no session to end.
- **Giving one is an owner's act, and is recorded as one.** `KEYS.TXT` is written by an owner's key or at the
  console, with `write`; the record's line for that write says who. The record's lines for what the agent then
  does say `key:` and its digits, and `agent`.
- `src/keys.cho` reads the line and answers whether a path is covered, and is pure: `tests/keys_test.cho` holds it to
  what is and is not covered (a name that only begins like a granted one, letters of either case, the top of the
  disk), and no bytes of a file make it trap.

Seen in `qemu-system-aarch64` as `virt`, with OpenSSH's client (`./agents.sh`, FAT32 made by macOS), a key granted
`read:DOCS write:WORK/OUT`:

| who | does | sees |
|---|---|---|
| the agent | `list DOCS`, `peek docs/readme.txt` | the listing; the file's text |
| the agent | `write --create --stdin WORK/OUT/R.TXT`, `replace` in it, `move` it to `DONE.TXT`, `hash` | each done |
| the agent | `hash SECRET.TXT`, `peek KEYS.TXT`, `list .`, `list WORK`, `hash` and `seek` in `WORK/OTHER`, `hash OLD/00000001.V` | `io.permission-denied`, seven times, and no byte of any |
| the agent | `write` to `DOCS`, to `WORK/OTHER` and to the top; `replace` in `DOCS`; `move` in `DOCS` | `io.permission-denied`, five times; no file made |
| the agent | `ls`, `cat SECRET.TXT`, `remove`, `copy`, `net ssh off`, `restart` | "this key is an agent's", six times |
| the owner | `cat LOG.TXT` | three lines by `key:... agent`: two `write` and a `move`; none for what was refused |
| the owner | writes `KEYS.TXT` again with `read:WORK/OUT` | written |
| the agent | the same `write` to `WORK/OUT`; `hash WORK/OUT/DONE.TXT` | refused; answered |

macOS's `fsck_msdos` finds nothing wrong with the volume afterwards, and `./keys.sh` passes as before.

What this part is not:

- **Not a statement signed by a person's key.** "The shape" says an agent's key comes with one. Here the grant is a
  line of a file only an owner or the console may write, and the chain back to a person is the record's line for
  that write. A grant cannot yet be passed on narrower by the agent itself.
- **"Until when" is a day, and is only as good as the date.** `until:YYYY-MM-DD` after a line's grants ends them
  when that day (UTC) is over (0.0.47). The board is told the date by a machine on its network and believes it
  ([`clock.md`](clock.md)): a board not told the date takes the grant to have ended, a date may not go back
  before the record's last line, and a word that begins `until:` and is not a day grants nothing rather than for
  ever. Whoever can answer for the time server's address can still make a day end early, or late by any date after
  the record's.
- **Two rights of the six.** There is no `append`, `delete`, `purge` or `control` for an agent: no tool does them.
- **No approval step** for what cannot be undone: an agent can do nothing of that kind yet.
- **Owners and readers are not asked about grants.** Their sessions are as they were; a reader still may not write.
- **A directory's short alias is another name.** A grant on `long-directory-name` does not cover the same directory
  reached as `LONG-D~1`: that is refused, which is the safe way to be wrong.
- **An agent can stop the board.** A trap in a tool is a trap of the kernel (docs/tools.md), and a tool that asks
  for all the memory traps. Grants bound what an agent can read and change, not whether the board stays up.
- Eight keys in all, and a `KEYS.TXT` of 2,048 bytes at most, as before.
- Not tried on a real board.

## The slices

1. **Writing, in QEMU.** `fat.cho` learns to add a file and to add to one, in the order above. Checked
   by other people's tools: Linux's `fsck.fat` must find nothing wrong and `mcopy` must read back what
   was written.
2. **The host key and the keys file**, the two things SSH is waiting for. Two roles, owner and reader,
   checked for every command of an SSH session.
3. **Versions and the record**, before any agent is let near a write.
4. **The real card**: the Pi 4's SD controller, on the board. Built: [`sdcard.md`](sdcard.md).
5. **Grants for agents, and approval.** The first part is built (above): an agent's key, `read` and `write` on
   directories, the tools held to them. Signed statements, passing a grant on, and approval are not.
