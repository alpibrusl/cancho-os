#!/bin/sh
# Build cancho-os for a Raspberry Pi: cancho -> LLVM IR -> aarch64 bare metal.
#   ./build.sh            Pi 3 / QEMU raspi3b
#   BOARD=pi4 ./build.sh  Raspberry Pi 4
set -eu
cd "$(dirname "$0")"
CANCHO=${CANCHO:-cancho}
case ${BOARD:-pi3} in
  pi3) BASE=0x3F000000; DEFS= ;;
  pi4) BASE=0xFE000000; DEFS=-DBOARD_PI4 ;;
  *) echo "BOARD must be pi3 or pi4" >&2; exit 2 ;;
esac
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
clang $T -O2 -ffunction-sections -fdata-sections -Wno-override-module -c build/kernel.ll -o build/kernel.o
clang $T -O2 -ffreestanding -fno-builtin -mgeneral-regs-only -ffunction-sections -DPERIPHERAL_BASE=${BASE}UL $DEFS -c board/board.c -o build/board.o
clang $T -c board/boot.S -o build/boot.o
# 3. link: whatever of cancho's hosted runtime main does not reach is dropped
ld.lld -T board/link.ld --gc-sections -o build/kernel8.elf build/boot.o build/board.o build/kernel.o
llvm-objcopy -O binary build/kernel8.elf build/kernel8.img
ls -l build/kernel8.img
