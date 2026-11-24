// The only assembly: park secondary cores, leave EL2, enable FP/SIMD,
// set a stack, install the exception vectors, zero .bss, call the cancho program's main.
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
    adr     x0, vectors
    msr     vbar_el1, x0
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

// ---- exceptions ------------------------------------------------------------
// The kernel runs at EL1 on SP_EL1, so only the "current EL, SPx" row is ever
// taken on purpose: IRQ goes to board_irq, everything else is a fault that is
// reported on the UART and parks the core. (docs/issues/04: cancho cannot be
// entered from an exception yet, so both handlers are C.)
.macro fault kind
    .balign 0x80
    mov     x0, #\kind
    b       fault_entry
.endm

.section .text.vectors, "ax"
.balign 0x800
vectors:
    fault 0                       // current EL, SP0: sync / irq / fiq / serror
    fault 1
    fault 2
    fault 3
    fault 4                       // current EL, SPx: sync
    .balign 0x80
    b       irq_entry             //                  irq
    fault 6                       //                  fiq
    fault 7                       //                  serror
    fault 8                       // lower EL, AArch64 (no user mode yet)
    fault 9
    fault 10
    fault 11
    fault 12                      // lower EL, AArch32
    fault 13
    fault 14
    fault 15
    .balign 0x80

fault_entry:
    mrs     x1, esr_el1
    mrs     x2, elr_el1
    mrs     x3, far_el1
    bl      board_fault
    b       park

// board_irq is C built with -mgeneral-regs-only, so the interrupted code's FP/SIMD
// registers survive untouched; save them here the day the handler runs cancho.
// IRQs stay masked inside the handler (no nesting), so ELR/SPSR need no saving.
irq_entry:
    sub     sp, sp, #160
    stp     x0, x1, [sp, #0]
    stp     x2, x3, [sp, #16]
    stp     x4, x5, [sp, #32]
    stp     x6, x7, [sp, #48]
    stp     x8, x9, [sp, #64]
    stp     x10, x11, [sp, #80]
    stp     x12, x13, [sp, #96]
    stp     x14, x15, [sp, #112]
    stp     x16, x17, [sp, #128]
    stp     x18, x30, [sp, #144]
    bl      board_irq
    ldp     x0, x1, [sp, #0]
    ldp     x2, x3, [sp, #16]
    ldp     x4, x5, [sp, #32]
    ldp     x6, x7, [sp, #48]
    ldp     x8, x9, [sp, #64]
    ldp     x10, x11, [sp, #80]
    ldp     x12, x13, [sp, #96]
    ldp     x14, x15, [sp, #112]
    ldp     x16, x17, [sp, #128]
    ldp     x18, x30, [sp, #144]
    add     sp, sp, #160
    eret
