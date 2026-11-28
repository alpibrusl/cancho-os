#!/bin/sh
# measure.sh -- what docs/tls.md measured, again. Nothing here is part of the kernel or of its tests in CI.
#   CANCHO=/path/to/cancho CANCHO_SRC=/path/to/a/checkout/of/cancho sh tests/tls/measure.sh
# Needs the compiler with `--target aarch64-none-elf` (README), clang and llvm-size and llvm-nm on the PATH, python3,
# and for the second half OpenSSL 3 or later (OPENSSL=, default `openssl`) and curl. Ports 44331 to 44337 on this machine.
# Everything is written under build/tls.
set -u
cd "$(dirname "$0")/../.."
C=${CANCHO:-cancho}; R=${CANCHO_SRC:?CANCHO_SRC: a checkout of https://github.com/alpibrusl/cancho}; O=${OPENSSL:-openssl}
T=tests/tls; W=build/tls; mkdir -p "$W"
client="record message slot cident client12 client"; x509="verify names x509 key"
files() { for f in $client; do printf '%s ' "$1/packages/tls/$f.cho"; done; for f in $x509; do printf '%s ' "$1/packages/x509/$f.cho"; done; }
sizes() { llvm-size -A "$1" | awk '$1 ~ /^\.text/ { t += $2 } $1 ~ /^\.rodata/ { r += $2 } END { print t " bytes of code, " r " of constants" }'; }

echo "1. the library as it is, for the bare target:"
"$C" build $T/bare.cho $(files "$R") --std --target aarch64-none-elf --emit obj -o "$W/asis.o" 2>&1 | head -3
echo "   what the same program reaches of the runtime, built for this machine:"
"$C" build $T/bare.cho $(files "$R") --std --emit ll -o "$W/host.ll" && python3 $T/reach.py "$W/host.ll" | sed -n 2,3p | tr ' ' '\n' | grep -v '^sinit\|^llvm\.\|^lexs_' | tr '\n' ' '
echo
echo "2. with the CPU never asked for its AES and SHA instructions (soften.py):"
python3 $T/soften.py "$R" "$W/soft"
std=$(for n in $(cat "$R/std/std.files"); do printf '%s ' "$W/soft/std/$n"; done)
"$C" build $T/bare.cho $(files "$W/soft") $std --target aarch64-none-elf --emit obj -o "$W/bare.o" || exit 1
"$C" build $T/none.cho --std --target aarch64-none-elf --emit obj -o "$W/none.o" || exit 1
echo "   with the client:    $(sizes "$W/bare.o")"
echo "   without:            $(sizes "$W/none.o")"
echo "   not defined in it:  $(llvm-nm -u "$W/bare.o" | tr -s ' \n' ' ')"

echo "3. against another system's server, on this machine:"
"$C" build $T/client.cho $(files "$R") --std -o "$W/client" || exit 1
"$C" build $T/client.cho $(files "$W/soft") $std -o "$W/client-soft" || exit 1
mkdir -p "$W/pki" "$W/www"
[ -f "$W/pki/good.pem" ] || (cd "$W/pki" && sh ../../../$T/certs.sh "$O" > certs.log 2>&1)
[ -f "$W/www/big.bin" ] || { head -c 1048576 /dev/urandom > "$W/www/big.bin"; echo 'hello from another machine' > "$W/www/hello.txt"; }
pids=
serve() { (cd "$W/www" && exec "$O" s_server -accept "127.0.0.1:$1" -cert "../pki/$2.pem" -key "../pki/$2.key" -WWW -quiet $3 > "../s_server-$1.log" 2>&1) & pids="$pids $!"; }
serve 44331 good ""; serve 44332 ended ""; serve 44333 othername ""; serve 44334 unknown ""
serve 44335 good "-ciphersuites TLS_AES_256_GCM_SHA384"; serve 44336 good "-ciphersuites TLS_CHACHA20_POLY1305_SHA256"; serve 44337 good "-tls1_2"
trap 'kill $pids 2>/dev/null' EXIT
sleep 1
ask() { name=$1; shift; printf '   %-34s ' "$name"; "$@" 2>&1 >/dev/null | tr '\n' ' '; echo; }
ca=$W/pki/ca.pem
ask "a good certificate"            "$W/client" 127.0.0.1 44331 board.test "$ca" 0 1 /hello.txt
ask "the same, ChaCha20 only"      "$W/client" 127.0.0.1 44336 board.test "$ca" 0 1 /hello.txt
ask "the same, TLS 1.2 only"       "$W/client" 127.0.0.1 44337 board.test "$ca" 0 1 /hello.txt
ask "one that has ended"            "$W/client" 127.0.0.1 44332 board.test "$ca" 0 1 /hello.txt
ask "one for another name"          "$W/client" 127.0.0.1 44333 board.test "$ca" 0 1 /hello.txt
ask "one signed by nobody known"    "$W/client" 127.0.0.1 44334 board.test "$ca" 0 1 /hello.txt
ask "a good one, and no roots"      "$W/client" 127.0.0.1 44331 board.test /dev/null 0 1 /hello.txt
ask "a good one, the date 1970"     "$W/client" 127.0.0.1 44331 board.test "$ca" 1 1 /hello.txt
ask "a good one, the date 2020"     "$W/client" 127.0.0.1 44331 board.test "$ca" 1592000000 1 /hello.txt
"$W/client-soft" 127.0.0.1 44331 board.test "$ca" 0 1 /big.bin > "$W/big.got" 2>/dev/null
curl -s -i --http1.0 --cacert "$ca" --resolve board.test:44331:127.0.0.1 https://board.test:44331/big.bin > "$W/big.curl"
cmp -s "$W/big.got" "$W/big.curl" && echo "   a file of 1 MiB: the same $(wc -c < "$W/big.got" | tr -d ' ') bytes curl gets" || echo "   a file of 1 MiB: NOT what curl gets"
if /usr/bin/time -l true 2>&1 | grep -q 'instructions retired'; then
    count() { /usr/bin/time -l "$@" 2>&1 >/dev/null | awk '/instructions retired/ { i = $1 } /cycles elapsed/ { c = $1 } / real / { r = $1 } END { print i, c, r }'; }
    echo "   instructions, cycles and seconds (macOS's /usr/bin/time -l), software only, 50 connections each:"
    echo "   none                         $(count "$W/client-soft" 127.0.0.1 44335 board.test "$ca" 0 0 /hello.txt quiet)"
    echo "   AES-256-GCM, 27 bytes        $(count "$W/client-soft" 127.0.0.1 44335 board.test "$ca" 0 50 /hello.txt quiet)"
    echo "   AES-256-GCM, 1 MiB           $(count "$W/client-soft" 127.0.0.1 44335 board.test "$ca" 0 50 /big.bin quiet)"
    echo "   ChaCha20-Poly1305, 27 bytes  $(count "$W/client-soft" 127.0.0.1 44336 board.test "$ca" 0 50 /hello.txt quiet)"
    echo "   ChaCha20-Poly1305, 1 MiB     $(count "$W/client-soft" 127.0.0.1 44336 board.test "$ca" 0 50 /big.bin quiet)"
    echo "   as it is: AES-256-GCM, 27 b  $(count "$W/client" 127.0.0.1 44335 board.test "$ca" 0 50 /hello.txt quiet)"
fi
