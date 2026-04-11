ENTRY(_start)
KERNEL_OFFSET = 0xffffffff80000000;
KERNEL_LOAD_ADDR = 0x00100000;

/* x86_64の慣習的な高位アドレスに配置 */
PHDRS {
  text PT_LOAD FILEHDR PHDRS FLAGS(5);
  rodata PT_LOAD FLAGS(4);
  data PT_LOAD FLAGS(6);
}

SECTIONS {
    . = KERNEL_LOAD_ADDR;
    . += KERNEL_OFFSET;

    .text : AT(ADDR(.text) - KERNEL_OFFSET) ALIGN(4K) {
        *(.text .text.*)
    } :text

    .rodata : AT(ADDR(.rodata) - KERNEL_OFFSET) ALIGN(4K) {
        *(.rodata .rodata.*)
        *(.rodata.cst*)
        *(.rodata.str*)
        *(.eh_frame*)
        *(.gcc_except_table*)
    } :rodata

    .data : AT(ADDR(.data) - KERNEL_OFFSET) ALIGN(4K) {
        *(.data .data.*)
        *(.data.rel.ro*)
        *(.got .got.*)
    } :data

    .bss : AT(ADDR(.bss) - KERNEL_OFFSET) ALIGN(4K) {
        *(.bss .bss.*)
        *(COMMON)
    } :data
}
