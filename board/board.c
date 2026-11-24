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
    while (r32(UART_FR) & (1u << 4)) {}       // RX FIFO empty
    return (int64_t)(r32(UART_DR) & 0xFF);
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
