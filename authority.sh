#!/bin/sh
# What the kernel can touch, checked two ways (what CI runs after build.sh):
#   1. `cancho authority` on the kernel is docs/authority.txt, line for line: the addresses each
#      capability holds, the system registers, and "never touches ... foreign code". A driver
#      that reaches for a new register changes this file, and the change is read in review.
#   2. A function lent one device cannot use another: a copy of the kernel in which `arm_zero`
#      (lent the console) writes to the servo bus with it must be refused, as a type mismatch.
# CANCHO names the compiler, as for build.sh.
set -eu
cd "$(dirname "$0")"
CANCHO=${CANCHO:-cancho}
SOURCES="src/feetech.cho src/calibration.cho src/kinematics.cho src/so101.cho src/safety.cho"
mkdir -p build
"$CANCHO" authority src/kernel.cho $SOURCES --std | sed '/^provably pure/,$d' > build/authority.txt
if ! diff docs/authority.txt build/authority.txt; then
    echo "authority.sh: the kernel's authority is not docs/authority.txt (update it if the change is meant)" >&2
    exit 1
fi
# the first statement of arm_zero becomes a write to the bus through the console's capability
awk '{ print } /^fn arm_zero\[/ { print "    bus_put(con, k, 0);" }' src/kernel.cho > build/steal.cho
grep -q '^    bus_put(con, k, 0);$' build/steal.cho
if "$CANCHO" check build/steal.cho $SOURCES --std --output json > build/steal.json 2>&1; then
    echo "authority.sh: a function lent the console wrote to the servo bus, and the compiler accepted it" >&2
    exit 1
fi
if ! grep -q '"rule": "type-mismatch"' build/steal.json; then
    echo "authority.sh: the stolen bus was refused, but not as a type mismatch:" >&2
    cat build/steal.json >&2
    exit 1
fi
echo "authority: as recorded; a function lent the console cannot write to the bus"
