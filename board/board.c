// Board support: the few things cancho cannot express yet (volatile MMIO),
// plus the handful of libc symbols cancho's runtime reaches for.
// Exposed to cancho as the foreign library "board".
#include <stdint.h>
#include <stddef.h>

#ifndef PERIPHERAL_BASE
#define PERIPHERAL_BASE 0x3F000000UL   // Pi 3 (and QEMU raspi3b); Pi 4 is 0xFE000000
#endif
#define GPIO  (PERIPHERAL_BASE + 0x200000)
#define UART0 (PERIPHERAL_BASE + 0x201000)

static inline void w32(uintptr_t a, uint32_t v) { *(volatile uint32_t *)a = v; }
static inline uint32_t r32(uintptr_t a) { return *(volatile uint32_t *)a; }

#define UART_DR   (UART0 + 0x00)
#define UART_FR   (UART0 + 0x18)
#define UART_IBRD (UART0 + 0x24)
#define UART_FBRD (UART0 + 0x28)
#define UART_LCRH (UART0 + 0x2C)
#define UART_CR   (UART0 + 0x30)
#define UART_ICR  (UART0 + 0x44)

static int irq_on, mmu_is_on;

void board_init(void) {
    w32(UART_CR, 0);                          // UART off
    uint32_t sel = r32(GPIO + 0x04);          // GPFSEL1: GPIO14/15 -> ALT0 (TXD0/RXD0)
    sel &= ~((7u << 12) | (7u << 15));
    sel |= (4u << 12) | (4u << 15);
    w32(GPIO + 0x04, sel);
    w32(UART_ICR, 0x7FF);
    w32(UART_IBRD, 26);                       // 115200 baud from a 48 MHz UART clock
    w32(UART_FBRD, 3);
    w32(UART_LCRH, (3u << 5) | (1u << 4));    // 8N1, FIFOs on
    w32(UART_CR, (1u << 0) | (1u << 8) | (1u << 9)); // enable, TX, RX
}

int64_t board_putc(int64_t c) {
    while (r32(UART_FR) & (1u << 5)) {}       // TX FIFO full
    w32(UART_DR, (uint32_t)c);
    return 0;
}

int64_t board_getc(void) {
    while (r32(UART_FR) & (1u << 4)) {        // RX FIFO empty
        if (irq_on) __asm__ volatile("wfi");  // sleep until the next interrupt (at most one tick)
    }
    return (int64_t)(r32(UART_DR) & 0xFF);
}

// ---- interrupts: the ARM generic timer through the board's interrupt controller ----
// Pi 4: GIC-400 (distributor +0x1000, CPU interface +0x2000), virtual timer = PPI 27.
// Pi 3: the BCM2836 per-core block at 0x40000000, virtual timer = bit 3.
#ifdef BOARD_PI4
#define GICD 0xFF841000UL
#define GICC 0xFF842000UL
#define TIMER_PPI 27
#else
#define CORE0_TIMER_IRQCNTL 0x40000040UL
#define CORE0_IRQ_SOURCE    0x40000060UL
#endif

static uint64_t tick_interval;                // counter units per tick
static volatile uint64_t ticks;

static inline uint64_t cntfrq(void) { uint64_t v; __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(v)); return v; }
static inline uint64_t cntvct(void) { uint64_t v; __asm__ volatile("isb; mrs %0, cntvct_el0" : "=r"(v)); return v; }

// Start a periodic tick and unmask IRQs. Returns the counter frequency in Hz.
int64_t board_tick_start(int64_t hz) {
    if (hz < 1) hz = 1;
    tick_interval = cntfrq() / (uint64_t)hz;
#ifdef BOARD_PI4
    w32(GICD + 0x000, 0);                                 // distributor off while configuring
    *(volatile uint8_t *)(GICD + 0x400 + TIMER_PPI) = 0xA0; // priority
    w32(GICD + 0x100, 1u << TIMER_PPI);                   // GICD_ISENABLER0
    w32(GICD + 0x000, 1);
    w32(GICC + 0x004, 0xFF);                              // GICC_PMR: let every priority through
    w32(GICC + 0x000, 1);                                 // GICC_CTLR
#else
    w32(CORE0_TIMER_IRQCNTL, 1u << 3);                    // route CNTVIRQ to core 0's IRQ
#endif
    __asm__ volatile("msr cntv_tval_el0, %0" : : "r"(tick_interval));
    __asm__ volatile("msr cntv_ctl_el0, %0" : : "r"((uint64_t)1));
    irq_on = 1;
    __asm__ volatile("msr daifclr, #2");                  // unmask IRQ
    return (int64_t)cntfrq();
}

int64_t board_ticks(void) { return (int64_t)ticks; }

// Milliseconds since the counter started, read from the counter itself (not the tick count).
int64_t board_uptime_ms(void) {
    uint64_t f = cntfrq(), c = cntvct();
    return (int64_t)(c / f * 1000 + c % f * 1000 / f);
}

static void timer_tick(void) {
    uint64_t cval;
    __asm__ volatile("mrs %0, cntv_cval_el0" : "=r"(cval));
    cval += tick_interval;                                // from the last deadline: no drift
    __asm__ volatile("msr cntv_cval_el0, %0" : : "r"(cval));
    ticks++;
}

void board_irq(void) {
#ifdef BOARD_PI4
    uint32_t iar = r32(GICC + 0x00C);                     // acknowledge
    if ((iar & 0x3FF) == TIMER_PPI) timer_tick();
    if ((iar & 0x3FF) < 1020) w32(GICC + 0x010, iar);     // end of interrupt
#else
    if (r32(CORE0_IRQ_SOURCE) & (1u << 3)) timer_tick();
#endif
}

// ---- memory: identity-mapped page tables (4 KB granule, 39-bit addresses) ------
// The kernel (cancho) decides the map and calls board_map once per range; this is the
// mechanism: fill tables, then turn the MMU and the caches on.
extern char __text_start[], __text_end[], __rodata_end[];
#define NTABLES 8
static uint64_t tables[NTABLES][512] __attribute__((aligned(4096)));  // tables[0] is level 1
static int tables_used = 1;

#define PTE_VALID  1ull
#define PTE_TABLE  2ull            // at levels 1-2: next-level table; at level 3: a page
#define PTE_AF     (1ull << 10)
#define PTE_INNER  (3ull << 8)
#define PTE_RO     (1ull << 7)
#define PTE_PXN    (1ull << 53)
#define PTE_UXN    (1ull << 54)

// perm: 0 read+execute, 1 read-only, 2 read+write, 3 device (read+write, uncached)
static uint64_t attrs(int64_t perm) {
    switch (perm) {
    case 0:  return PTE_AF | PTE_INNER | PTE_RO | PTE_UXN;
    case 1:  return PTE_AF | PTE_INNER | PTE_RO | PTE_PXN | PTE_UXN;
    case 2:  return PTE_AF | PTE_INNER | PTE_PXN | PTE_UXN;
    default: return PTE_AF | PTE_PXN | PTE_UXN | (1ull << 2);   // MAIR index 1
    }
}

static uint64_t *next_table(uint64_t *slot) {
    if (*slot & PTE_VALID) {
        if (!(*slot & PTE_TABLE)) return 0;                     // already a block: refuse to split
        return (uint64_t *)(*slot & 0x0000FFFFFFFFF000ull);
    }
    if (tables_used == NTABLES) return 0;
    uint64_t *t = tables[tables_used++];
    *slot = (uint64_t)t | PTE_TABLE | PTE_VALID;
    return t;
}

// Identity-map [start, end) with one permission, using 1 GB / 2 MB blocks where the
// range allows and 4 KB pages elsewhere. Returns 0, or -1 (misaligned, out of range,
// out of tables, or overlapping an existing block).
int64_t board_map(int64_t start, int64_t end, int64_t perm) {
    uint64_t va = (uint64_t)start, e = (uint64_t)end, a = attrs(perm);
    if ((va | e) & 0xFFF || va > e || e > (1ull << 39) || mmu_is_on) return -1;
    while (va < e) {
        uint64_t *l1 = &tables[0][va >> 30];
        if (!(va & 0x3FFFFFFF) && e - va >= (1ull << 30) && !(*l1 & PTE_VALID)) {
            *l1 = va | a | PTE_VALID; va += 1ull << 30; continue;
        }
        uint64_t *l2t = next_table(l1);
        if (!l2t) return -1;
        uint64_t *l2 = &l2t[(va >> 21) & 511];
        if (!(va & 0x1FFFFF) && e - va >= (1ull << 21) && !(*l2 & PTE_VALID)) {
            *l2 = va | a | PTE_VALID; va += 1ull << 21; continue;
        }
        uint64_t *l3t = next_table(l2);
        if (!l3t) return -1;
        l3t[(va >> 12) & 511] = va | a | PTE_TABLE | PTE_VALID;
        va += 4096;
    }
    return 0;
}

// Where things are. 0 image start, 1 end of code, 2 end of constants, 3 end of RAM the
// kernel may use, 4-5 the peripheral window, 6-7 a second window (0-0 when there is none).
int64_t board_layout(int64_t which) {
    switch (which) {
    case 0: return (int64_t)__text_start;
    case 1: return (int64_t)__text_end;
    case 2: return (int64_t)__rodata_end;
#ifdef BOARD_PI4
    case 3: return 0x3C000000;             // first 960 MB: present on every Pi 4, below the GPU's share
    case 4: return 0xFC000000;             // BCM2711 peripherals, including the GIC at 0xFF84xxxx
    case 5: return 0x100000000;
#else
    case 3: return 0x3C000000;
    case 4: return 0x3F000000;             // BCM2837 peripherals
    case 5: return 0x40000000;
    case 6: return 0x40000000;             // per-core timers and interrupt routing
    case 7: return 0x40200000;
#endif
    default: return 0;
    }
}

// Turn translation and the caches on. From here an access outside the map is a fault,
// and so is a write to code or constants, or a jump into data (WXN).
int64_t board_mmu_on(void) {
    if (mmu_is_on) return -1;
    uint64_t mair = 0xFFull | (0x04ull << 8);           // 0: normal write-back; 1: device nGnRE
    uint64_t tcr = 25ull                                // T0SZ: 39-bit addresses, start at level 1
                 | (1ull << 8) | (1ull << 10)           // table walks: write-back cacheable
                 | (3ull << 12)                         // inner shareable
                 | (1ull << 23)                         // no TTBR1 half yet
                 | (1ull << 32);                        // 36-bit physical addresses
    uint64_t sctlr = 0x30D00800ull                      // the bits that must be one
                   | (1ull << 0) | (1ull << 2) | (1ull << 12)   // MMU, data cache, instruction cache
                   | (1ull << 19);                      // WXN: writable is never executable
    __asm__ volatile("msr mair_el1, %0" : : "r"(mair));
    __asm__ volatile("msr tcr_el1, %0" : : "r"(tcr));
    __asm__ volatile("msr ttbr0_el1, %0" : : "r"((uint64_t)tables[0]));
    __asm__ volatile("isb; tlbi vmalle1; dsb nsh; isb");
    __asm__ volatile("msr sctlr_el1, %0; isb" : : "r"(sctlr));
    mmu_is_on = 1;
    return tables_used;
}

// Raw access to an address, for the shell's fault demonstrations.
int64_t board_peek(int64_t addr) { return *(volatile uint8_t *)addr; }
int64_t board_poke(int64_t addr, int64_t v) { *(volatile uint8_t *)addr = (uint8_t)v; return 0; }

// ---- faults: report on the UART and stop ------------------------------------
static void put_str(const char *s) { while (*s) board_putc(*s++); }
static void put_hex(uint64_t v) {
    put_str("0x");
    for (int i = 60; i >= 0; i -= 4) board_putc("0123456789abcdef"[(v >> i) & 15]);
}
// The fault status code says why the MMU refused: bits 5:2 are the class.
static const char *abort_kind(const char *prefix, uint64_t esr) {
    put_str(prefix);
    switch ((esr >> 2) & 15) {
    case 1:  return "address not mapped";
    case 2:  return "access flag";
    case 3:  return (esr >> 26) == 0x25 && (esr & 0x40) ? "write to read-only memory" : "permission denied";
    default: return "other";
    }
}
void board_fault(uint64_t kind, uint64_t esr, uint64_t elr, uint64_t far) {
    static const char *const what[4] = { "synchronous exception", "irq", "fiq", "serror" };
    put_str("\r\n*** ");
    // cancho's checks (bounds, overflow, ...) end in `udf #0xc11f`
    if ((kind & 3) == 0 && (esr >> 26) == 0 && *(uint32_t *)elr == 0x0000c11f) put_str("cancho trap");
    else if ((kind & 3) == 0 && (esr >> 26) == 0x25) put_str(abort_kind("data abort: ", esr));
    else if ((kind & 3) == 0 && (esr >> 26) == 0x21) put_str(abort_kind("instruction abort: ", esr));
    else put_str(what[kind & 3]);
    put_str(" (vector "); board_putc('0' + kind / 10); board_putc('0' + kind % 10);
    put_str(")\r\n    esr "); put_hex(esr);
    put_str("\r\n    elr "); put_hex(elr);
    put_str("\r\n    far "); put_hex(far);
    put_str("\r\nhalted.\r\n");
}

// ---- the libc cancho's runtime still calls ----------------------------------
extern char __heap_start[];
static char *brk_ptr;
void *malloc(size_t n) {
    if (!brk_ptr) brk_ptr = __heap_start;
    n = (n + 15) & ~(size_t)15;
    void *p = brk_ptr; brk_ptr += n; return p;  // bump allocator; free is a no-op for now
}
void free(void *p) { (void)p; }
void *calloc(size_t a, size_t b) { return malloc(a * b); }  // fresh memory from a zeroed RAM range
void *memset(void *d, int c, size_t n) { unsigned char *p = d; while (n--) *p++ = (unsigned char)c; return d; }
void *memcpy(void *d, const void *s, size_t n) { unsigned char *p = d; const unsigned char *q = s; while (n--) *p++ = *q++; return d; }
void *memmove(void *d, const void *s, size_t n) {
    unsigned char *p = d; const unsigned char *q = s;
    if (p < q) while (n--) *p++ = *q++; else { p += n; q += n; while (n--) *--p = *--q; }
    return d;
}
// one core, one thread: thread-local storage is a single slot
static void *tls_slot;
int pthread_key_create(unsigned *k, void (*d)(void *)) { (void)d; *k = 0; return 0; }
void *pthread_getspecific(unsigned k) { (void)k; return tls_slot; }
int pthread_setspecific(unsigned k, const void *v) { (void)k; tls_slot = (void *)v; return 0; }
void abort(void) { for (;;) __asm__ volatile("wfe"); }
