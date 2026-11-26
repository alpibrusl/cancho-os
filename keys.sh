#!/bin/sh
# Who may log in, and the host key kept (docs/permissions.md, slice 2), in QEMU's virt machine.
#   ./keys.sh <disk image> <owner key> <reader key> <a key that is in neither place>
# The image is written to. The kernel must have been built with AUTHORIZED=<owner key>.pub.
# The first start: KEYS.TXT is made at the console with the reader's key in it, SSH is turned on, and
#   the owner writes a file; the reader lists files, and is refused when it writes or asks for the host key;
#   the stranger is not let in.
# The second start, of the same disk: the host key must be the one the first start made.
# Exit 0 if all of that held.
set -u
cd "$(dirname "$0")"
DISK=$1; OWNER=$2; READER=$3; STRANGER=$4
rkey=$(awk '{print $2}' "$READER.pub")
opts="-p 5522 -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=20"
start() {
    rm -f build/uart.in
    mkfifo build/uart.in
    qemu-system-aarch64 -M virt -cpu cortex-a57 -m 1G -global virtio-mmio.force-legacy=false \
        -netdev user,id=n0,net=10.0.0.0/24,host=10.0.0.1,hostfwd=tcp:127.0.0.1:5522-10.0.0.2:22 \
        -device virtio-net-device,netdev=n0 -device virtio-rng-device \
        -drive file="$DISK",format=raw,if=none,id=d0 -device virtio-blk-device,drive=d0 \
        -kernel build/kernel-virt.elf -serial stdio -display none -monitor none < build/uart.in > "$1" 2>&1 &
    QEMU=$!
    exec 3> build/uart.in
    sleep 2
}
stop() {
    exec 3>&-
    kill $QEMU 2>/dev/null
    wait $QEMU 2>/dev/null
    rm -f build/uart.in
}
say() { printf '%s\r' "$1" >&3; sleep "${2:-1}"; }
as() { key=$1; shift; echo "\$ ssh ($(basename "$key")) $*"; ssh -i "$key" $opts cancho@127.0.0.1 "$@" < /dev/null 2>&1 | tr -d '\r' | sed 's/^/    /'; }

mkdir -p build
start build/keys1.out
say 'net up'
say "write KEYS.TXT reader ssh-ed25519 $rkey the reader"
say 'net ssh on' 4
{
    as "$OWNER" 'write O.TXT written by an owner'
    as "$READER" ls
    as "$READER" 'write R.TXT written by a reader'
    as "$READER" 'ping 10.0.0.1'
    as "$READER" 'cat HOSTKEY.BIN'
    as "$OWNER" 'copy HOSTKEY.BIN STOLEN.BIN'
    as "$OWNER" 'cat O.TXT'
    as "$STRANGER" about
} > build/keys-ssh.out
say net
stop
start build/keys2.out
say 'net up'
say 'net ssh on' 4
as "$OWNER" 'cat O.TXT' >> build/keys-ssh.out
as "$OWNER" ls > build/keys-ls.out
stop
tr -d '\r' < build/keys1.out | grep -E "^written|^ssh is on|^ssh host key|^ssh on port"
cat build/keys-ssh.out
tr -d '\r' < build/keys2.out | grep -E "^ssh is on|^ssh host key"
first=$(tr -d '\r' < build/keys1.out | grep '^ssh host key' | sed 's/.*ssh-ed25519 //')
second=$(tr -d '\r' < build/keys2.out | grep '^ssh host key' | sed 's/.*ssh-ed25519 //')
ok=0
[ -n "$first" ] && [ "$first" = "$second" ] && echo "the host key is the same after the restart" || ok=1
grep -q "new, and kept on the disk as HOSTKEY.BIN" build/keys1.out || ok=1
grep -q "read from the disk: the same as before the restart" build/keys2.out || ok=1
grep -q "and from KEYS.TXT on the disk: 1" build/keys1.out || ok=1
grep -q "^    written: 20 bytes" build/keys-ssh.out || ok=1
grep -q "^    O.TXT " build/keys-ssh.out || ok=1
[ "$(grep -c "this key may only read: that needs an owner's key" build/keys-ssh.out)" = 2 ] || ok=1
[ "$(grep -c "the host key is kept by the kernel" build/keys-ssh.out)" = 2 ] || ok=1
[ "$(grep -c "^    written by an owner" build/keys-ssh.out)" = 2 ] || ok=1
grep -q "Permission denied" build/keys-ssh.out || ok=1
# and neither refused write left a file behind
cat build/keys-ls.out
grep -q "^    O.TXT " build/keys-ls.out || ok=1
grep -q "^    R.TXT \|^    STOLEN.BIN " build/keys-ls.out && ok=1
exit $ok
