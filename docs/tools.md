# The tools, inside the kernel

cancho-tools (https://github.com/alpibrusl/cancho-tools) are the programs an agent reads and changes files with on
Linux and macOS: each answers in JSON, says what it may touch, and is small. Four of them, the four that only read,
are built into this kernel as they are written: `hash`, `peek`, `seek` and `list`. Not a line of them was changed
for it and none of them knows it is not on a system.

## How

A tool is a program: a `run` that takes a `Heap`, an `Args`, an `Fs` and an `Io`, and a `main` that cuts those from
the world. On a system the compiler's runtime answers what `run` asks. Here nothing is under the kernel, so the
kernel answers: `hosted` in `src/kernel.cho` has the one `system ksys(...) in { }` block of the image (cancho
docs/bare-system.md), and inside it a tool's `write_bytes` is the shell's output, its `arg` a word of the line that
was typed, and its `open_dir`, `dir_open_read`, `file_read`, `dir_list`, `dir_stat` the FAT volume, through
`src/ksys.cho`.

`build.sh` takes the tools from a checkout beside this one (`../cancho-tools`, or `TOOLS=`), and for each of the four:

- puts `module tool_<name>;` after the first line and makes `run` public;
- leaves out `main`, the last function of the file: the kernel has its own;
- gives the generated module that says how the tool was built (`toolbox.built`, one for each tool, all of one name)
  the tool's name, so that four can be in one image.

That is text moved by `awk` and `sed`, into `build/tools/`; the build stops if a tool is not written the way this
expects. What the tools share (`contract/`) is built in as it is. `TOOLS_REF` in the workflow is the commit they are
taken at.

## What they may do

Read. `ksys` refuses every way of opening a file that writes, and has no function that changes a directory; the four
tools ask for none. `HOSTKEY.BIN` is refused them as it is the shell (`files.secret`), and a name that begins with a
dot is not found and not listed. A key that may only read may run them (`reading` in kernel.cho).

`cancho authority` of the kernel gains `err_write` with them (a tool writes its usage errors there; here both streams
are the shell's output), and already had `heap`, `args`, `io_write` and the three that read files from step 3.

## What is not right yet

- **A trap in a tool is a trap of the kernel.** The tools refuse a path with `..` in it themselves, before the language
  would trap on it, and no input was found that makes one trap; but they were written for a system that would go on
  without them, and no memory left is a trap too (the heap is the kernel's, 16 MB of it).
- **The status a tool ends with is dropped.** Over SSH the session ends with 0 whatever the tool answered; the JSON
  says `"ok":false`.
- **The tools that read their input** (`tally`, `jsonq`) and **the ones that write** (`write`, `replace`, `move`,
  `archive`) are not built in. Writing must go through `files` and the record first (docs/permissions.md).
- **Time.** FAT keeps local time and no zone; `list --long` gives it as if it were UTC.
- **A listing walks the directory again for each name** (`ksys.next`), and `dir_stat` three times for each: a
  directory of a thousand names would be slow. None here is that long.
- Not tried on a real board.

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
