// A probe for docs/programs.md, section 8: what leaving one stack for another costs on AArch64.
// It is not part of the kernel and nothing of it is linked into an image. It runs alone in QEMU's `virt`:
//
//   clang --target=aarch64-none-elf -c tests/switch_probe.S -o switch.o
//   ld.lld -Ttext=0x40080000 -e _start switch.o -o switch.elf
//   qemu-system-aarch64 -M virt -cpu cortex-a57 -icount shift=0 -kernel switch.elf -serial stdio -display none
//
// With `-icount shift=0` QEMU's clock moves one nanosecond for each instruction, and the counter the probe
// reads (CNTVCT_EL0, 62,500,000 a second there) moves one for every sixteen. So the two numbers it prints,
// times sixteen, are instructions: first for a million turns of an empty loop, then for a million turns of
// the same loop with a switch there and a switch back in it. It says nothing about time on a real processor.
//
// `switch` is the whole of a switch as section 2 has it: the registers a function must keep for its caller
// (x19 to x30, the stack pointer, d8 to d15) go to the save area in x0 and come from the one in x1.
// Twenty-one words, 168 bytes, twenty-five instructions.
.text
.global _start
_start:
    mov     x0, #(3 << 20)            // no trap on the floating-point registers
    msr     cpacr_el1, x0
    isb
    ldr     x0, =stack_a
    mov     sp, x0
    // the second context: its stack, and where it begins
    ldr     x1, =ctx_b
    ldr     x2, =stack_b
    str     x2, [x1, #96]
    adr     x2, other
    str     x2, [x1, #88]             // x30: where its first `ret` goes

    ldr     x19, =1000000
    mrs     x20, cntvct_el0
1:  subs    x19, x19, #1
    b.ne    1b
    mrs     x21, cntvct_el0
    sub     x0, x21, x20
    bl      number

    ldr     x19, =1000000
    mrs     x20, cntvct_el0
2:  ldr     x0, =ctx_a
    ldr     x1, =ctx_b
    bl      switch
    subs    x19, x19, #1
    b.ne    2b
    mrs     x21, cntvct_el0
    sub     x0, x21, x20
    bl      number
3:  wfi                       // nothing ends QEMU: whoever started it does
    b       3b

other:
    ldr     x0, =ctx_b
    ldr     x1, =ctx_a
    bl      switch
    b       other

switch:
    stp     x19, x20, [x0, #0]
    stp     x21, x22, [x0, #16]
    stp     x23, x24, [x0, #32]
    stp     x25, x26, [x0, #48]
    stp     x27, x28, [x0, #64]
    stp     x29, x30, [x0, #80]
    mov     x9, sp
    str     x9, [x0, #96]
    stp     d8, d9, [x0, #104]
    stp     d10, d11, [x0, #120]
    stp     d12, d13, [x0, #136]
    stp     d14, d15, [x0, #152]
    ldp     x19, x20, [x1, #0]
    ldp     x21, x22, [x1, #16]
    ldp     x23, x24, [x1, #32]
    ldp     x25, x26, [x1, #48]
    ldp     x27, x28, [x1, #64]
    ldp     x29, x30, [x1, #80]
    ldr     x9, [x1, #96]
    mov     sp, x9
    ldp     d8, d9, [x1, #104]
    ldp     d10, d11, [x1, #120]
    ldp     d12, d13, [x1, #136]
    ldp     d14, d15, [x1, #152]
    ret

// x0 in decimal, and a new line, on the PL011 of `virt`
number:
    ldr     x3, =digits_end
    mov     x4, x3
    mov     x5, #10
4:  udiv    x6, x0, x5
    msub    x7, x6, x5, x0
    add     x7, x7, #'0'
    strb    w7, [x4, #-1]!
    mov     x0, x6
    cbnz    x0, 4b
    ldr     x8, =0x9000000
5:  ldrb    w7, [x4], #1
    str     w7, [x8]
    cmp     x4, x3
    b.lo    5b
    mov     w7, #10
    str     w7, [x8]
    ret

.bss
.balign 16
ctx_a:      .skip 168
            .skip 8
ctx_b:      .skip 168
            .skip 8
digits:     .skip 32
digits_end:
            .skip 4096
stack_a:
            .skip 4096
stack_b:
