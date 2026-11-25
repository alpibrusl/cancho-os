#!/bin/sh
# Build cancho-os: cancho compiles the kernel for bare-metal aarch64, the boot stub is
# assembled, and the link script places both. No C anywhere.
#   ./build.sh    one kernel8.img for Pi 3 and Pi 4 (and QEMU raspi3b / raspi4b): the kernel asks the CPU which it is
# Needs a cancho with `--target aarch64-none-elf` (docs/issues/01, 03), clang, ld.lld, llvm-objcopy.
set -eu
cd "$(dirname "$0")"
CANCHO=${CANCHO:-cancho}
CLANG=${CLANG:-clang}
mkdir -p build
"$CANCHO" build src/kernel.cho src/feetech.cho src/calibration.cho src/kinematics.cho src/so101.cho src/safety.cho src/inet.cho --std --target aarch64-none-elf --emit obj --clang "$(command -v "$CLANG")" -o build/kernel.o
"$CLANG" --target=aarch64-none-elf -c board/boot.S -o build/boot.o
# whatever main does not reach is dropped
ld.lld -T board/link.ld --gc-sections -o build/kernel8.elf build/boot.o build/kernel.o
llvm-objcopy -O binary build/kernel8.elf build/kernel8.img
ls -l build/kernel8.img
# the simulated servo bus for ./test.sh: an ordinary program for this machine (it is not in the image)
"$CANCHO" build sim/servos.cho src/feetech.cho -o build/servos
# the other end of the network link, the same way
"$CANCHO" build sim/netpeer.cho src/inet.cho -o build/netpeer
# and what `arm pose` must say for those servos, computed on this machine from the same sources
"$CANCHO" build sim/expect.cho src/calibration.cho src/kinematics.cho src/so101.cho src/safety.cho --std -o build/expect
