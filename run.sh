#!/bin/sh
# Boot in QEMU (Pi 3 model; QEMU 9+ also has -M raspi4b). Ctrl-A X quits.
# For QEMU's own board with a network card: MACHINE=virt ./test.sh ... (test.sh has the command line).
exec qemu-system-aarch64 -M raspi3b -kernel build/kernel8.img -serial stdio -display none -monitor none
