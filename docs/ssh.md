# SSH

> **Status: design.** What was measured is at the end.

## What is wanted

The kernel's shell over a connection that is encrypted and asks who is there. Port 23 (docs/network.md,
section 8) gives the shell to whoever reaches it, in the clear; it was built to be replaced by this.

## What is used

[cancho-ssh](https://github.com/alpibrusl/cancho-ssh): an SSH server in cancho that owns no socket, clock,
file or heap. It is given bytes and gives bytes back, which is the shape of everything in `src/inet.cho`.
It is not copied here: the build takes its eight files from a checkout pinned to a commit, as it takes the
compiler. Its own README says nobody but its author has read it, and that it should not guard anything
yet. That holds here too.

## The shape

- **`net ssh on`, at the serial console only**, opens port 22. `net ssh off` closes it. One connection
  at a time has the shell, as on port 23, and the two are not open together: `inet` has one port that
  is the caller's.
- **`ssh_step` in `src/network.cho`** is the loop cancho-ssh's own `docs/cancho-os.md` describes, between
  `tcp_read`/`tcp_write` and the two things the shell already had: the line being typed and the queue of
  what it printed. It holds no hardware. Above it nothing changed: the same commands, the same `putc`.
- **Who may log in is built into the image.** There is no file to read. `AUTHORIZED=key.pub ./build.sh`
  writes the key's 32 bytes into a generated source file; with none, the port can be opened and nobody
  can log in, and the kernel says so. Only `ssh-ed25519` keys, since that is what cancho-ssh checks.
- **The host key is drawn when the port is first opened**, from the board's generator, and its public
  half is printed on the serial console in the form `known_hosts` wants. There is nowhere to keep it:
  after a restart it is another key, and a client that remembered the old one will object. A kernel
  with storage would keep it; this one has none yet.
- **No generator, no SSH.** With guessable numbers the keys of a session are guessable and what was
  said can be read afterwards. On a board whose generator has not been started the port stays closed.
  Each connection takes 32 bytes from the pool of random words, and the host key 32 once.
- **A terminal is the client's.** If the client asked for one, it sends each key as typed and echoes
  nothing, so the kernel echoes, and understands backspace, Ctrl-C and Ctrl-D. `ssh host command` runs
  the one command and ends with it.

## What it does not do

- **No passwords, no forwarding, no file transfer:** cancho-ssh has none.
- **No names.** Any user name is taken; the key decides.
- **The window is small and the handshake slow:** a connection's inbox is 256 bytes, and a client's
  first message is about 1,500.
