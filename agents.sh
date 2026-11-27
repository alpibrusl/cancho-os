#!/bin/sh
# An agent's key and what it is granted (docs/permissions.md, slice 5), in QEMU's virt machine.
#   ./agents.sh <disk image> <owner key> <agent key>
# The image is written to. The kernel must have been built with AUTHORIZED=<owner key>.pub.
# At the console three directories and three files are made, and KEYS.TXT with one line: the agent's key, granted
# to read DOCS and to write WORK/OUT. Then, with OpenSSH's client and the agent's key:
#   what it is granted works (list, peek, write, replace, move, under those two directories);
#   everything else is refused: a file at the top, a directory beside the granted one, the top's listing, a write
#   where it may only read, KEYS.TXT itself, and every command of the shell's that is not a tool.
# The record must say an agent's key made the changes. Then the owner writes the file again without the grant to
# write, and the same write is refused. Exit 0 if all of that held.
set -u
cd "$(dirname "$0")"
DISK=$1; OWNER=$2; AGENT=$3
akey=$(awk '{print $2}' "$AGENT.pub")
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
# the same with a line of input, for `write`, which reads what it is to write
sent() { key=$1; text=$2; shift 2; echo "\$ ssh ($(basename "$key")) $*"; printf '%s\n' "$text" | ssh -i "$key" $opts cancho@127.0.0.1 "$@" 2>&1 | tr -d '\r' | sed 's/^/    /'; }

mkdir -p build
start build/agents1.out
for d in DOCS WORK WORK/OUT WORK/OTHER; do say "mkdir $d"; done
say 'write --create --stdin DOCS/README.TXT'; say 'what the agent may read'; printf '\004' >&3; sleep 1
say 'write --create --stdin SECRET.TXT'; say 'not for the agent'; printf '\004' >&3; sleep 1
say 'write --create --stdin WORK/OTHER/MINE.TXT'; say 'beside what is granted'; printf '\004' >&3; sleep 1
say 'write --create --stdin KEYS.TXT'; say "agent ssh-ed25519 $akey read:DOCS write:WORK/OUT the builder"; printf '\004' >&3; sleep 1
say 'net up'
say 'net ssh on' 4
{
    as "$AGENT" 'list DOCS'
    as "$AGENT" 'peek docs/readme.txt'
    sent "$AGENT" 'made by an agent' 'write --create --stdin WORK/OUT/R.TXT'
    as "$AGENT" 'replace --old agent --new AGENT WORK/OUT/R.TXT'
    as "$AGENT" 'move WORK/OUT/R.TXT DONE.TXT'
    as "$AGENT" 'hash WORK/OUT/DONE.TXT'
} > build/agents-yes.out
{
    as "$AGENT" 'hash SECRET.TXT'
    as "$AGENT" 'peek KEYS.TXT'
    as "$AGENT" 'list .'
    as "$AGENT" 'list WORK'
    as "$AGENT" 'hash WORK/OTHER/MINE.TXT'
    as "$AGENT" 'seek agent WORK/OTHER/MINE.TXT'
    as "$AGENT" 'hash OLD/00000001.V'
    sent "$AGENT" 'x' 'write --create --stdin DOCS/NEW.TXT'
    sent "$AGENT" 'x' 'write --create --stdin WORK/OTHER/NEW.TXT'
    sent "$AGENT" 'x' 'write --create --stdin TOP.TXT'
    as "$AGENT" 'replace --old read --new write DOCS/README.TXT'
    as "$AGENT" 'move DOCS/README.TXT GONE.TXT'
} > build/agents-no.out
{
    as "$AGENT" ls
    as "$AGENT" 'cat SECRET.TXT'
    as "$AGENT" 'remove DOCS/README.TXT'
    as "$AGENT" 'copy SECRET.TXT WORK/OUT/S.TXT'
    as "$AGENT" 'net ssh off'
    as "$AGENT" restart
    as "$AGENT" 'fail trap'
} > build/agents-shell.out
as "$OWNER" 'cat LOG.TXT' > build/agents-log.out
# the grant to write is taken away: the owner writes the file again with `read:` where `write:` was
sent "$OWNER" "agent ssh-ed25519 $akey read:DOCS read:WORK/OUT the builder" "write --if-sha256 $(printf '%s\n' "agent ssh-ed25519 $akey read:DOCS write:WORK/OUT the builder" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -d' ' -f1) --max-diff-lines 0 --stdin KEYS.TXT" > build/agents-change.out
{
    sent "$AGENT" 'again' 'write --create --stdin WORK/OUT/R2.TXT'
    as "$AGENT" 'hash WORK/OUT/DONE.TXT'
} > build/agents-after.out
as "$OWNER" 'ls WORK/OUT' > build/agents-ls.out
stop
cat build/agents-yes.out build/agents-no.out build/agents-shell.out build/agents-log.out build/agents-change.out build/agents-after.out build/agents-ls.out | cut -c1-240
ok=0
# what is granted
[ "$(grep -c '"ok":true' build/agents-yes.out)" = 6 ] || ok=1
grep -q '"path":"WORK/OUT/R.TXT","changed":true,"created":true' build/agents-yes.out || ok=1
grep -q '"path":"WORK/OUT/R.TXT","to":"WORK/OUT/DONE.TXT","changed":true' build/agents-yes.out || ok=1
grep -q '"text":"what the agent may read"' build/agents-yes.out || ok=1
[ "$(grep -c '"ok":false\|"type":"error"' build/agents-yes.out)" = 0 ] || ok=1
# what is not: twelve commands, each refused, none answered
[ "$(grep -c '^\$ ssh' build/agents-no.out)" = 12 ] || ok=1
[ "$(grep -c '"ok":false' build/agents-no.out)" = 12 ] || ok=1
[ "$(grep -c '"ok":true\|"type":"hash"\|"type":"match"\|"type":"entry"' build/agents-no.out)" = 0 ] || ok=1
grep -q 'not for the agent\|beside what is granted' build/agents-no.out && ok=1
[ "$(grep -c "this key is an agent's" build/agents-shell.out)" = 7 ] || ok=1
grep -q 'not for the agent' build/agents-shell.out && ok=1
# the record: three changes by an agent's key, and none of the refused ones
[ "$(grep -c ' key:[0-9a-f]* agent ' build/agents-log.out)" = 3 ] || ok=1
grep -q ' agent move WORK/OUT/DONE.TXT WORK/OUT/R.TXT ' build/agents-log.out || ok=1
grep -q 'NEW.TXT\|TOP.TXT\|GONE.TXT' build/agents-log.out && ok=1
# after the grant is narrowed: the write is refused, the read still answered, and nothing was made
grep -q '"path":"KEYS.TXT","changed":true' build/agents-change.out || ok=1
grep -q '"ok":false' build/agents-after.out || ok=1
grep -q '"type":"hash","path":"WORK/OUT/DONE.TXT"' build/agents-after.out || ok=1
grep -q 'DONE.TXT' build/agents-ls.out || ok=1
grep -q 'R2.TXT\|NEW.TXT' build/agents-ls.out && ok=1
exit $ok
