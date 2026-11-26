#!/bin/sh
# `load` in QEMU (docs/load.md): the running kernel takes another over its serial console and starts it.
# The other is this build with its version changed to 0.0.99, so `about` says which one is running.
#   ./load.sh                  as a Pi 3
#   MACHINE=raspi4b ./load.sh  as a Pi 4
#   MACHINE=virt ./load.sh     QEMU's virt machine
# First a wrong checksum is typed, which must forget what was sent; then the right one.
# Exit 0 if the kernel that answers at the end is the one that was sent.
set -u
cd "$(dirname "$0")"
MACHINE=${MACHINE:-raspi3b}
KERNEL=build/kernel8.img
[ "$MACHINE" = virt ] && { MACHINE="virt -cpu cortex-a57 -m 1G"; KERNEL=build/kernel-virt.elf; }
# the image that is sent is always the flat one: it is copied to where the running kernel is
if [ "$KERNEL" = build/kernel-virt.elf ]; then
    llvm-objcopy -O binary build/kernel-virt.elf build/next.img
else
    cp build/kernel8.img build/next.img
fi
version=$(grep -ao 'cancho-os [0-9]*\.[0-9]*\.[0-9]*:' build/next.img | head -1)
LC_ALL=C sed "s/$version/cancho-os 0.0.99:/" build/next.img > build/next99.img
[ "$(wc -c < build/next.img)" = "$(wc -c < build/next99.img)" ] || { echo "load.sh: the changed image is not the same size" >&2; exit 1; }
size=$(wc -c < build/next99.img | tr -d ' ')
sum=$(python3 -c 'import zlib,sys; print("%08x" % zlib.adler32(open(sys.argv[1],"rb").read()))' build/next99.img)
rm -f build/uart.in build/load.out
mkfifo build/uart.in
qemu-system-aarch64 -M $MACHINE -kernel $KERNEL -serial stdio -display none -monitor none \
    < build/uart.in > build/load.out 2>&1 &
QEMU=$!
exec 3> build/uart.in
sleep 2
printf 'about\r' >&3; sleep 1
printf 'load %s\r' "$size" >&3; sleep 1
cat build/next99.img >&3; sleep 2
printf 'go 00000000\r' >&3; sleep 1
printf 'about\r' >&3; sleep 1
printf 'load %s\r' "$size" >&3; sleep 1
cat build/next99.img >&3; sleep 2
printf 'go %s\r' "$sum" >&3; sleep 3
printf 'about\r' >&3; sleep 1
printf 'ticks\r' >&3; sleep 1
printf 'crash null\r' >&3; sleep 1
exec 3>&-
kill $QEMU 2>/dev/null
wait $QEMU 2>/dev/null
rm -f build/uart.in
tr -d '\r' < build/load.out
echo "sent: $size bytes, adler32 $sum"
grep -q "adler32 $sum" build/load.out && grep -q "^forgotten" build/load.out && \
    [ "$(grep -c 'cancho-os 0.0.99:' build/load.out)" = 1 ] && tail -12 build/load.out | grep -q "data abort: address not mapped"
