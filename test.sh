#!/bin/sh
# Boot build/kernel8.img in QEMU, type the lines given as arguments (one per second),
# and print what the UART said. Portable: no `timeout` (macOS has none).
#   ./test.sh about 'echo ci'            QEMU raspi3b
#   MACHINE=raspi4b ./test.sh about      the same image as a Pi 4 (QEMU >= 9)
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
qemu-system-aarch64 -M "$MACHINE" -kernel build/kernel8.img -serial stdio $BUS -display none -monitor none \
    < build/uart.in > build/uart.out 2>&1 &
QEMU=$!
exec 3> build/uart.in
sleep 2
for line in "$@"; do
    printf '%s\r' "$line" >&3
    sleep 1
done
exec 3>&-
kill $QEMU 2>/dev/null
wait $QEMU 2>/dev/null
[ -n "$SIM" ] && { kill $SIM 2>/dev/null; wait $SIM 2>/dev/null; }
rm -f build/uart.in build/bus.in build/bus.out
tr -d '\r' < build/uart.out
if [ -f build/peer.txt ]; then cat build/peer.txt; fi
