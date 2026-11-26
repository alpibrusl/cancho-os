# The servo bus, through another machine

> **Status: built**, in QEMU against a made-up bus. 0.0.30. A way to read real arms during development,
> not the way a controller will hold them: see "What it is not".

The arms' adapters are USB, and the kernel has no USB. Until it does, or until the bus is wired to the
board's own pins, the bus can be another machine's: one that has the adapters, and a cable to this one.

## How

- **`servo via <address> <port>`**, at the serial console. From then on every servo packet the kernel
  would have put on its own bus goes to that address as one UDP datagram, and the servo's answer comes
  back as one. `servo via off` undoes it. `net` says which it is.
- Nothing above the bus changes: `servo scan`, `servo pos`, `arm pose` and `arm check` are the code that
  ran on the emulated bus. The one function they all send through, `transact`, takes the other path.
- **`board/busbridge.py`** runs on the machine with the bus. A datagram in is written to the serial
  port; what comes back within 20 ms is the datagram out.

## It only reads

The kernel cannot build a packet that moves a servo: `feetech.cho` has a ping and two reads, and
`feetech_write.cho` is not here. But the bridge listens on a network, and a network has other machines.
So the bridge passes on **only a ping, a read and a read of several**, each one whole packet with a right
checksum, and drops and counts everything else. Whoever reaches its port can ask where the arm is. Nobody
can move it through there. It should be bound to the cable's address, not to every address.

## Measured

In QEMU's `virt`, the bridge on the same machine with `--fake` (six servos made up in Python, a second
implementation of the protocol):

| what | result |
|---|---|
| `servo via 10.0.0.1 6000`, `servo scan` | servos 1 to 6 present, 7 and 8 "no answer" |
| `servo pos` | 1300, 1600, 1900, 2200, 2500, 2800: the positions the bridge made up |
| `arm pose`, `arm check 5 14 33 -41 44` | a pose, and "approved ... nothing was sent" |
| to the bridge: a write, a registered write, a write to several, a wrong checksum, two packets in one | dropped, five of five; a ping and a read answered |

## What it is not

- **Not how the controller will hold the arm.** Another operating system is in the path, and so is a
  network. A late or lost datagram is a servo that "did not answer". The controller that guards the arm
  must own the bus: through USB, or the board's own pins.
- **Not private.** The datagrams are not encrypted or signed. On a cable between two boards that is two
  machines; it is not for a shared network.
- **Not faster than the bus.** Each packet waits for the servo on the other machine and then crosses
  the cable: about 20 ms more for one that does not answer.
- **Nothing moves.** That is unchanged, and waits for the safety core's side that sends.
