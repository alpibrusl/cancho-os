// The only assembly in cancho-os. Three jobs:
//   1. boot: park secondary cores, leave EL2, enable FP/SIMD, set a stack, zero .bss, call main
//   2. exceptions: record what happened and enter main again, which reports it (see kernel.cho)
//   3. the hardware primitives cancho cannot spell yet, each one or two instructions,
//      exposed to cancho as the foreign library "board" (docs/issues/02 turns them into builtins)
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
2:  mov     x0, #0
    mov     x1, #0
    bl      main
park:
    wfe
    b       park

// ---- exceptions ------------------------------------------------------------
// Nothing is ever taken on purpose: interrupts are masked and polled. So every
// vector is a fault. The stub records it in `info`, throws the stack away and
// calls main a second time; main sees the record, reports it and returns here.
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
    adr     x4, info
    ldr     x5, [x4, #40]
    cmn     x5, #1
    b.ne    park                  // already reporting one
    str     x0, [x4, #40]
    mrs     x1, esr_el1
    str     x1, [x4, #48]
    mrs     x1, elr_el1
    str     x1, [x4, #56]
    mrs     x1, far_el1
    str     x1, [x4, #64]
    ldr     x0, =_start
    mov     sp, x0
    mov     x0, #0
    mov     x1, #0
    bl      main
    b       park

// ---- the "board" library: what cancho calls --------------------------------
.section .text.board, "ax"
.global board_info, board_sys_read, board_sys_write, board_wfi, board_tlb_flush

// board_info(i): 0 image start, 1 end of code, 2 end of constants, 3 page-table pool,
// 4 tables in the pool, 5 fault vector (-1: none), 6 ESR, 7 ELR, 8 FAR
board_info:
    adr     x1, info
    ldr     x0, [x1, x0, lsl #3]
    ret

board_wfi:  wfi                   // sleeps until an interrupt is pending, masked or not
            mov  x0, #0
            ret
board_tlb_flush:
    isb
    tlbi    vmalle1
    dsb     nsh
    isb
    mov     x0, #0
    ret

// System registers by number (the list kernel.cho names): `mrs`/`msr` take the
// register in the instruction, so each is its own two lines.
.macro sysr n, reg
    cmp     x0, #\n
    b.ne    1f
    mrs     x0, \reg
    ret
1:
.endm
.macro sysw n, reg
    cmp     x0, #\n
    b.ne    1f
    msr     \reg, x1
    isb
    mov     x0, #0
    ret
1:
.endm
board_sys_read:
    isb
    sysr 0, cntfrq_el0
    sysr 1, cntvct_el0
    sysr 2, cntv_ctl_el0
    sysr 3, cntv_cval_el0
    sysr 9, midr_el1
    mov     x0, #-1
    ret
board_sys_write:
    sysw 2, cntv_ctl_el0
    sysw 3, cntv_cval_el0
    sysw 4, cntv_tval_el0
    sysw 5, mair_el1
    sysw 6, tcr_el1
    sysw 7, ttbr0_el1
    sysw 8, sctlr_el1
    mov     x0, #-1
    ret

.section .data.info, "aw"
.balign 8
info:
    .quad   __text_start, __text_end, __rodata_end, __tables, 8
    .quad   -1, 0, 0, 0
