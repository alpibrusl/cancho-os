#!/bin/sh
# Boot build/kernel8.img in QEMU, type the lines given as arguments (one per second),
# and print what the UART said. Portable: no `timeout` (macOS has none).
#   ./test.sh about 'echo ci'            QEMU raspi3b
#   MACHINE=raspi4b ./test.sh about      needs a BOARD=pi4 build and QEMU >= 9
set -u
cd "$(dirname "$0")"
MACHINE=${MACHINE:-raspi3b}
mkdir -p build
rm -f build/uart.in build/uart.out
mkfifo build/uart.in
qemu-system-aarch64 -M "$MACHINE" -kernel build/kernel8.img -serial stdio -display none -monitor none \
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
rm -f build/uart.in
tr -d '\r' < build/uart.out
