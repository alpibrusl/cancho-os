# Programs that stay, and programs that fail

> **Status: design, nothing built.** For #52 (a program that keeps running beside the shell) and #53 (a program
> that fails ends alone), of the epic #60. Every number here says how it was got; what was not measured is listed
> in section 8. The compiler changes it asks for are described, not made. Section 11 is what is left to the owner.

## 1. What is missing

Today (0.0.48) `hosted` in `src/kernel.cho` runs a program inside the one `system ksys(...) in { }` block of the
image and comes back when the program has ended ([`tools.md`](tools.md), cancho `docs/bare-system.md`). Three
things follow from that:

- **Nothing else runs meanwhile.** The shell, the network and SSH are served from the shell's loop (`getc`), and
  the loop is not running while a program is.
- **A program that serves cannot exist.** cancho-db's engine waits for its connections in one loop
  (`poller_wait`, cancho-db `src/serve.cho`); here that wait would never return to anybody.
- **A trap in a program is a trap of the kernel.** Every check of the language ends in `udf #0xc11f`, the
  processor takes the exception, `board/boot.S` throws the stack away and enters `main` again, and `main` reports
  and resets the board. The kernel's state was in a region of the first `main`, so the second cannot go on.

What exists and is kept: interrupts stay masked and polled; no code runs behind cancho's back; the kernel has no
foreign function and `board/boot.S` gains no logic; a program is lent what it has and reaches the disk only by
asking `ksys`.

## 2. How a program that waits gives the processor back

### What the first user holds across a wait

cancho-db at `a92ea11`, `src/serve.cho`, read for this:

- `run` (line 1451) takes **twenty** borrowed parameters from its caller (the pager, the engine, the buffers of
  every connection) and holds, across `poller_wait` at line 1462: all twenty, a `Poller` and a `conns.Table`
  (both linear), one region and one borrow.
- There is a **second** place it waits: `writable` (line 276), which makes a poller of its own and waits up to
  the server's limit for one client to take bytes. It is called from `put` (line 307), which every answer to a
  client goes through.
- `conn_read` and `tcp_accept` do not wait there: they answer `Again`.

So what cancho-db holds across a wait is not one value. It is a stack: frames of several functions, each with
borrows of what its caller owns.

### The ways compared

**(a0) A stack for each program, and a switch the kernel writes.** The familiar one: a function `switch(from, to)`
the kernel calls where it likes, and `hosted` running once on each program's stack. Refused, for three reasons.
The kernel cannot write it: a switch changes the stack pointer, cancho has no way to say that, and the rule here
is no foreign function and no callable symbol in `boot.S`. It breaks the lending: each program's stack would be
inside its own open `system` block, and each block holds `con`, `k`, `h` as a unique borrow, so two unique borrows
of the kernel's state would be alive at once. And it lets the kernel be left in the middle of one of its own
functions, with its state half changed, which is the shared mutable state `docs/issues/04` keeps out.

**(a) A stack for each program, and the switch written by the compiler at the edge of the block.** The `system`
block becomes a block that can be left and entered again. A program runs on a stack in its own memory. It leaves
in three ways, all the same code: it ended, it waits, or it trapped. Leaving ends the lending, as the closing
brace does today; the kernel is entered again after the block. Entering the block again with a program that
waits lends again and goes on where the program was. The switch is a fixed run of instructions the compiler
writes into the module, as it writes `cancho_trap` and the functions of `syscode.cho`. The kernel calls nothing
foreign and `boot.S` does not change. This is the one recommended; the rest of the document is its detail.

**(b) The program written as a step function the kernel calls.** Honest about what is held: between two calls a
program is one value, and its type says what is in it. Refused for now, for what it costs and what it does not
save:

- cancho-db would be rewritten, not adjusted. The twenty borrows of `run` would have to become things the
  program owns, since a borrow cannot be kept in a value that outlives it; the loop's body would become the step;
  and `writable`, several calls deep, would have to become a state of every function above it.
- cancho-tools would not change (none of the nine waits), so nothing is learnt from them.
- It does not give #53. A trap in the middle of a step must still come back to the kernel, which needs the
  kernel's saved registers and the program's memory thrown away: half of a switch and all of section 5. With
  (a), the other half is the same twenty-five instructions.

**(b') The compiler turning a waiting program into steps.** The row already says which functions can wait (`poll`
is in theirs), so the compiler knows which to transform. But a frame kept across a wait holds borrows and open
regions, and making those into a value is the hard part of every language that has done it. It is a large change
to a compiler whose every new statement is known in ten places (`bare-system.md`, section 10). Not now. If it is
ever built, the system side of (a) (what `ksys` answers, the table of programs) does not change.

**(c) The wait as a call.** `ksys`'s waiting function could call one turn of the kernel's loop and return when
what was waited for is there. No switch and no compiler change. It serves exactly one waiting program: a second
that waits is called from inside the first's wait and sits on top of it, so the first cannot go on until the
second has ended. And a trap still ends everything. Refused.

**(d) A program on another core.** The Pi 4 has four and three are parked. Two cores means the kernel's state is
shared between two things running at once. Refused: it is the opposite of what this kernel is built on.

**(e) The processor's protection** (a lower exception level, a translation table for each program). The epic puts
it afterwards, as hardening. What (a) fixes on the way to it: a program's memory is one range of addresses, which
is what a table would map.

### Judged by what cancho's rules make checkable

| | (a0) kernel's switch | (a) the block's switch | (b) step function |
|---|---|---|---|
| what a program holds across a wait | its stack, and a share of the kernel's | its stack, all of it inside its own memory; handles; nothing of the kernel's | one value of a known type |
| the kernel's state while a program waits | lent to several at once | lent to nobody: the block is closed | lent to nobody |
| can the kernel be left half way through its own function | yes | no: a program is left only between two answers | no |
| what the lending of the block means with two programs alive | not sound | what it means today, for one at a time | what it means today |
| cancho-db's loop | unchanged | unchanged | rewritten |
| a trap ends the program alone | no | yes, by the same code | only with half of (a) added |
| asked of the compiler | a foreign function | sections 3 and 5 | nothing for waiting; section 5 for traps |

What (a) gives up against (b): what a waiting program holds is not written in a type. It is stated a level down
and checked there: everything it holds is inside its block or is a number in a table of the kernel's (section 5),
and `programs` lists both.

### What the lending means when two programs are alive

The compiler takes one `system` block and keeps what is lent in globals (`@cancho_sys_on`, `@cancho_sys_lent`,
`compiler/syscode.cho`). With (a) that stays one block and one set of globals, because **only one program is ever
inside the block**:

- A program that is left (waiting, ended or failed) has had `@cancho_sys_on` set to 0 on the way out. What was
  lent is back with the kernel, as after the closing brace.
- The functions the compiler writes for a hosted builtin load what is lent **each time they are called**
  (`system_open`). A program that is entered again is lent again and reads the new values. Nothing of what was
  lent the first time is kept on its stack: the only frames that cross a wait are the program's own and the
  compiler's small function, which loads again when it goes on.
- A function of `ksys` always runs to its end. A wait is not taken inside one: the function answers "later"
  (below), returns, and the compiler's function leaves the block. So no cancho function of the kernel is ever
  suspended, and none holds a borrow across a wait.
- What differs for each program is what the kernel chooses to lend it: its own table of handles (`h`), its own
  line. The kernel passes the ones of the program it is entering.

Two things of today's globals are a program's own and must move into its memory: `@cancho_sys_args`, the 16,384
bytes its arguments are copied to (`[64 x [256 x i8]]`: `arg` answers bytes that live there, and a program may
keep them across a wait while another program is given other arguments), and `@cancho_argc`.

### Waiting, and taking turns

- **"Later".** A function of the module may answer one number no operation uses (the least whole number). The
  compiler's function then leaves the block; when the program is entered again it asks the same function again
  with the same arguments. Before answering "later", `ksys` notes in the program's entry what it waits for (which
  handles, until when). The kernel enters it again when that is there or the time has come. Entering it too soon
  is harmless: it is told "later" again.
- **Which calls wait** is `ksys`'s choice: `poller_wait` with a time, `getchar` at a console with no key yet, a
  connection that is being made. For cancho-db that is `poller_wait`, in its two places.
- **The kernel's turn at any call.** A program that never waits but keeps asking (`hash` of a large file) would
  hold the board as long as it runs. So a function of `ksys` may also set a word, "others are due", when the
  program has had the processor longer than a slice; the compiler's function then leaves the block after the
  answer, keeps the answer, and returns it when the program is entered again. A program is never left anywhere
  else: not at an instruction, not by an interrupt.
- **A program that computes and asks for nothing** holds the board. The watchdog ends it with the board
  (`watch on`, [`tools.md`](tools.md)), as today. The count starts when a program is entered and stops when it is
  left.
- **Order.** The shell's loop does one pass of what `getc` does now (the console, the network, SSH), then enters
  one program that can go on, the one that has waited longest. So the console and SSH are looked at between any
  two turns of programs.

### What cancho-db needs changed

For waiting: nothing. Its `poller_wait` is answered by a function of `ksys` that says "later" until a connection
has something or the time is over. What it needs beside that is other tasks of the epic: the poller, listener and
connection operations in the lent system (#51, #54), the clock (#50), a file changed in place (#55).

## 3. What the compiler must do

In alpibrusl/cancho. Described here so that it can be judged; none of it is made.

**The statement.** The block names where the program lives. The words are the owner's to choose (section 11):

```
system ksys(con, vio, dma, stage, pm, k, line, h) runs (mem, at, size) as (heap, args, fs, io) in {
    which_tool.run(heap, args, fs, io)
}
```

- `mem` is a capability over the memory programs live in (section 6), `at` and `size` whole numbers: the block of
  this program. The first bytes of the block are the compiler's: the state of the program, its saved registers,
  its allocator and its arguments.
- **Reaching the statement** reads the state. *Fresh*: the stack is set at the top of the block, what is lent is
  stored, and the body starts on that stack. *Waiting*: what is lent is stored and the program goes on.
  *Ended or failed*: nothing runs.
- **After the statement**, in every case, nothing is lent. The state word says which of three happened, and
  beside it are the value the body ended with, or why it failed and at which address.
- **The body sees nothing of the function around it** except whole numbers and booleans, which are copied when
  the program starts, and it assigns to nothing outside itself. It runs across several calls of that function,
  whose own variables are gone by the second. Its value is kept in the block. This needs the capabilities the
  block makes (`as (...)`, #49 and `bare-system.md` section 4): with them the body has no reason to name anything
  else.

**The switch.** The registers a function must keep for its caller, by the processor's calling rules: x19 to x28,
x29, x30, the stack pointer, and d8 to d15. Twenty-one words. They are stored in the save area of the one that
leaves and loaded from the save area of the one that comes: twenty-five instructions (`tests/switch_probe.S` is
exactly that run). The kernel's save area is one global of the module, `@cancho_sys_back`; a program's is in its
block. A program's very first entry loads a stack pointer and a return address the statement put there.

**The functions of `syscode.cho`.** Each becomes, around the call of the module's function:

1. *enough stack left?* If the stack pointer is nearer than a fixed margin to the end of the program's stack, a
   trap, taken as the program's (below). The module's function runs on the program's stack, and the kernel's own
   code must not be what overruns it.
2. `@cancho_sys_on` to 2 and the allocator to the kernel's (section 6); the call; the allocator back and
   `@cancho_sys_on` to 1.
3. the answer is "later": leave the block; when entered again, load what is lent and go to 2.
4. "others are due" is set: clear it, leave the block; when entered again, return the answer.

**The trap.** `cancho_trap` is defined in `build_module` of `compiler/driver.cho` (line 341 at `f1fa983b`): one
`udf #0xc11f`, and LLVM writes it in line wherever a check fails (the image of 2026-11-27 has 8,322 `udf` and no
call of `cancho_trap`: counted in its disassembly). For the bare target, in a module that has a `system` block,
it becomes a function that is not written in line:

```
cancho_trap:
    if @cancho_sys_on == 1:        a program was running
        state of the program = failed; why = @cancho_sys_why; where = the address that called
        @cancho_sys_on = 0
        switch to @cancho_sys_back      (the kernel goes on after the block)
    else:
        udf #0xc11f                     (as today: the vector, `main` again, the report, the reset)
```

A trap site stays one instruction, a call where a `udf` was. `@cancho_sys_why` is 1 unless the place that traps
says otherwise: the allocator of `compiler/runtime/bare.ll` stores 2 before its three traps (no memory left), and
the check of the stack stores 3. Since the block is found after `cancho_trap` is written, the driver writes the
globals of `syscode.system_globals` for every module of this target, or writes the trap among the constants.

**The stack's end.** Section 5 needs a program's stack never to leave its block. Proposed: at the start of every
function, for this target, the stack pointer is compared with a global, `@cancho_stack_end`, and below it is a
trap with why 3. The global is the program's while it runs and the kernel's while the kernel does. The margin of
step 1 above and a zone left unused below the limit cover the frame of the function that is being entered: the
largest frame of the 583 functions of the image of 2026-11-27 is 3,040 bytes and the median 80 (read from its
disassembly: what each function takes from the stack pointer). What the check costs is not measured (section 8).
The other way, a page that is not mapped below each stack, is in section 11.

**The allocator.** Section 6.

**Two backends.** The LLVM backend is the one the kernel is built with. The backend of cancho's own (cancho#840)
writes instructions itself and needs the same switch and the same check when it reaches this target.

## 4. What a running program is to the system

There are no processes here, no owner of a process, and no signals. A running program is an entry in a table of
the kernel's, and everything about it is in the entry:

| | |
|---|---|
| its number | counted from 1 since the board started; never used twice in one boot |
| the line it was started with | the word that names the program, and its arguments |
| who started it | `console`, or `key:` and sixteen digits of the key's fingerprint, as the record writes it |
| in which role | `owner`, `reader` or `agent` |
| under which grants | for an agent, the `read:` and `write:` of its line of `KEYS.TXT` (and, with #51 and #54, hosts and ports) |
| what its row says | from the table #49 makes at build time: what it can touch at all |
| its memory | where its block is, how large, how much is used, how deep its stack has been |
| what it holds | open files and directories, a draft, a port it listens on, connections |
| its state | `running`, `waiting` (and for what), `ended` (and its status), `failed` (and why) |
| its session | the SSH session or the console it answers, or none |

**Who a program is, is in its entry, not in the session.** Today `may` in `src/ksys.cho` asks the session's role
(`k[4179]`) and the grants the shell loaded for the line just typed. A program that stays outlives the line, and
is entered while another key's session is being served. So before the kernel enters a program it puts the
entry's who, role and grants where `may` and the record read them, and takes them back after. A program never
acts as whoever happens to be typing.

**Grants are lent for a time.** The entry does not keep a copy made at the start for ever. Its grants are read
again from `KEYS.TXT` when the file changes and when the day changes ([`clock.md`](clock.md)): a grant that was
narrowed is narrower for the running program at its next call, and a grant whose day is over grants nothing, and
the program's next call that needs it is refused with 13 as any is. What happens to a program whose key is no
longer in the file is section 11.

**Two ways to run a line.**

- *As today*: a line that names a program runs it, and that session takes no other line until the program has
  ended. What is new is that everything else goes on: the console, another program, the network. If the session
  closes, the program is ended (why: `session`).
- *`start <line>`*: the program is started and the answer comes at once, with its number. It has no input (its
  first read is the end) and its output is kept, the last 4,096 bytes of it, in its block, where `said <n>` reads
  it until the block is used again.

**The commands.** Each answers in the form of cancho-tools, so that an agent reads them as it reads `hash`.

`start --memory 8388608 db serve 5432`, by an agent's key:

```
{"ok":true,"command":"start","schema":"start.v1","data":{"program":3,"line":"db serve 5432","by":"key:da8e761b716a82a8","role":"agent","memory":8388608,"stack":262144,"grants":{"read":["DATA"],"write":["DATA"],"listen":[5432]}}}
```

and when there is no room, before anything runs:

```
{"ok":false,"command":"start","schema":"start.v1","error":{"code":"NO_ROOM","rule":"programs.memory","message":"8388608 bytes were asked for and the largest free block is 6291456","hint":"ask for less with --memory, or end a program: `programs` lists them","asked":8388608,"largest":6291456}}
```

`programs`:

```
{"type":"program","program":2,"line":"hash BIG.BIN","by":"console","role":"owner","state":"running","for_ms":412,"memory":{"block":1048576,"used":70656,"stack":5568},"holds":{"files":1,"directories":1,"draft":false,"listens":[],"connections":0},"session":"console"}
{"type":"program","program":3,"line":"db serve 5432","by":"key:da8e761b716a82a8","role":"agent","state":"waiting","waits":{"for":"connections","until_ms":655},"for_ms":86120,"memory":{"block":8388608,"used":2228224,"stack":14208},"holds":{"files":2,"directories":1,"draft":false,"listens":[5432],"connections":4},"session":null}
{"type":"end","ok":true,"command":"programs","schema":"programs.v1","programs":2,"memory":{"all":33554432,"free":24117248,"largest":16777216}}
```

An agent's key is shown the programs it started and no others; an owner and the console see all.

`end 3`:

```
{"ok":true,"command":"end","schema":"end.v1","data":{"program":3,"changed":true,"was":"waiting","closed":{"files":2,"directories":1,"draft":false,"listens":[5432],"connections":4},"memory":8388608}}
```

The same line again, since a retried command that had landed must say so and change nothing:

```
{"ok":true,"command":"end","schema":"end.v1","data":{"program":3,"changed":false,"was":"ended","why":"asked","by":"key:da8e761b716a82a8"}}
```

and by a key that neither started it nor is an owner's:

```
{"ok":false,"command":"end","schema":"end.v1","error":{"code":"DENIED","rule":"programs.not-yours","message":"program 3 was started by another key","hint":"the key that started it, an owner's key or the console can end it","program":3}}
```

A number that was never given answers `programs.no-such`. `end` runs no code of the program: it is not asked to
stop and cannot refuse. Section 5 is why nothing needs it to.

**A program that failed**, to the one who ran it, on the session it was run from, in place of its last line:

```
{"ok":false,"command":"fail","schema":"program.v1","error":{"code":"FAILED","rule":"programs.trap","message":"the program trapped: a check of the language failed","hint":"the board goes on; nothing the program had open is left open","program":7,"why":"trap","at":"0x400a51c4","memory":{"block":1048576,"used":65536,"stack":1424}}}
```

`rule` is `programs.trap`, `programs.memory` (it asked for more than its block: `used` and `block` say how much)
or `programs.stack`. `at` is the address the trap was reached from; the build keeps the map that turns it into a
function's name.

**The record.** `start`, `end` and a failure each add a line to `LOG.TXT`, in the format it has
([`permissions.md`](permissions.md)): who, role, the action, the program's word as the target, why in the next
field, its number where a version's is.

```
41 86120 key:da8e761b716a82a8 agent start db - 3 8388608 - 77c1...
58 91377 key:da8e761b716a82a8 agent end db asked 3 8388608 - 0b9e...
59 91502 console owner fail fail trap 7 1048576 - 5d20...
```

A program run the first way that ends by itself leaves no line, as today: what it changed has its own lines. With
no disk there is no record and the answers are the same. `tests/checklog.py` must learn the three words before
the kernel writes them.

## 5. A trap ends the program alone

### The argument

A trap in a program switches to the kernel, which finds the program failed. No code of the program runs again:
nothing is unwound, no `defer` of its runs, its regions are not given back, its linear values are never closed.
That is sound only if nothing the program had is still held anywhere, and nothing the kernel has is half changed.
Everything a program can own or hold, and why none of it is left:

| what | where it is | why nothing survives |
|---|---|---|
| its stack | at the top of its block | the block is the kernel's again; the check of the stack's end (section 3) is what keeps it inside |
| what it boxed (`Heap`) | its block | while a program runs the allocator has only its block (section 6); the lists of free pieces are in the block too |
| its regions | chunks of 64 KiB from the same allocator | the same |
| its arguments | its block | moved there (section 2) |
| a `static` | the image, not written | the compiler writes every `static` as constant (cancho `docs/unsafe-and-global-state.md`): a program has no state outside its block |
| the capabilities of the block | words that mean something only while the block is open | the program is never entered again, so nothing asks with them |
| open files, directories, listings | numbers into its own table of handles, in the kernel | the kernel clears the table, as `hosted` clears `h` before every program today |
| the draft of `src/ksys.cho` | a mark and a length in that table; its bytes wait in `stage` | the mark is cleared. A draft that was never renamed was never on the disk ([`tools.md`](tools.md)) |
| the lock it took | a handle and nothing else | cleared with the table |
| its input over SSH | `stage`, counted in `k[4268]`.. | the counts are set to none |
| a port it listens on, its connections, its poller (#51, #54) | the kernel's tables of the network, each entry marked with the program's number | the kernel closes each: the other end is sent a reset, not left waiting |
| what it printed and is not sent yet | the kernel's queue of the session | it is the kernel's and is sent; the failure follows it |
| what it was lent of the kernel (`con`, `k`, `h`, ...) | the kernel | touched only inside a function of `ksys`, and a trap there is not this case (below) |
| a pointer of the kernel's into the program's memory | none | a function of `ksys` takes a program's bytes as a borrow for the call (`&p [byte]`), and the kernel's state is whole numbers: the checker refuses to keep the borrow |
| the watchdog's count | the watchdog | stopped when the program is left |

What can be left is what the program **finished** before it failed. A function of `ksys` runs whole or not at
all, so a file is the old one or the new one, with its version and its line in the record, and never part of
each. A program that meant two changes and trapped between them has made one. That is what a board that loses
power leaves too, and the record says who and when.

"Nothing of the program is left" then rests on four statements, each the compiler's or one function's:

1. A program writes only inside its block. The language gives it no address: its memory comes from an allocator
   that has only the block, and its stack is checked.
2. The kernel keeps no reference into the block (the borrow checker, on `ksys`'s signatures).
3. Everything else a program holds is a number in a table, and one function of the kernel empties a program's
   tables. It is the only way a program is ended: by itself, by `end`, by a failure, by its session closing.
4. A program is left only between two answers of the kernel, never inside one.

### The case that must still stop the kernel

- **A trap in the kernel's own code while it answers a program**: a function of `ksys`, or anything it calls. Its
  state may be half changed: a sector written and its table not, a line of the record half made. `cancho_trap`
  finds `@cancho_sys_on` at 2 and does what it does today.
- **A trap with nothing lent** (`@cancho_sys_on` at 0): the shell's own code.
- **Any exception the processor takes** (an abort, an undefined instruction that is not the trap's): through the
  vector to `main`, as today, whoever was running. In cancho code that passed the checker this is the compiler's
  mistake or the hardware's, and neither is a program's failure. `board/boot.S` does not change.

The two are told apart by one word, `@cancho_sys_on`, which only code the compiler writes changes, in four
places: 1 where a program is entered, 0 where it is left, 2 before a function of the module is called and 1
after. A check the compiler's function makes itself before asking the kernel (a path outside the `Fs` it was
opened through, a name that is not one component, too little stack left) is made at 1: it is the program's fault
and ends the program. So a path with `..` in it, which today a tool must look for because the language traps on
it, stops being a way to reset the board.

A function of `ksys` must therefore never trap on what a program gives it: a handle that is not open, a length
that is too large, a name of any bytes. That is already the rule (`held`, `may`, and `inet` and `fat` trap on no
bytes at all). It becomes the line between a program's failure and the kernel's, and wants a test of its own.

## 6. Memory

**Where.** Not the kernel's heap. A range of RAM beside it, cut in `board/link.ld` as `__stage` is and held by
`main` as a capability whose bound is exactly that range, so that `./authority.sh` shows it. The kernel's
allocator never reaches it and a program's never reaches outside its block.

**A block.** One run of bytes, a power of two in size, 64 KiB at least:

```
low   the compiler's: state, saved registers, allocator, arguments         168 + 416 + 16,384 bytes, and the state's words
      the kernel's: the program's last 4,096 bytes of output
      boxes and regions, growing up
      (unused)
high  the stack, growing down from the top                                 its size fixed when the program starts
```

**The allocator.** `compiler/runtime/bare.ll` keeps three globals (`cancho_bare_next`, `cancho_bare_free`, the
forty-eight lists of `cancho_bare_bins`) and reads its limits from two symbols of the link. They become one
record, fifty-two words (416 bytes), reached through one pointer, `@cancho_bare_arena`. The kernel's record is a
global, as now. A program's is in its block, with the block's ends as its limits. The pointer is the program's
while it runs (`@cancho_sys_on` at 1) and the kernel's otherwise; the compiler's functions change it around every
call of the module (section 3). So a region the kernel opens while answering takes a chunk of the kernel's
memory and has given it back before the answer: no chunk of the kernel's is ever in a program's lists, or a
program's in the kernel's.

**How its size is chosen.** By the one who starts it: `--memory` to `start`, or the size the table of programs
(#49) gives its word, or 1 MB. The stack is 256 KiB of it unless the table says otherwise. Both are in the answer
of `start` and in `programs`. What was measured (section 8): the deepest call of seven tools used 10,896 bytes of
stack, the kernel's own frames included.

**No room is told before the program runs.** The kernel cuts blocks out of the range itself and knows what is
free, so `start` refuses with the number asked and the largest free (section 4). It never asks the kernel's heap
for a program's block, where no memory left is a trap.

**When a block is exhausted.** The allocator's trap, with `@cancho_sys_on` at 1 and why 2: the program fails with
`programs.memory`, the block is free again whole, and the one who ran it is told how much it had. A hundred
failing programs take and give back the same block.

**What belongs to #57 and is not decided here:** how large the range is and how much of a Pi 4's memory the
kernel maps; `mem` saying what each program has; a better allocator inside a block than lists of powers of two
that are never split or joined; a database's cache of pages.

## 7. What changes in the kernel

No code is written for this document. For judging its size:

- `hosted` takes a program's number and is called for a start and for every turn; the block is the new statement.
- The shell's loop (`shell`, `getc`) gains one answer of `getc` ("a program can go on") and enters that program.
  `getc` no longer sleeps (`wfi`) while a program can go on.
- A table of programs in the kernel's state, and a table of handles for each (`ksys.handle_room()` whole numbers:
  2,619 with eight handles).
- `src/ksys.cho`: "later" from `key`; who a program is, taken from its entry. One function that empties a
  program's tables.
- Commands `start`, `programs`, `end`, `said`; three words in `src/record.cho` and `tests/checklog.py`.
- `fail` in `src/programs.cho` gains `deep` (it calls itself until the stack ends), `draft` (a draft, then a trap)
  and `wait`.

## 8. Measured, and not

**Measured (2026-11-27).**

- *A saved context is 168 bytes*: twenty-one words, counted from the calling rules of the processor (x19 to x28,
  x29, x30, the stack pointer, d8 to d15). `tests/switch_probe.S` saves and loads exactly these and runs.
- *A switch is 25 instructions.* The probe in `qemu-system-aarch64` 11.1.3 as `virt`, with `-icount shift=0`,
  where the counter moves one for every sixteen instructions: 125,000 for a million turns of an empty loop of two
  instructions (2,000,000 instructions), 3,687,500 for a million turns with a switch there and a switch back
  (59,000,000: 25 for each switch, 9 for the two calls and the loop). This counts instructions. It is not time.
- *On one real processor*, an Apple M4 Max, the same twenty-five instructions in a program of macOS: 11.1 to
  11.5 ns for a switch there and back, five runs of a hundred million. Not a Pi's processor, and not tried on one.
- *The stack the tools use.* A build of the kernel's tree as it stood that day (it called itself 0.0.49), in
  QEMU as `virt`, on a FAT16 volume macOS made with a file of 297,716 bytes and a directory of ten names. After
  each command the stack's memory (520,192 bytes, from 4 KiB to the image) was read out with QEMU's `pmemsave`,
  and the lowest word that had changed, or was not zero, was taken as how deep the stack had been:

  | command | bytes of stack, the kernel's own frames included |
  |---|---|
  | the shell at its prompt | 2,112 |
  | `tell`, `about` | 1,448 |
  | `hash` (21 bytes; 297,716 bytes) | 5,568; 5,544 |
  | `seek` | 5,888 |
  | `list --long` | 6,736 |
  | `peek` | 7,456 |
  | `move` | 10,144 |
  | `replace`, with a file written | 10,896 |

  A word the stack wrote zero into, in memory that was zero, is not seen: the numbers can be a little low, not
  high. `write` was not measured to its end.
- *Frames.* In that image, 583 functions; the largest takes 3,040 bytes of stack, the median 80.
- *Trap sites.* 8,322 `udf` in that image, and no call of `cancho_trap`.
- *What moves into a block*: 16,384 bytes of arguments, 416 of allocator, 168 of registers.

**Not measured, and wanted before the code that depends on it.**

- A switch on a Raspberry Pi 4.
- What the check of the stack's end costs: `hash` of 300,000 bytes with and without it, in instructions.
- The stack cancho-db's engine uses, on a system, under its own tests: it decides the default for a program that
  is not a tool.
- The longest single answer of `ksys` (a file of 2 MB written and read back by `files.store_as`): it is the
  least the bound on the shell's answer can be.
- One pass of the shell's loop with the network up and nothing to do: what every turn of a program pays.
- The margin of stack the kernel's own answers need (step 1 of section 3). 10,896 bytes is the whole of the
  deepest chain seen, program and kernel together, so it is under that.

## 9. An order of slices

Each boots in QEMU in CI. The first two are the compiler's and change nothing a program can see.

1. **The trap is a call, and the allocator is behind one pointer** (cancho). `cancho_trap` not written in line for
   this target; `bare.ll`'s record. *Shows:* the compiler's own gate; this kernel built with it passes every test
   it passes now; the image's size before and after. *Judged by:* the same judges as today (`fsck.fat`, OpenSSH,
   `checklog.py`), finding nothing new.
2. **A block that is left by a trap** (cancho, then here). The statement with `runs`, the switch, the check of
   the stack; a program runs on its own stack in its own block and still runs to its end. *Shows:* `fail trap`,
   `fail memory` and `fail deep` over SSH each answer the failure, and the same session then lists a directory;
   the board does not reset; a hundred of each in one boot and the free memory is what it was; `fail trap` in the
   kernel's own code (`crash`) still resets. `fail draft`, which makes a draft and traps before the rename, leaves
   no file and no name with `lexsys` in it. *Judged by:* OpenSSH's client for the session, `tests/checklog.py` for
   the three lines, `fsck.fat -n` for the volume, and the seven tools' answers still the same bytes as on another
   machine.
3. **A program that waits** (here). "Later", the table of programs, `start`, `programs`, `end`, `said`.
   `fail wait` waits for a key that never comes. *Shows:* it is listed as waiting while `ls` answers at the
   console and over SSH; `end` ends it, and the same `end` again says so and changes nothing; an agent's key is
   refused another key's program. *Judged by:* OpenSSH; `./agents.sh` and `./keys.sh` with the new lines.
4. **The kernel's turn at any call** (cancho for the word, here for the slice). *Shows:* two `hash` of 16 MB
   files started together both end with the SHA-256 `sha256sum` gives, and while they run a third session's
   `about` is answered within a bound; the bound is measured from the other machine, a hundred times, and written
   here. `fail spin` is still ended by the watchdog, on a real board.
5. **A program that serves** (with #54). A program in `src/programs.cho` that answers what it is sent, on a port.
   *Shows:* twenty connections of Linux's `nc` at once, each given back its bytes, while files are listed over
   SSH and a second program runs; the shell's bound measured again. `end` of it: every `nc` sees its connection
   closed, and `tcpdump` on the other machine sees the resets. *Judged by:* Linux's `nc` and TCP, OpenSSH.
6. **Who a program is** (here). The entry's who and grants in `may` and in the record; grants read again while a
   program runs. *Shows:* a program started by an agent writes under its grant while an owner's session is being
   served, and the record's line names the agent; the grant taken out of `KEYS.TXT` and the program's next write
   is refused with 13. *Judged by:* `./agents.sh`, `checklog.py`.
7. **cancho-db's engine** is the epic's own end, not a slice of this.

The epic lists #52 before #53. Slice 2 is #53's and comes first here because a wait is the same leaving as a
trap, with a way back: built in this order, nothing is built twice.

## 10. What this is not

- **Not processes.** No address space for each program, no `fork`, no user a program runs as, no signal a
  program can catch or refuse. A program is an entry; `end` is the kernel emptying it.
- **Not a scheduler that interrupts.** A program is left only when it asks the kernel for something. One that
  computes and asks for nothing is ended by the watchdog, with the board.
- **Not protection by the processor.** What keeps a program inside its block is the compiler that built it into
  this image. A program compiled elsewhere and loaded is not this design, and neither is a compiler that is
  wrong.
- **Not threads.** One program has one stack. cancho-db's engine needs no more.
- **Not two SSH sessions at once.** `src/sshd.cho` holds one connection's state. A program that serves and one
  session beside it is what #52 asks for.
- **Not a program started by a program.** Only a line starts one.
- **Not undoing what a failed program finished.** What it wrote is a version and a line in the record, and is
  undone as any write is.
- **Not a way to load a new program** without building an image, or to move a servo.

## 11. Open, for the owner

1. **The words of the statement** (`runs (mem, at, size)`), and the rule that the body names nothing of the
   function around it but whole numbers copied at the start. It is the one new thing in the language.
2. **The stack's end: a check at every function, or a page that is not mapped.** The check makes an overrun the
   program's failure and is what statement 1 of section 5 rests on; its cost is not measured. The page costs
   nothing while running and needs a table of 4 KiB pages for each program's stack (the kernel has eight tables
   in all today), and an overrun then goes through the vector and resets the board. Proposed: the check.
3. **The order**: #53's half first (section 9).
4. **A program whose key is taken out of `KEYS.TXT` while it runs**: ended at once (why: `revoked`), or left
   running with nothing granted. Proposed: ended, with a line in the record.
5. **May an agent `start` a program that stays**, or only an owner. Proposed: an agent may, programs its row and
   grants cover, and sees and ends only its own.
6. **The slice** after which the kernel takes its turn (10 ms is the tick it has), and whether a program's row
   could promise it asks often enough to do without the watchdog.
7. **What is kept of a program that has no session**: 4,096 bytes of its output, proposed; or a file.
8. **The memory programs live in**: a range of its own beside the heap, held as a capability (proposed), or
   boxes of the kernel's heap. And the default sizes: 1 MB and a stack of 256 KiB.
9. **The second backend** (cancho#840): the switch and the check written there when it reaches this target, or
   this target kept on LLVM until then.
