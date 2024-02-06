	.file	"always_inline.c"
	.text
	.section	.rodata
.LC0:
	.string	"abc"
.LC1:
	.string	"def"
	.text
	.globl	main
	.type	main, @function
main:
.LFB1:
	.cfi_startproc
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset 6, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register 6
	subq	$32, %rsp
	movq	$.LC0, -32(%rbp)
	movq	$.LC1, -24(%rbp)
	movl	$1, -16(%rbp)
	leaq	-32(%rbp), %rax
	movq	%rax, -8(%rbp)
	cmpq	$0, -8(%rbp)
	jne	.L2
	movl	$0, %eax
	jmp	.L3
.L2:
	movq	-8(%rbp), %rax
	movl	16(%rax), %eax
	cmpl	$1, %eax
	sete	%al
.L3:
	testb	%al, %al
	je	.L4
	movq	-32(%rbp), %rax
	movq	%rax, %rdi
	call	puts
	jmp	.L5
.L4:
	movq	-24(%rbp), %rax
	movq	%rax, %rdi
	call	puts
.L5:
	movl	$0, %eax
	leave
	.cfi_def_cfa 7, 8
	ret
	.cfi_endproc
.LFE1:
	.size	main, .-main
	.ident	"GCC: (GNU) 8.3.1 20190311 (Red Hat 8.3.1-3)"
	.section	.note.GNU-stack,"",@progbits
