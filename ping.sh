#!/bin/sh
# The kernel's network link against a stack that is not ours: Linux's own SLIP driver and the system's `ping`.
# Linux only, and it needs root (a network interface is made): this is for CI, where sim/netpeer.cho's packets
# are checked by the kernel that everyone else's packets go through.
#   sudo ./ping.sh            boots build/kernel8.img in QEMU with its second serial port on a pty, types
#                             `net up`, attaches the pty as sl0 (10.0.0.1, the kernel is 10.0.0.2), and pings
#   sudo MACHINE=virt ./ping.sh   the same over Ethernet: QEMU's virt machine, its network card on a tap interface
# Exit 0 if every ping was answered and a UDP datagram to port 7 came back.
set -u
cd "$(dirname "$0")"
MACHINE=${MACHINE:-raspi3b}
mkdir -p build
rm -f build/uart.in build/ping-uart.out build/qemu.err
mkfifo build/uart.in
if [ "$MACHINE" = virt ]; then
    # the network card, on a tap interface of this machine: Ethernet frames, so ARP comes first
    # (a route to that one address, not to a /24: the machine's own network may be 10.0.0.x too, and the
    # ping would leave by it)
    ip tuntap add dev tap0 mode tap && ip addr add 10.0.0.1 peer 10.0.0.2 dev tap0 && ip link set tap0 up
    qemu-system-aarch64 -M virt -cpu cortex-a57 -m 1G -global virtio-mmio.force-legacy=false \
        -netdev tap,id=n0,ifname=tap0,script=no,downscript=no -device virtio-net-device,netdev=n0 \
        -kernel build/kernel-virt.elf -serial stdio -display none -monitor none \
        < build/uart.in > build/ping-uart.out 2> build/qemu.err &
else
    qemu-system-aarch64 -M "$MACHINE" -kernel build/kernel8.img -serial stdio -serial pty -display none -monitor none \
        < build/uart.in > build/ping-uart.out 2> build/qemu.err &
fi
QEMU=$!
exec 3> build/uart.in
sleep 2
status=1
SLIP=
ready=1
if [ "$MACHINE" != virt ]; then
    PTY=$(grep -o '/dev/pts/[0-9]*' build/ping-uart.out build/qemu.err | head -1 | sed 's/^[^:]*://')
    if [ -z "$PTY" ]; then
        echo "ping.sh: QEMU did not say which pty the second serial port is" >&2
        ready=
    fi
fi
if [ -n "$ready" ]; then
    printf 'net up\r' >&3
    if [ "$MACHINE" != virt ]; then
        modprobe slip 2>/dev/null
        slattach -L -p slip -s 115200 "$PTY" &
        SLIP=$!
        sleep 1
        ip addr add 10.0.0.1 peer 10.0.0.2 dev sl0 && ip link set sl0 up mtu 1006
    fi
    sleep 1
    if [ -n "${TRACE:-}" ] && [ "$MACHINE" = virt ]; then
        # what is on the wire, both ways, for when the answer is not what was expected
        tcpdump -i tap0 -n -e -XX -c 12 > build/trace.txt 2>&1 &
        sleep 1
    fi
    ping -c 5 -i 0.3 -W 2 10.0.0.2 && status=0
    # a datagram to the echo port, and what comes back
    back=$(printf 'cancho-os over udp' | timeout 3 nc -u -w 1 10.0.0.2 7)
    echo "udp echo: '$back'"
    [ "$back" = "cancho-os over udp" ] || status=1
    if [ "$MACHINE" = virt ]; then
        # what this machine's own ARP table learned from the kernel's answer
        ip neigh show dev tap0
    fi
    printf 'net\r' >&3
    sleep 1
    [ -n "$SLIP" ] && kill $SLIP 2>/dev/null
fi
exec 3>&-
kill $QEMU 2>/dev/null
wait $QEMU 2>/dev/null
[ "$MACHINE" = virt ] && ip link del tap0 2>/dev/null
rm -f build/uart.in
tr -d '\r' < build/ping-uart.out
if [ -f build/trace.txt ]; then cat build/trace.txt; fi
exit $status
