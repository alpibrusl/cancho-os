#!/usr/bin/env python3
"""Pass servo packets between cancho-os and a servo bus on this machine (docs/netbus.md).

    python3 board/busbridge.py --bind 10.42.0.1 6000 /dev/ttyACM0
    python3 board/busbridge.py --bind 127.0.0.1 6000 --fake      # no bus: six servos made up, for tests

One datagram in is one packet for the bus; one datagram back is what the servo said (nothing, if none did).
ONLY PACKETS THAT READ ARE PASSED ON: a ping (1), a read (2), a read of several at once (0x82). Anything
else, and anything whose checksum is wrong, is dropped and counted. Whoever can reach this port can ask
where the arm is; nobody can move it through here. Bind it to the cable's address, not to every address.
Needs pyserial for a real bus. Not part of the kernel: a tool for a machine that has the bus.
"""
import socket
import sys
import time

READS = (0x01, 0x02, 0x82)


def checksum(body):
    return (~sum(body)) & 0xFF


def allowed(p):
    """Is `p` one whole packet that only reads?"""
    if len(p) < 6 or p[0] != 0xFF or p[1] != 0xFF or p[3] != len(p) - 4:
        return False
    return p[4] in READS and checksum(p[2:-1]) == p[-1]


def fake(p):
    """Six servos, numbered 1 to 6, each at a position of its own. A second implementation of the
    protocol, for tests of the kernel's."""
    ident, inst = p[2], p[4]
    if not 1 <= ident <= 6:
        return b""
    if inst == 0x01:
        body = bytes([ident, 2, 0])
    elif inst == 0x02 and len(p) == 8:
        position = 1000 + 300 * ident
        memory = {56: position & 0xFF, 57: position >> 8}
        data = bytes(memory.get(p[5] + i, 0) for i in range(p[6]))
        body = bytes([ident, 2 + len(data), 0]) + data
    else:
        return b""
    return b"\xff\xff" + body + bytes([checksum(body)])


def main():
    args = sys.argv[1:]
    bind = "127.0.0.1"
    if args and args[0] == "--bind":
        bind = args[1]
        args = args[2:]
    port = int(args[0])
    bus = None
    if args[1] != "--fake":
        import serial
        bus = serial.Serial(args[1], 1000000, timeout=0.003)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((bind, port))
    passed = dropped = 0
    print(f"busbridge: {bind} port {port}, {'a made-up bus' if bus is None else args[1]}; reads only", flush=True)
    while True:
        p, who = sock.recvfrom(256)
        if not allowed(p):
            dropped += 1
            print(f"busbridge: dropped a packet that does not read, or is not whole ({dropped} so far)", flush=True)
            continue
        passed += 1
        if bus is None:
            answer = fake(p)
        else:
            bus.reset_input_buffer()
            bus.write(p)
            bus.flush()
            answer = b""
            end = time.time() + 0.02
            quiet = 0
            while time.time() < end and quiet < 2:
                more = bus.read(64)
                if more:
                    answer += more
                    quiet = 0
                elif answer:
                    quiet += 1
            # an adapter that hears its own sending gives the packet back first: that is not the servo's answer
            if answer.startswith(p):
                answer = answer[len(p):]
        sock.sendto(answer, who)


if __name__ == "__main__":
    main()
