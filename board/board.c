// Not hardware: the handful of libc symbols cancho's hosted runtime still reaches for.
// docs/issues/03 (a freestanding runtime) deletes this file, and with it the last C.
#include <stdint.h>
#include <stddef.h>

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
