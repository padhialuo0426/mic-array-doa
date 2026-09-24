/* Section layout shared by both A9 programs; mirrors the Vitis 2025.2
 * standalone linker script: vectors first at the region origin, 16 KiB
 * aligned MMU table, 8 KiB heap and system stack, 1-2 KiB mode stacks. */
_STACK_SIZE = DEFINED(_STACK_SIZE) ? _STACK_SIZE : 0x2000;
_HEAP_SIZE = DEFINED(_HEAP_SIZE) ? _HEAP_SIZE : 0x2000;
_ABORT_STACK_SIZE = 1024;
_SUPERVISOR_STACK_SIZE = 2048;
_IRQ_STACK_SIZE = 1024;
_FIQ_STACK_SIZE = 1024;
_UNDEF_STACK_SIZE = 1024;

ENTRY(_vector_table)

SECTIONS
{
.text : {
   KEEP (*(.vectors))
   *(.boot)
   *(.text)
   *(.text.*)
   *(.gnu.linkonce.t.*)
   *(.plt)
   *(.gnu_warning)
   *(.gcc_execpt_table)
   *(.glue_7)
   *(.glue_7t)
   *(.vfp11_veneer)
   *(.ARM.extab)
   *(.gnu.linkonce.armextab.*)
} > DDR

.init : { KEEP (*(.init)) } > DDR
.fini : { KEEP (*(.fini)) } > DDR

.rodata : {
   __rodata_start = .;
   *(.rodata)
   *(.rodata.*)
   *(.gnu.linkonce.r.*)
   __rodata_end = .;
} > DDR

.rodata1 : { *(.rodata1) } > DDR
.sdata2 : { __sdata2_start = .; *(.sdata2) *(.sdata2.*) *(.gnu.linkonce.s2.*) __sdata2_end = .; } > DDR
.sbss2 : { __sbss2_start = .; *(.sbss2) *(.sbss2.*) *(.gnu.linkonce.sb2.*) __sbss2_end = .; } > DDR

.data : {
   __data_start = .;
   *(.data)
   *(.data.*)
   *(.gnu.linkonce.d.*)
   *(.jcr)
   *(.got)
   *(.got.plt)
   __data_end = .;
} > DDR

.data1 : { *(.data1) } > DDR
.got : { *(.got) } > DDR
.eh_frame : { *(.eh_frame) } > DDR

.mmu_tbl (ALIGN(16384)) : {
   __mmu_tbl_start = .;
   *(.mmu_tbl)
   __mmu_tbl_end = .;
} > DDR

.ARM.exidx : {
   __exidx_start = .;
   *(.ARM.exidx*)
   *(.gnu.linkonce.armexidix.*.*)
   __exidx_end = .;
} > DDR

.preinit_array : { __preinit_array_start = .; KEEP (*(SORT(.preinit_array.*))) KEEP (*(.preinit_array)) __preinit_array_end = .; } > DDR
.init_array : { __init_array_start = .; KEEP (*(SORT(.init_array.*))) KEEP (*(.init_array)) __init_array_end = .; } > DDR
.fini_array : { __fini_array_start = .; KEEP (*(SORT(.fini_array.*))) KEEP (*(.fini_array)) __fini_array_end = .; } > DDR

.sdata : { __sdata_start = .; *(.sdata) *(.sdata.*) *(.gnu.linkonce.s.*) __sdata_end = .; } > DDR
.sbss (NOLOAD) : { __sbss_start = .; *(.sbss) *(.sbss.*) *(.gnu.linkonce.sb.*) __sbss_end = .; } > DDR
.tdata : { __tdata_start = .; *(.tdata) *(.tdata.*) *(.gnu.linkonce.td.*) __tdata_end = .; } > DDR
.tbss : { __tbss_start = .; *(.tbss) *(.tbss.*) *(.gnu.linkonce.tb.*) __tbss_end = .; } > DDR

.bss (NOLOAD) : {
   . = ALIGN(8);
   __bss_start = .;
   *(.bss)
   *(.bss.*)
   *(.gnu.linkonce.b.*)
   *(COMMON)
   . = ALIGN(8);
   __bss_end = .;
} > DDR

_SDA_BASE_ = __sdata_start + ((__sbss_end - __sdata_start) / 2 );
_SDA2_BASE_ = __sdata2_start + ((__sbss2_end - __sdata2_start) / 2 );

.heap (NOLOAD) : {
   . = ALIGN(16);
   _heap = .;
   HeapBase = .;
   _heap_start = .;
   . += _HEAP_SIZE;
   _heap_end = .;
   HeapLimit = .;
} > DDR

.stack (NOLOAD) : {
   . = ALIGN(16);
   _stack_end = .;
   . += _STACK_SIZE;
   . = ALIGN(16);
   _stack = .;
   __stack = _stack;
   . = ALIGN(16);
   _irq_stack_end = .;
   . += _IRQ_STACK_SIZE;
   . = ALIGN(16);
   __irq_stack = .;
   _supervisor_stack_end = .;
   . += _SUPERVISOR_STACK_SIZE;
   . = ALIGN(16);
   __supervisor_stack = .;
   _abort_stack_end = .;
   . += _ABORT_STACK_SIZE;
   . = ALIGN(16);
   __abort_stack = .;
   _fiq_stack_end = .;
   . += _FIQ_STACK_SIZE;
   . = ALIGN(16);
   __fiq_stack = .;
   _undef_stack_end = .;
   . += _UNDEF_STACK_SIZE;
   . = ALIGN(16);
   __undef_stack = .;
} > DDR

_end = .;
end = .;
}
