// The only assembly in cancho-os. Three jobs:
//   1. boot: park secondary cores, leave EL2, enable FP/SIMD, set a stack, zero .bss, call main
//   2. exceptions: note which vector was taken and enter main again, which reports it (see kernel.cho)
//   3. start a kernel that was loaded over the serial line, in place of this one (docs/load.md)
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
    // Whatever is in the caches is not ours: the firmware's, or an earlier kernel's. The kernel turns
    // them on later; they are emptied here, while they are off. Every level of data cache, every set
    // and way of it (the architecture's own recipe), then the instruction cache and the TLB.
    mrs     x0, clidr_el1
    ubfx    w3, w0, #24, #3           // how many levels there are
    cbz     w3, 9f
    mov     w10, #0                   // the level
5:  add     w2, w10, w10, lsl #1
    lsr     w1, w0, w2
    and     w1, w1, #7
    cmp     w1, #2
    b.lo    8f                        // no data cache at this level
    lsl     w11, w10, #1
    msr     csselr_el1, x11
    isb
    mrs     x1, ccsidr_el1
    and     w2, w1, #7
    add     w2, w2, #4                // log2 of a line's bytes
    ubfx    w4, w1, #3, #10           // ways, less one
    clz     w5, w4                    // where the way goes in the operand
    ubfx    w6, w1, #13, #15          // sets, less one
6:  mov     w7, w6
7:  lsl     w8, w4, w5
    orr     w8, w8, w11
    lsl     w9, w7, w2
    orr     w8, w8, w9
    dc      isw, x8
    subs    w7, w7, #1
    b.ge    7b
    subs    w4, w4, #1
    b.ge    6b
8:  add     w10, w10, #1
    cmp     w10, w3
    b.lo    5b
9:  msr     csselr_el1, xzr
    dsb     sy
    ic      iallu
    tlbi    vmalle1
    dsb     sy
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

// ---- a kernel loaded over the serial line (docs/load.md) --------------------
// x4 is where it waits: the mark, its length, the image. The image goes where this one is, and is started
// as the firmware would start it, except that it is entered at EL1.
chain:
    str     xzr, [x4]                 // the mark is used once
    ldr     x7, [x4, #8]              // how many bytes
    // What this kernel wrote is partly still in the data cache: write it out, and empty the cache, so
    // that the next kernel does not find this one's data when it turns the cache on again.
    // (All the RAM this kernel maps, to the end of its heap: its state lives in the heap, and what is
    // left in the cache from there comes back over the next kernel's when the cache is on again. Seen
    // on a real Pi 4, where a loaded kernel woke up with its predecessor's address and counters.)
    ldr     x0, =__mapped_start
    ldr     x1, =__cancho_heap_end
1:  dc      civac, x0
    add     x0, x0, #64
    cmp     x0, x1
    b.lo    1b
    dsb     sy
    // Translation and both caches off: the image about to be replaced is mapped read-only.
    mrs     x0, sctlr_el1
    bic     x0, x0, #(1 << 0)
    bic     x0, x0, #(1 << 2)
    bic     x0, x0, #(1 << 12)
    msr     sctlr_el1, x0
    isb
    ic      iallu
    dsb     sy
    isb
    // The loop that copies cannot run from the image it overwrites: it is moved below the stack first.
    adr     x0, copier
    adr     x1, copier_end
    ldr     x2, =__copier
    mov     x3, x2
2:  ldr     w8, [x0], #4
    str     w8, [x3], #4
    cmp     x0, x1
    b.lo    2b
    add     x0, x4, #16               // from
    ldr     x1, =_start               // to
    mov     x9, x1                    // and where to start it
    br      x2
copier:
3:  ldrb    w8, [x0], #1
    strb    w8, [x1], #1
    subs    x7, x7, #1
    b.ne    3b
    br      x9
copier_end:

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
    // A kernel loaded over the serial line (docs/load.md)? The kernel marks it and faults on purpose.
    ldr     x4, =__stage
    ldr     x5, [x4]
    ldr     x6, =0x6f6863616e6163     // "canacho", the mark
    cmp     x5, x6
    b.eq    chain
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
