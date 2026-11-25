#!/bin/sh
# The kernel's network link against a stack that is not ours: Linux's own SLIP driver and the system's `ping`.
# Linux only, and it needs root (a network interface is made): this is for CI, where sim/netpeer.cho's packets
# are checked by the kernel that everyone else's packets go through.
#   sudo ./ping.sh            boots build/kernel8.img in QEMU with its second serial port on a pty, types
#                             `net up`, attaches the pty as sl0 (10.0.0.1, the kernel is 10.0.0.2), and pings
# Exit 0 if every ping was answered and a UDP datagram to port 7 came back.
set -u
cd "$(dirname "$0")"
MACHINE=${MACHINE:-raspi3b}
mkdir -p build
rm -f build/uart.in build/ping-uart.out build/qemu.err
mkfifo build/uart.in
qemu-system-aarch64 -M "$MACHINE" -kernel build/kernel8.img -serial stdio -serial pty -display none -monitor none \
    < build/uart.in > build/ping-uart.out 2> build/qemu.err &
QEMU=$!
exec 3> build/uart.in
sleep 2
PTY=$(grep -o '/dev/pts/[0-9]*' build/ping-uart.out build/qemu.err | head -1 | sed 's/^[^:]*://')
status=1
if [ -z "$PTY" ]; then
    echo "ping.sh: QEMU did not say which pty the second serial port is" >&2
else
    printf 'net up\r' >&3
    modprobe slip 2>/dev/null
    slattach -L -p slip -s 115200 "$PTY" &
    SLIP=$!
    sleep 1
    ip addr add 10.0.0.1 peer 10.0.0.2 dev sl0 && ip link set sl0 up mtu 1006
    ping -c 5 -i 0.3 -W 2 10.0.0.2 && status=0
    # a datagram to the echo port, and what comes back
    back=$(printf 'cancho-os over udp' | timeout 3 nc -u -w 1 10.0.0.2 7)
    echo "udp echo: '$back'"
    [ "$back" = "cancho-os over udp" ] || status=1
    printf 'net\r' >&3
    sleep 1
    kill $SLIP 2>/dev/null
fi
exec 3>&-
kill $QEMU 2>/dev/null
wait $QEMU 2>/dev/null
rm -f build/uart.in
tr -d '\r' < build/ping-uart.out
exit $status
