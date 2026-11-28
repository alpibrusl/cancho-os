#!/bin/sh
# A program connects out (docs/network-out.md), in QEMU's virt machine.
#   ./netout.sh <disk image> <owner key> <agent key> [port] [reader key]
# The image is written to. The kernel must have been built with AUTHORIZED=<owner key>.pub.
# Python's HTTP server serves one page on three ports of this machine (`port`, 8765 if not given, and the two after
# it), which the board reaches at 10.0.0.1. KEYS.TXT has one line: the agent's key, granted `net:10.0.0.1:<port>`.
# Then, with OpenSSH's client:
#   the agent's `fetch` of the granted port: what comes back is the page, byte for byte;
#   the agent's `fetch` of the second port is refused, with the rule named, and no frame the board sent (QEMU's
#   filter-dump writes them all to a file) asks the second port for a connection;
#   the owner's `fetch` of the third port: the page;
#   with a reader's key too, its `fetch` of the granted port is refused: a reader watches;
#   the record has a line for each, with who and the bytes sent and received.
# Exit 0 if all of that held.
set -u
cd "$(dirname "$0")"
DISK=$1; OWNER=$2; AGENT=$3; PORT=${4:-8765}; READER=${5:-}
P2=$((PORT + 1)); P3=$((PORT + 2))
akey=$(awk '{print $2}' "$AGENT.pub")
opts="-p 5522 -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=20"
mkdir -p build/www
python3 -c "
import random
random.seed(51)
w = ['agents', 'first', 'lent', 'grant', 'board', 'record', 'cancho', 'kernel', 'page', 'fetch']
lines = [' '.join(random.choice(w) for _ in range(12)) for _ in range(300)]
open('build/www/page.txt', 'w').write('\n'.join(lines) + '\n')
open('build/www/small.txt', 'w').write('\n'.join(lines[:40]) + '\n')
"
SERVERS=""
for p in $PORT $P2 $P3; do
    python3 -m http.server "$p" --bind 127.0.0.1 --directory build/www > "build/www-$p.log" 2>&1 &
    SERVERS="$SERVERS $!"
done
rm -f build/netout.pcap build/uart.in
mkfifo build/uart.in
qemu-system-aarch64 -M virt -cpu cortex-a57 -m 1G -global virtio-mmio.force-legacy=false \
    -netdev user,id=n0,net=10.0.0.0/24,host=10.0.0.1,hostfwd=tcp:127.0.0.1:5522-10.0.0.2:22 \
    -device virtio-net-device,netdev=n0 -device virtio-rng-device \
    -object filter-dump,id=f0,netdev=n0,file=build/netout.pcap \
    -drive file="$DISK",format=raw,if=none,id=d0 -device virtio-blk-device,drive=d0 \
    -kernel build/kernel-virt.elf -serial stdio -display none -monitor none < build/uart.in > build/netout-console.out 2>&1 &
QEMU=$!
exec 3> build/uart.in
sleep 2
say() { printf '%s\r' "$1" >&3; sleep "${2:-1}"; }
as() { key=$1; shift; echo "\$ ssh ($(basename "$key")) $*"; { ssh -i "$key" $opts cancho@127.0.0.1 "$@" < /dev/null 2>&1; echo "[exit $?]"; } | tr -d '\r'; }

say 'write --create --stdin KEYS.TXT'; say "agent ssh-ed25519 $akey net:10.0.0.1:$PORT the fetcher"
[ -n "$READER" ] && say "reader ssh-ed25519 $(awk '{print $2}' "$READER.pub") a person who watches"
printf '\004' >&3; sleep 1
say 'net up'
say 'net ssh on' 4
# (what a program writes over SSH is cut at 4,096 bytes for now, cancho-os#58: these pages are smaller)
as "$AGENT" "fetch 10.0.0.1 $PORT /small.txt" > build/netout-agent.out
as "$AGENT" "fetch 10.0.0.1 $P2 /small.txt" > build/netout-refused.out
as "$OWNER" "fetch 10.0.0.1 $P3 /small.txt" > build/netout-owner.out
: > build/netout-reader.out
[ -n "$READER" ] && as "$READER" "fetch 10.0.0.1 $PORT /small.txt" > build/netout-reader.out
# and at the console, which may reach any machine too, the whole page of 22 KB
say "fetch 10.0.0.1 $P3 /page.txt" 6
say 'echo fetched'
as "$OWNER" 'cat LOG.TXT' > build/netout-log.out
exec 3>&-
kill $QEMU 2>/dev/null
wait $QEMU 2>/dev/null
rm -f build/uart.in
# shellcheck disable=SC2086
kill $SERVERS 2>/dev/null
head -c 600 build/netout-agent.out; echo; echo ...
cat build/netout-refused.out build/netout-reader.out
head -c 300 build/netout-owner.out; echo; echo ...
grep ' net' build/netout-log.out
ok=0
# the pages, each time the same bytes as the file: the body is what follows the first empty line
python3 -I - build/netout-agent.out build/netout-owner.out build/www/small.txt build/netout-console.out build/www/page.txt <<'EOF' || ok=1
import sys
bad = 0
def judge(name, got, want):
    global bad
    head, sep, body = got.partition(b'\n\n')
    same = head.startswith(b'HTTP/1.0 200 OK') and body == want
    print(name, len(body), 'bytes', 'the same as the page' if same else 'NOT the page')
    bad += not same
small = open(sys.argv[3], 'rb').read()
for name in sys.argv[1:3]:
    got = open(name, 'rb').read()
    judge(name, got[got.index(b'\n') + 1:got.rindex(b'[exit ')], small)
console = open(sys.argv[4], 'rb').read().replace(b'\r', b'')
start = console.index(b'> fetch 10.0.0.1')
start = console.index(b'\n', start) + 1
judge(sys.argv[4], console[start:console.index(b'> echo fetched')], open(sys.argv[5], 'rb').read())
sys.exit(bad)
EOF
grep -q '^\[exit 0\]' build/netout-agent.out || ok=1
# refused, with the rule named, and the program says it failed
grep -q "refused: net.not-granted 10.0.0.1:$P2" build/netout-refused.out || ok=1
grep -q '^\[exit 0\]' build/netout-refused.out && ok=1
grep -q 'HTTP/1.0' build/netout-refused.out && ok=1
if [ -n "$READER" ]; then
    grep -q "refused: net.not-granted 10.0.0.1:$PORT" build/netout-reader.out || ok=1
    grep -q " key:[0-9a-f]* reader net-refused 10.0.0.1:$PORT " build/netout-log.out || ok=1
fi
# no frame the board sent asks the refused port for a connection, and some ask the others (the capture is a judge)
python3 -I - build/netout.pcap "$PORT" "$P2" "$P3" <<'EOF' || ok=1
import struct, sys
data = open(sys.argv[1], 'rb').read()
ports = [int(p) for p in sys.argv[2:]]
syns = {p: 0 for p in ports}
at = 24
while at + 16 <= len(data):
    n = struct.unpack('<I', data[at + 8:at + 12])[0]
    f = data[at + 16:at + 16 + n]
    at += 16 + n
    if len(f) < 54 or f[12:14] != b'\x08\x00' or f[23] != 6 or f[26:30] != bytes([10, 0, 0, 2]):
        continue
    ihl = (f[14] & 15) * 4
    t = f[14 + ihl:]
    dport = struct.unpack('>H', t[2:4])[0]
    if t[13] & 2 and not t[13] & 16 and dport in syns:
        syns[dport] += 1
print('connections asked for, by port:', syns)
sys.exit(0 if syns[ports[0]] >= 1 and syns[ports[1]] == 0 and syns[ports[2]] >= 1 else 1)
EOF
# the record: the agent's connection with its bytes, its refusal, and the owner's
grep -q " key:[0-9a-f]* agent net 10.0.0.1:$PORT - [0-9][0-9]* 3[0-9][0-9][0-9] - " build/netout-log.out || ok=1
grep -q " key:[0-9a-f]* agent net-refused 10.0.0.1:$P2 " build/netout-log.out || ok=1
grep -q " key:[0-9a-f]* owner net 10.0.0.1:$P3 " build/netout-log.out || ok=1
grep -q " console console net 10.0.0.1:$P3 - [0-9][0-9]* 22[0-9][0-9][0-9] - " build/netout-log.out || ok=1
exit $ok
