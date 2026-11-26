#!/bin/sh
# Send a file to a running cancho-os over SSH, to be kept on its disk (docs/update.md).
#   board/put.sh [ssh options] user@host <file> [name on the disk]
#   board/put.sh cancho@192.168.1.24 build/kernel8.img KERNEL8.IMG
# The kernel is told the length and the SHA-256 first; it keeps the file only if the bytes that came, and
# the bytes its disk gives back, have that hash. What the name held before stays in OLD.
set -eu
opts=""
while [ $# -gt 3 ] || { [ $# -eq 3 ] && [ ! -f "$2" ]; }; do opts="$opts $1"; shift; done
host=$1; file=$2
name=${3:-$(basename "$file" | tr 'a-z' 'A-Z')}
size=$(wc -c < "$file" | tr -d ' ')
if command -v sha256sum > /dev/null 2>&1; then sum=$(sha256sum "$file" | cut -d' ' -f1); else sum=$(shasum -a 256 "$file" | cut -d' ' -f1); fi
# shellcheck disable=SC2086
exec ssh $opts "$host" "put $name $size $sum" < "$file"
