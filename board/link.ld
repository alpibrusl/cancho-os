ENTRY(_start)
SECTIONS {
    . = 0x80000;
    .text : { KEEP(*(.text.boot)) *(.text .text.*) }
    .rodata : { *(.rodata .rodata.*) }
    .data : { *(.data .data.*) }
    . = ALIGN(16);
    __bss_start = .;
    .bss (NOLOAD) : { *(.bss .bss.* COMMON) }
    . = ALIGN(16);
    __bss_end = .;
    __heap_start = ALIGN(4096);
}
