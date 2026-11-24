ENTRY(_start)
SECTIONS {
    . = 0x80000;
    __text_start = .;
    .text : { KEEP(*(.text.boot)) KEEP(*(.text.vectors)) *(.text .text.*) }
    . = ALIGN(4096);              /* page boundaries: each part gets its own permissions (milestone 3) */
    __text_end = .;
    .rodata : { *(.rodata .rodata.*) }
    . = ALIGN(4096);
    __rodata_end = .;
    .data : { *(.data .data.*) }
    . = ALIGN(16);
    __bss_start = .;
    .bss (NOLOAD) : { *(.bss .bss.* COMMON) }
    . = ALIGN(4096);
    __tables = .;                 /* eight 4 KB translation tables, zeroed with .bss */
    . += 8 * 4096;
    __bss_end = .;
    /* what cancho's runtime takes its region chunks from: the rest of the RAM the kernel maps */
    __cancho_heap_start = ALIGN(4096);
    __cancho_heap_end = 0x3c000000;
    /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) }
}
