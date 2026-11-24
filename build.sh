#!/bin/sh
# Build cancho-os for a Raspberry Pi: cancho -> LLVM IR -> aarch64 bare metal.
#   ./build.sh    one kernel8.img for Pi 3 and Pi 4 (and QEMU raspi3b / raspi4b): the kernel asks the CPU which it is
set -eu
cd "$(dirname "$0")"
CANCHO=${CANCHO:-cancho}
mkdir -p build
T="--target=aarch64-none-elf"
# 1. cancho writes target-neutral LLVM IR; keep it instead of letting it link for the host
cat > build/keepll.sh <<W
#!/bin/sh
for a in "\$@"; do case \$a in *.ll) cp "\$a" "$PWD/build/kernel.ll";; esac; done
exec clang "\$@"
W
chmod +x build/keepll.sh
CANCHO_COMPILER=auto "$CANCHO" build src/kernel.cho --emit obj --clang "$PWD/build/keepll.sh" -o build/host.o
# The IR is target-neutral except the trap instruction, which follows the host (driver.cho): use aarch64's
sed 's/asm sideeffect "ud2"/asm sideeffect "udf #0xc11f"/' build/kernel.ll > build/kernel.ll.tmp
mv build/kernel.ll.tmp build/kernel.ll
# 2. compile it, the boot stub and the board for bare-metal aarch64
# -mstrict-align: until the MMU is on every access is to "device" memory, where an unaligned one faults
clang $T -O2 -mstrict-align -ffunction-sections -fdata-sections -Wno-override-module -c build/kernel.ll -o build/kernel.o
clang $T -O2 -ffreestanding -fno-builtin -mgeneral-regs-only -ffunction-sections -c board/board.c -o build/board.o
clang $T -c board/boot.S -o build/boot.o
# 3. link: whatever of cancho's hosted runtime main does not reach is dropped
ld.lld -T board/link.ld --gc-sections -o build/kernel8.elf build/boot.o build/board.o build/kernel.o
llvm-objcopy -O binary build/kernel8.elf build/kernel8.img
ls -l build/kernel8.img
