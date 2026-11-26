// The only assembly in cancho-os. Two jobs:
//   1. boot: park secondary cores, leave EL2, enable FP/SIMD, set a stack, zero .bss, call main
//   2. exceptions: note which vector was taken and enter main again, which reports it (see kernel.cho)
// Nothing here is called by cancho: the kernel has no foreign function. What it needs from the link
// it reads as memory, at two addresses fixed here and named in its capabilities:
//   image + 0x10   two words, the end of the code and the end of the constants (inside `code`)
//   __fault_note   one word (2 MB + 32 KB above where RAM starts), the vector of the fault being reported, -1 for none (`fault`)
.section .text.boot, "ax"
.global _start
_start:
    b       boot
    .balign 16
    .quad   __text_end, __rodata_end
boot:
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
    // SCTLR_EL1 is undefined at reset on a real processor: the bits that must be one, and the MMU off
    ldr     x0, =0x30d00800
    msr     sctlr_el1, x0
    mov     x0, #0x3c5            // EL1h, interrupts masked (they stay masked: the kernel polls, see kernel.cho)
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
2:  ldr     x0, =__fault_note         // no fault is being reported
    mov     x1, #-1
    str     x1, [x0]
    mov     x0, #0
    mov     x1, #0
    bl      main
park:
    wfe
    b       park

// ---- exceptions ------------------------------------------------------------
// Nothing is ever taken on purpose: interrupts are masked and polled. So every
// vector is a fault. The stub notes which vector, throws the stack away and calls
// main a second time; main sees the note, reads ESR, ELR and FAR itself, reports
// and returns here.
// A fault while reporting a fault parks the core.
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
    fault 4                       // current EL, SPx
    fault 5
    fault 6
    fault 7
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
    ldr     x4, =__fault_note
    ldr     x5, [x4]
    cmn     x5, #1
    b.ne    park                  // already reporting one
    str     x0, [x4]
    ldr     x0, =_start
    mov     sp, x0
    mov     x0, #0
    mov     x1, #0
    bl      main
    b       park
