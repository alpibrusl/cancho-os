// The only assembly: park secondary cores, leave EL2, enable FP/SIMD,
// set a stack, zero .bss, call the cancho program's main.
.section .text.boot, "ax"
.global _start
_start:
    mrs     x0, mpidr_el1
    and     x0, x0, #3
    cbnz    x0, park

    mrs     x0, CurrentEL
    lsr     x0, x0, #2
    cmp     x0, #2
    b.ne    at_el1
    // EL2 -> EL1: AArch64 at EL1, no traps of FP to EL2, timers accessible
    mov     x0, #(1 << 31)
    msr     hcr_el2, x0
    mov     x0, #0x33ff
    msr     cptr_el2, x0
    mov     x0, #3
    msr     cnthctl_el2, x0
    msr     cntvoff_el2, xzr
    mov     x0, #0x3c5            // EL1h, interrupts masked
    msr     spsr_el2, x0
    adr     x0, at_el1
    msr     elr_el2, x0
    eret
at_el1:
    mov     x0, #(3 << 20)        // CPACR_EL1.FPEN: no FP/SIMD traps
    msr     cpacr_el1, x0
    isb
    ldr     x0, =_start
    mov     sp, x0
    ldr     x0, =__bss_start
    ldr     x1, =__bss_end
1:  cmp     x0, x1
    b.hs    2f
    str     xzr, [x0], #8
    b       1b
2:  bl      board_init
    mov     x0, #0
    mov     x1, #0
    bl      main
park:
    wfe
    b       park
