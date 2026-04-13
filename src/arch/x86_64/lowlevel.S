.global gdt_flush
.type gdt_flush, @function
gdt_flush:
  mov %si, %ds
  mov %si, %es
  mov %si, %fs
  mov %si, %gs
  mov %si, %ss

  pushq %rdi
  lea 1f(%rip), %rax
  pushq %rax
  lretq
1:
  ret
