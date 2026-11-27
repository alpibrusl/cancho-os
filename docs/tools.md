# The tools, inside the kernel

cancho-tools (https://github.com/alpibrusl/cancho-tools) are the programs an agent reads and changes files with on
Linux and macOS: each answers in JSON, says what it may touch, and is small. Seven of them are built into this kernel
as they are written: `hash`, `peek`, `seek` and `list`, which only read, `write` and `replace`, which change a file,
and `move`, which changes a name. `write` is the kernel's one way of writing a file's contents: the shell had a
`write` and an `append` of its own, which wrote over whatever was there, and they are gone. Not a
line of them was changed for it and none of them knows it is not on a system.

## How

A tool is a program: a `run` that takes a `Heap`, an `Args`, an `Fs` and an `Io`, and a `main` that cuts those from
the world. On a system the compiler's runtime answers what `run` asks. Here nothing is under the kernel, so the
kernel answers: `hosted` in `src/kernel.cho` has the one `system ksys(...) in { }` block of the image (cancho
docs/bare-system.md), and inside it a tool's `write_bytes` is the shell's output, its `arg` a word of the line that
was typed, and its `open_dir`, `dir_open_read`, `file_read`, `dir_list`, `dir_stat` the FAT volume, through
`src/ksys.cho`.

`build.sh` takes the tools from a checkout beside this one (`../cancho-tools`, or `TOOLS=`), and for each of the seven:

- puts `module tool_<name>;` after the first line and makes `run` public;
- leaves out `main`, the last function of the file: the kernel has its own;
- gives the generated module that says how the tool was built (`toolbox.built`, one for each tool, all of one name)
  the tool's name, so that seven can be in one image.

That is text moved by `awk` and `sed`, into `build/tools/`; the build stops if a tool is not written the way this
expects. What the tools share (`contract/`) is built in as it is. `TOOLS_REF` in the workflow is the commit they are
taken at.

## What they may do

The four that read: read. `HOSTKEY.BIN` is refused them as it is the shell (`files.secret`), and a name that begins
with a dot is not found and not listed. A key that may only read may run them (`reading` in kernel.cho).

## The tools that write

`write (--create | --if-sha256 HEX) --stdin PATH` makes a file, or writes over one whose contents the caller has
named by their hash; `replace --old TEXT --new TEXT PATH` changes text in one. Both change a file the way the tools
change one on a system: it holds a lock, makes
a temporary file beside the one it changes, writes the new contents to it, has it kept, and renames it over the name.
Here those five steps are one write of the disk, and it is not the tool that makes it:

- **The lock** (`<name>.lexsys-lock`, opened to add to) is a handle and nothing else. Nothing runs while a program
  does, so it is held by being asked for; no file is made.
- **The temporary** (`dir_open_new`) is the draft: its bytes wait in memory, where a file sent with `put` waits
  (2 MB less a little; more is refused, 27). One draft at a time. The disk does not know of it.
- **`file_sync` and `dir_sync`** have nothing to do.
- **The rename** of the draft to a name is the write, done by `files.store_as`, which is `put`'s own writer: the bytes
  go to clusters that were free, are read back from the disk and compared, what the name held is kept in `OLD` under a
  number, `LOG.TXT` gains a line that says who (the console, or which key) and the SHA-256 of what the file now is,
  and the name is changed last. What that writer would print is not printed (`k[4267]`): the tool's answer is the
  tool's.
- **Removing the draft** forgets it. A draft that was never renamed was never on the disk.

What a program may not do through `ksys`, each refused with the number a system would give:

- write a name `put` may not write (13): `HOSTKEY.BIN`, `LOG.TXT`, anything under `OLD`, and `BOOT.TXT`, which a
  program started at the console may write and one started over SSH may not (docs/boot.md);
- rename a file of the disk over another, or remove one (30): no tool deletes;
- change a file the board starts from (13): the kernel's image, `config.txt`, what the firmware loads. `put` does
  that, and checks every byte;
- add to a file, or open one to write in place (30): a file changes whole or not at all;
- make a second draft while one is waiting (24), or any while a `put` is being received (16).

`move PATH NEWNAME` is the one other change: a name of the disk, a file's or a directory's, becomes another in the
same directory (`files.rename`). Never over a name that is taken (17). Nothing of the file moves and no version is
made, since what it holds does not change; the record gains a line, `move`, with both names and who. The record is
written first, then the new name, then the old one is taken away: a board that loses power between the last two has
the file under both names.

A key that may only read is refused `write`, `replace` and `move` by the shell, before the tool runs.

## A program's input

`write --stdin` reads what it is to write. `ksys.key` answers `getchar`:

- **At the console** it is what is typed after the command, shown as it is typed, until Ctrl-D. Enter is a line feed.
  Nothing else runs meanwhile: the network is not served while a program waits for a key.
- **Over SSH**, for `ssh host 'write ...' < file`: the shell keeps the line, collects what the client sends until the
  client closes its side, and then runs the line with those bytes as the program's input. They wait in memory, a
  megabyte in from where a draft waits: 983,040 bytes at most, and more is refused before the program runs.
- A program started from a shell session over SSH (not `ssh host command`) has no input: its first read is the end.


`cancho authority` of the kernel gains `dir_write` and `file_write` with `replace`, and `err_write` with the first four (a tool writes its usage errors there; here both streams
are the shell's output), and already had `heap`, `args`, `io_write` and the three that read files from step 3.

## What is not right yet

- **A program that goes wrong takes the kernel with it, and the board then starts again.** A trap in a tool is a trap
  of the kernel: reading past the end of something, or no memory left (the heap is the kernel's, 16 MB of it). The
  kernel says what happened on its console and, on a Pi that had been up ten seconds, resets the board through its
  watchdog; the firmware loads the kernel from the card again, and `BOOT.TXT`, if the card has one, brings the
  network and SSH back. About half a minute in which nobody is answered, the session that ran the program is lost,
  and the record has no line for it. On QEMU's `virt`, which has no such watchdog, the kernel stops as before.
- **A program that never ends** is ended the same way once `watch on` has been typed at the console, or is a line
  of `BOOT.TXT`: the watchdog counts fifteen seconds while a program runs, and the functions a working program
  keeps calling (`read_at`, `write`, `next`, `step`, `key`) start the count again. It is off until asked for,
  because QEMU's Pi resets the moment the watchdog is started, so a kernel that always started it could not be
  tried there. Without it, a program that never ends stops the board until its power is cut.
- **What is still wanted**: a trap that ends the program and not the kernel, so that the session goes on and the
  one who ran it is told. That needs the program's memory to be its own, thrown away whole, and the compiler to
  take a trap inside the block that lends the system to the block's end (cancho docs/bare-system.md).
- **The status a tool ends with is dropped.** Over SSH the session ends with 0 whatever the tool answered; the JSON
  says `"ok":false`.
- **`tally` and `jsonq`**, which read their input, are not built in yet, though a program now has one; nor is
  `archive`, which makes directories.
- **What a tool prints is cut at 4,000 bytes over SSH** (the shell's queue). `write` and `replace` print the lines
  that changed: `--max-diff-lines 0` keeps the answer short.
- **`disk.extend`**, which added to a file in place for the shell's `append`, has no caller now.
- **Why a write failed is mostly lost.** `files.store_as` says why in words, which are not printed for a tool, and
  answers yes or no: a full disk and a disk that could not be read are both 5 to the tool.
- **A tool's write is recorded as `write`**, the shell's word: the record does not say a tool made it. A `move` has
  no hash in its line, so `checklog.py` does not check the file under its new name.
- **Grants.** A tool may write what its caller may. There are two kinds of caller, owner and reader; a key for an
  agent that may write under one directory only is docs/permissions.md, not built.
- **Time.** FAT keeps local time and no zone; `list --long` gives it as if it were UTC.
- **A listing walks the directory again for each name** (`ksys.next`), and `dir_stat` three times for each: a
  directory of a thousand names would be slow. None here is that long.
- On the real board `write`, `replace` and `move` were tried once each over SSH (below), not at its console, and
  not on the names the kernel keeps to itself: those refusals were seen in QEMU only. The four that read are: they ran on the Raspberry Pi 4 from its card on
  2026-11-27, and `hash KERNEL8.IMG` there gave what `shasum` gives the same file on a Mac.

## Measured

In `qemu-system-aarch64` as `virt`, on a FAT16 volume macOS made (four files, one with a long name, and a directory),
with the same four tools built for the Mac by the same compiler and run on the same files:

- six commands (`hash` of four files and one that is not there, `peek`, `seek` in three files, `seek` given a
  directory, `list --long` of the directory, `list`) answer 24 lines. 22 are the same bytes on both. The two that
  differ are the times in `list --long`, by the 3,600 seconds between the Mac's zone and UTC.
- the SHA-256 of a 300,000-byte file is what `shasum` gives.
- `hash` and `list --long` forty times each in one boot, then the shell's `heap` check: nothing wrong.
- over SSH with OpenSSH's client, `hash NOTE.TXT` answers the same two lines.
- the image is 629,872 bytes with the four tools, 432,672 without.

CI does the comparison again on volumes Linux's tools made, with the zone set to UTC, where every line must be the same.

`replace`, the same way (2026-11-27), on FAT16 and FAT32 volumes macOS made, with a file of 154,857 bytes, one under a
directory and one with a long name:

- nine commands (four that change a file, one that finds it already changed, and four that are refused: a hash that
  is not one, a name that is not there, a path with `..`, a dry run) answer the same bytes as the same tool on the
  Mac, twelve lines with the four hashes asked afterwards; the four files are then the same bytes as the Mac's.
- macOS's `fsck_msdos` finds nothing wrong with either volume; `OLD/00000001.V` is the file as it was; no name
  with `lexsys` in it is on the volume; `tests/checklog.py` follows the four lines of the record and finds each
  file to be what its line says.
- on the Pi 3's SD card in QEMU the same; over SSH with the owner's key the record's line says `key:` and its
  first sixteen digits, and `owner`; with a key that may only read the shell refuses (`./keys.sh`).
- the image is 677,008 bytes with the five tools.

`move`, the same way: seven commands (three files renamed, one of them to and one from a long name, a directory
renamed, a name that is taken, one that is not there, a new name with a `/` in it) and the hashes of the four files
afterwards answer the same twelve lines as on the Mac; the files are the same bytes under their new names;
`fsck_msdos` finds nothing wrong; the record has four lines that follow. `move` to `KERNEL8.IMG` is refused (13).
The image is 723,024 bytes with the six tools.

`write` and a program's input (2026-11-27), in QEMU as `virt`: a file typed at the console (two lines and Ctrl-D) is
those bytes; written over with `--if-sha256` of what it held, and refused with a hash it does not have; `--create`
on a name that is taken is refused; `BOOT.TXT` is written at the console and refused over SSH, `KERNEL8.IMG` and
`CONFIG.TXT` refused both ways. Over SSH with OpenSSH's client, 220,890 bytes sent as the command's input become a
file whose SHA-256 is what `shasum` gives the bytes that were sent, and the record's line says which key. `./keys.sh`
passes with `KEYS.TXT` written by `write`. The image is 766,000 bytes with the seven tools.

On the Raspberry Pi 4, from its SD card, over SSH through another machine (2026-11-27, 0.0.41): 106,890 bytes sent
as the input of `write --create --stdin TRY.TXT` are a file whose SHA-256, by the board's `hash`, is what `shasum`
gives them on the Mac; `replace` changes one line of it and `seek` finds the new text at line 1,778; `move` renames
it; `write --create` on the new name is refused; the record follows, 33 lines; `heap` finds nothing wrong after.

A program that goes wrong (2026-11-27, 0.0.44). In QEMU as a Pi 3 with an SD card: `fail trap` and `fail memory`,
each after the board had been up twelve seconds, are reported ("cancho trap"), the board resets, and the same card
then answers `about` and `hash`; `fail trap` in the first seconds leaves it halted. On the Raspberry Pi 4, from its
card, over SSH: `fail trap` and `fail memory` each reset the board, and it answered again by itself, through
`BOOT.TXT`, within about forty seconds; with `watch on` typed at its console, `fail spin` was ended by the watchdog
and the board answered again as soon after. The record followed afterwards, 44 lines.
