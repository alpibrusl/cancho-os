#!/bin/sh
# The kernel's network link against a stack that is not ours: Linux's own SLIP driver and the system's `ping`.
# Linux only, and it needs root (a network interface is made): this is for CI, where sim/netpeer.cho's packets
# are checked by the kernel that everyone else's packets go through.
#   sudo ./ping.sh            boots build/kernel8.img in QEMU with its second serial port on a pty, types
#                             `net up`, attaches the pty as sl0 (10.0.0.1, the kernel is 10.0.0.2), and pings
#   sudo MACHINE=virt ./ping.sh   the same over Ethernet: QEMU's virt machine, its network card on a tap interface
# Exit 0 if every ping was answered, a UDP datagram to port 7 came back, a TCP connection to it echoed a line
# and then 64 KB (BYTES=n for another size), port 9 refused one, and the kernel's own ping of this machine
# was answered; the kernel fetched a page from a web server here and was refused by a port with none; `exit`
# over the shell's connection made the kernel hang up; on the card, dnsmasq gave the kernel an address and
# answered its questions about names, and the kernel then reached 10.0.0.1 by the gateway; and port 23 refused a connection before `net shell on` and gave the kernel's shell after it.
set -u
cd "$(dirname "$0")"
MACHINE=${MACHINE:-raspi3b}
mkdir -p build
rm -f build/uart.in build/ping-uart.out build/qemu.err
mkfifo build/uart.in
if [ "$MACHINE" = virt ]; then
    # the network card, on a tap interface of this machine: Ethernet frames, so ARP comes first
    # (a route to that one address, not to a /24: the machine's own network may be 10.0.0.x too, and the
    # ping would leave by it)
    ip tuntap add dev tap0 mode tap && ip addr add 10.0.0.1 peer 10.0.0.2 dev tap0 && ip link set tap0 up
    qemu-system-aarch64 -M virt -cpu cortex-a57 -m 1G -global virtio-mmio.force-legacy=false \
        -netdev tap,id=n0,ifname=tap0,script=no,downscript=no -device virtio-net-device,netdev=n0 -device virtio-rng-device \
        -kernel build/kernel-virt.elf -serial stdio -display none -monitor none \
        < build/uart.in > build/ping-uart.out 2> build/qemu.err &
else
    qemu-system-aarch64 -M "$MACHINE" -kernel build/kernel8.img -serial stdio -serial pty -display none -monitor none \
        < build/uart.in > build/ping-uart.out 2> build/qemu.err &
fi
QEMU=$!
exec 3> build/uart.in
sleep 2
status=1
SLIP=
ready=1
if [ "$MACHINE" != virt ]; then
    PTY=$(grep -o '/dev/pts/[0-9]*' build/ping-uart.out build/qemu.err | head -1 | sed 's/^[^:]*://')
    if [ -z "$PTY" ]; then
        echo "ping.sh: QEMU did not say which pty the second serial port is" >&2
        ready=
    fi
fi
if [ -n "$ready" ]; then
    printf 'net up\r' >&3
    if [ "$MACHINE" != virt ]; then
        modprobe slip 2>/dev/null
        slattach -L -p slip -s 115200 "$PTY" &
        SLIP=$!
        sleep 1
        ip addr add 10.0.0.1 peer 10.0.0.2 dev sl0 && ip link set sl0 up mtu 1006
    fi
    sleep 1
    if [ -n "${TRACE:-}" ] && [ "$MACHINE" = virt ]; then
        # what is on the wire, both ways, for when the answer is not what was expected
        tcpdump -i tap0 -n -e -c 400 > build/trace.txt 2>&1 &
        sleep 1
    fi
    ping -c 5 -i 0.3 -W 2 10.0.0.2 && status=0
    # a datagram to the echo port, and what comes back
    back=$(printf 'cancho-os over udp' | timeout 3 nc -u -w 1 10.0.0.2 7)
    echo "udp echo: '$back'"
    [ "$back" = "cancho-os over udp" ] || status=1
    # a connection to the same port: Linux's TCP opens it, sends, closes, and reads what comes back
    back=$(printf 'cancho-os over tcp' | timeout 10 nc -N -w 5 10.0.0.2 7)
    echo "tcp echo: '$back'"
    [ "$back" = "cancho-os over tcp" ] || status=1
    # and enough to need many segments, each of which must be acknowledged before the next is taken
    head -c "${BYTES:-65536}" /dev/urandom > build/tcp.sent
    start=$(date +%s)
    timeout 120 nc -N -w 30 10.0.0.2 7 < build/tcp.sent > build/tcp.back
    if cmp -s build/tcp.sent build/tcp.back; then
        echo "tcp echo: $(wc -c < build/tcp.back) bytes came back the same, in $(( $(date +%s) - start )) s"
    else
        echo "tcp echo: $(wc -c < build/tcp.back) bytes came back, NOT the $(wc -c < build/tcp.sent) sent"
        status=1
    fi
    # a port nothing listens on: the kernel must say no at once (a reset), not leave Linux waiting
    refused=$(timeout 5 nc -v -w 3 10.0.0.2 9 < /dev/null 2>&1 | tr "\n" " ")
    echo "tcp port 9: ${refused:-no answer}"
    echo "$refused" | grep -qi refused || status=1
    # the shell's port is closed until the console opens it
    closed=$(timeout 5 nc -v -w 3 10.0.0.2 23 < /dev/null 2>&1 | tr "\n" " ")
    echo "tcp port 23, before: ${closed:-no answer}"
    echo "$closed" | grep -qi refused || status=1
    printf 'net shell on\r' >&3
    sleep 1
    # the kernel's shell from Linux: two lines a second apart, answered while the connection is open, then
    # Linux finishes and the kernel does
    (printf 'about\n'; sleep 1; printf 'mem\n'; sleep 1) | timeout 15 nc -N -w 5 10.0.0.2 23 | tr -d '\r' | sed 's/^/remote: /' > build/remote.txt
    cat build/remote.txt
    grep -q "^remote: > cancho-os .* no Linux underneath" build/remote.txt || status=1
    grep -q "r-x  kernel code" build/remote.txt || status=1
    # `exit` there: the kernel hangs up while Linux's end is still open (its input stays open six seconds)
    (printf 'about\nexit\n'; sleep 6) | timeout 12 nc -N -w 10 10.0.0.2 23 | tr -d '\r' > build/exit.txt &
    NC=$!
    sleep 3
    printf 'echo after exit\r' >&3
    sleep 1
    printf 'net\r' >&3
    sleep 1
    echo
    tr -d '\r' < build/ping-uart.out | awk '/^after exit/ { f = 1 } f && /^shell on port 23/ { print "exit: " $0; exit }'
    wait $NC
    grep -q "bye" build/exit.txt && echo "exit: the kernel said bye" || status=1
    # the kernel opens a connection: a web server on this machine, asked for its page; and a port with none
    mkdir -p build/www && echo "a page from linux, for cancho-os" > build/www/index.html
    (cd build/www && exec python3 -m http.server 8099 --bind 10.0.0.1) > /dev/null 2>&1 &
    WWW=$!
    sleep 1
    printf 'http 10.0.0.1 8099\r' >&3
    sleep 3
    printf 'http 10.0.0.1 8098\r' >&3
    sleep 3
    kill $WWW 2>/dev/null
    grep -q "a page from linux, for cancho-os" build/ping-uart.out || status=1
    grep -q "no connection to 10.0.0.1 port 8098" build/ping-uart.out || status=1
    if [ "$MACHINE" = virt ]; then
        # what this machine's own ARP table learned from the kernel's answer
        ip neigh show dev tap0
    fi
    if [ "$MACHINE" = virt ]; then
        # An address that is given, and names, from a server that is not ours: dnsmasq, on a second network
        # of the same interface (172.31.77.0/24), so that the kernel's address really changes. After it the
        # kernel is no longer on 10.0.0.1's network, and its ping of 10.0.0.1 below goes by the gateway.
        ip addr add 172.31.77.1/24 dev tap0
        dnsmasq --keep-in-foreground --user=root --conf-file=/dev/null --interface=tap0 --bind-interfaces \
            --dhcp-range=172.31.77.50,172.31.77.60,255.255.255.0,1h --dhcp-option=3,172.31.77.1 \
            --dhcp-option=6,172.31.77.1 --address=/www.cancho-os.test/172.31.77.1 --local=/cancho-os.test/ \
            --no-resolv --no-hosts --dhcp-leasefile="$PWD/build/leases" --log-dhcp --log-queries \
            --log-facility="$PWD/build/dnsmasq.log" &
        DNSMASQ=$!
        (cd build/www && exec python3 -m http.server 8099 --bind 172.31.77.1) > /dev/null 2>&1 &
        WWW=$!
        sleep 1
        printf 'net dhcp\r' >&3
        sleep 5
        printf 'lookup www.cancho-os.test\r' >&3
        sleep 2
        printf 'lookup nothing.cancho-os.test\r' >&3
        sleep 2
        printf 'http www.cancho-os.test 8099\r' >&3
        sleep 3
        kill $DNSMASQ $WWW 2>/dev/null
        echo "what dnsmasq saw:"
        grep -E "DHCP(DISCOVER|OFFER|REQUEST|ACK)|query\[A\]" build/dnsmasq.log | sed 's/^.*dnsmasq[^:]*: /  /'
        grep -q "^address 172.31.77.5[0-9], mask 255.255.255.0, gateway 172.31.77.1, names from 172.31.77.1" build/ping-uart.out || status=1
        grep -q "^www.cancho-os.test is 172.31.77.1" build/ping-uart.out || status=1
        grep -q "^no such name: nothing.cancho-os.test" build/ping-uart.out || status=1
        test "$(grep -c "a page from linux, for cancho-os" build/ping-uart.out)" = 2 || status=1
    fi
    # the kernel speaks first: it asks who 10.0.0.1 is (on the card) and pings it; Linux answers both
    printf 'ping 10.0.0.1\r' >&3
    sleep 2
    printf 'net\r' >&3
    sleep 1
    # every connection of this run has ended, the one the kernel hung up on included
    tr -d '\r' < build/ping-uart.out | grep "^tcp: " | tail -1 | grep -q "^tcp: 0 open" || { echo "a connection was left open"; status=1; }
    grep -q "reply from 10.0.0.1 in" build/ping-uart.out || status=1
    [ -n "$SLIP" ] && kill $SLIP 2>/dev/null
fi
exec 3>&-
kill $QEMU 2>/dev/null
wait $QEMU 2>/dev/null
[ "$MACHINE" = virt ] && ip link del tap0 2>/dev/null
rm -f build/uart.in
tr -d '\r' < build/ping-uart.out
if [ -f build/trace.txt ]; then cat build/trace.txt; fi
exit $status
