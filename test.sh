#!/bin/sh
# Boot build/kernel8.img in QEMU, type the lines given as arguments (one per second),
# and print what the UART said. Portable: no `timeout` (macOS has none).
#   ./test.sh about 'echo ci'            QEMU raspi3b
#   MACHINE=raspi4b ./test.sh about      the same image as a Pi 4 (QEMU >= 9)
#   MACHINE=virt ./test.sh about         QEMU's virt machine (build/kernel-virt.elf), with a network card
#   MACHINE=virt UDP=hello ./test.sh 'net up' net     and a datagram sent to the kernel's echo port from here
#   MACHINE=virt TCP=hello ./test.sh 'net up' net     the same over a TCP connection (the host's stack opens it)
#   MACHINE=virt TCPFILE=path ./test.sh 'net up' net  a whole file over one, and whether it came back the same
#   SERVOS=1 ./test.sh 'servo scan'      with six simulated servos on the board's second serial
#                                        port (build/servos, from sim/servos.cho: see build.sh)
#   NET=1 ./test.sh 'net up' net         with the network peer on that port instead (build/netpeer, from
#                                        sim/netpeer.cho); what the peer saw is printed after the UART
set -u
cd "$(dirname "$0")"
MACHINE=${MACHINE:-raspi3b}
mkdir -p build
rm -f build/uart.in build/uart.out build/bus.in build/bus.out build/peer.txt
mkfifo build/uart.in
BUS="-serial null"
SIM=
if [ -n "${SERVOS:-}" ]; then
    # QEMU reads the port's input from bus.in and writes its output to bus.out
    mkfifo build/bus.in build/bus.out
    ./build/servos < build/bus.out > build/bus.in &
    SIM=$!
    BUS="-serial pipe:build/bus"
elif [ -n "${NET:-}" ]; then
    mkfifo build/bus.in build/bus.out
    # the peer speaks once the kernel has booted: what it sent earlier, the bus's set-up would throw away
    (sleep 2; exec ./build/netpeer) < build/bus.out > build/bus.in 2> build/peer.txt &
    SIM=$!
    BUS="-serial pipe:build/bus"
fi
KERNEL=build/kernel8.img
if [ "$MACHINE" = virt ]; then
    # QEMU's own board: one serial port (no servo bus), RAM at 1 GB. A Cortex-A57 is how the kernel knows it.
    # A network card on QEMU's own user-mode network: the host is 10.0.0.1, the kernel 10.0.0.2, and a
    # datagram sent to this machine's port 5507 reaches the kernel's port 7, and so does a connection.
    MACHINE="virt -cpu cortex-a57 -m 1G -global virtio-mmio.force-legacy=false -netdev user,id=n0,net=10.0.0.0/24,host=10.0.0.1,hostfwd=udp:127.0.0.1:5507-10.0.0.2:7,hostfwd=tcp:127.0.0.1:5507-10.0.0.2:7 -device virtio-net-device,netdev=n0 ${DUMP:+-object filter-dump,id=f0,netdev=n0,file=$DUMP}"
    KERNEL=build/kernel-virt.elf
    BUS=
fi
qemu-system-aarch64 -M $MACHINE -kernel $KERNEL -serial stdio $BUS -display none -monitor none \
    < build/uart.in > build/uart.out 2>&1 &
QEMU=$!
exec 3> build/uart.in
sleep 2
first=1
for line in "$@"; do
    printf '%s\r' "$line" >&3
    sleep 1
    if [ -n "$first" ] && [ -n "${UDP:-}" ]; then
        # after the first line (`net up`): a datagram from this machine to the kernel's echo port
        printf "udp echo: '%s'\n" "$(printf '%s' "$UDP" | nc -u -w 1 127.0.0.1 5507)" > build/peer.txt
    fi
    if [ -n "$first" ] && [ -n "${TCP:-}" ]; then
        printf "tcp echo: '%s'\n" "$(printf '%s' "$TCP" | nc -w 5 127.0.0.1 5507)" >> build/peer.txt
    fi
    if [ -n "$first" ] && [ -n "${TCPFILE:-}" ]; then
        nc -w 20 127.0.0.1 5507 < "$TCPFILE" > build/tcp.back
        if cmp -s "$TCPFILE" build/tcp.back; then
            echo "tcp echo: $(wc -c < build/tcp.back | tr -d ' ') bytes came back the same" >> build/peer.txt
        else
            echo "tcp echo: $(wc -c < build/tcp.back | tr -d ' ') bytes came back, NOT what was sent" >> build/peer.txt
        fi
    fi
    first=
done
exec 3>&-
kill $QEMU 2>/dev/null
wait $QEMU 2>/dev/null
[ -n "$SIM" ] && { kill $SIM 2>/dev/null; wait $SIM 2>/dev/null; }
rm -f build/uart.in build/bus.in build/bus.out
tr -d '\r' < build/uart.out
if [ -f build/peer.txt ]; then cat build/peer.txt; fi
