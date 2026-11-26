/* RAM_BASE is where the board's RAM starts: build.sh links the same objects twice, with 0 for a
   Raspberry Pi (kernel8.img) and 0x40000000 for QEMU's virt machine (kernel-virt.elf). */
ENTRY(_start)
SECTIONS {
    . = RAM_BASE + 0x80000;
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
    __bss_end = .;
    /* Eight 4 KB translation tables at an address the kernel can name: the bound of its `tab`
       capability is this range (src/kernel.cho), and the image below it is what `code` holds. */
    ASSERT(. <= RAM_BASE + 0x200000, "the kernel image has grown past 2 MB: move the tables, and the bounds in src/kernel.cho")
    . = RAM_BASE + 0x200000;
    __tables = .;
    . += 8 * 4096;
    /* what cancho's runtime takes its region chunks from: the rest of the RAM the kernel maps */
    /* one page after the tables: its first word is the fault note (board/boot.S, `fault` in src/kernel.cho) */
    __fault_note = .;
    . += 4096;
    /* 64 KB a device reads and writes on its own (`dma` in src/kernel.cho): a network card's queues and packets */
    . = RAM_BASE + 0x210000;
    . += 0x10000;
    __cancho_heap_start = ALIGN(4096);
    __cancho_heap_end = RAM_BASE + 0x3c000000;
    /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) }
}
