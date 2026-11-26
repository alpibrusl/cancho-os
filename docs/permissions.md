# Who may do what: keys, grants, versions and a record

> **Status: design, with two slices built**, in QEMU: adding a file and adding to one
> ([`storage.md`](storage.md)); and the host key kept, the keys file read, and two roles ("What is built"
> below). Grants, versions, the record and approval are not built. It was written before the kernel
> could write a single byte to a disk, because it decides how writing must work.

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
- **A key is given by adding a line**: `append KEYS.TXT reader ssh-ed25519 AAAA...`, by an owner or at
  the console. There is no taking one away yet: that is removing, which waits for versions. Until then
  a key is taken away by editing the card on another machine.

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
nothing is recorded; and the port-23 shell, where it is turned on, asks nobody anything.

## The slices

1. **Writing, in QEMU.** `fat.cho` learns to add a file and to add to one, in the order above. Checked
   by other people's tools: Linux's `fsck.fat` must find nothing wrong and `mcopy` must read back what
   was written.
2. **The host key and the keys file**, the two things SSH is waiting for. Two roles, owner and reader,
   checked for every command of an SSH session.
3. **Versions and the record**, before any agent is let near a write.
4. **The real card**: the Pi 4's SD controller, on the board.
5. **Grants for agents, and approval.**
