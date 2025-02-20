# Requirement: manager of contiguous memory.
# We have 8 MB split in blocks of 8kb. In this simplified version, we will only remember 1 byte per memory block, totaling 1kb memory.
# max 1 file/block.
# every file has a file descriptor (1-255).
.data
	 memMax: .long 1024 # max size of memory
	n: .long 0 # number of operations
	op: .long 0 # current operation
	memory: .space 1024 # 1 kb, simulated memory
# printing formats:
	cin: .asciz "%ld" # format for scanf
	cout: .asciz "%ld " # format for printf
	nl: .asciz "\n"   # format for syscall with new line
	fdPrint: .asciz "%d: (%d, %d)\n" # fileDescriptor: (start,end).
	getPrint: .asciz "(%d, %d)\n" # (start,end)
.text
# helper functions:
	readLong:
		push 4(%esp)
		push $cin
		call scanf
		addl $8, %esp
		ret
	printLong:
		push 4(%esp)
		push $cout
		call printf
		pushl $0
		call fflush
		add $12,%esp
		ret
	printNewLine: 
		push %ebx # callee-saved
		mov $4, %eax 
		mov $1, %ebx 
		mov $nl, %ecx 
		mov $2, %edx  
		int $0x80 # syscall
		pop %ebx
		ret
	exit:
		mov $1, %eax
		xor %ebx, %ebx
		int $0x80
# logic:
	printMemory:
		push %esi # callee-saved
		xor %ecx, %ecx
		lea memory, %esi
		loop_printMemory:
			cmpl  memMax, %ecx
			jge printMemory_end
			xor %eax, %eax
			movb (%esi,%ecx,1), %al # put into the smallest byte of eax.
			push %ecx
			push %eax
			call printLong
			pop %eax
			pop %ecx
			inc %ecx
			jmp loop_printMemory
		printMemory_end:
			call printNewLine
			pop %esi
			ret
	# 4-12esp: fd start end
	tryPrint_fileFD: 
		cmpl $-1, 8(%esp)
		jne print_fileFD
		ret
	print_fileFD:
		push %ebp
		movl %esp, %ebp
		push 16(%ebp) # end positions
		push 12(%ebp) # start position
		push 8(%ebp) # file descriptor
		push $fdPrint
		call printf
		pushl $0
		call fflush
		addl $20, %esp
		popl %ebp
		ret
	printFiles:
		push %ebp
		mov %esp, %ebp
		push $-1 # start -4(%ebp)
		push $-1 # end -8(%ebp)
		push $-1 # current fd -12(%ebp)
		push %esi # callee-saved
		lea memory, %esi
		xor %ecx, %ecx
		printFiles_loop:
			cmp  memMax,%ecx
			jge printFiles_end
			xor %eax, %eax
			movb (%esi,%ecx), %al
			cmp -12(%ebp), %eax
			je printFiles_continueFile
			push %eax
			push %ecx
			push -8(%ebp)
			push -4(%ebp)
			push -12(%ebp)
			call tryPrint_fileFD
			addl $12, %esp
			pop %ecx
			pop %eax
			cmp $0, %eax
			je printFiles_endFile
			movl %eax, -12(%ebp)
			movl %ecx, -4(%ebp)
			movl %ecx, -8(%ebp)
			jmp printFiles_continue
		printFiles_endFile:
			movl $-1, -12(%ebp)
			movl $-1, -8(%ebp)
			movl $-1, -4(%ebp)
			jmp printFiles_continue
		printFiles_continueFile:
			movl %ecx, -8(%ebp) #update end
		printFiles_continue:
			inc %ecx
			jmp printFiles_loop
		printFiles_end:
			push -8(%ebp)
			push -4(%ebp)
			push -12(%ebp)
			call tryPrint_fileFD
			addl $12, %esp
			pop %esi
			addl $12, %esp
			pop %ebp
			ret
	findNFree: #returns in eax start position of n ( = 4(ebp) ) free blocks in a row
		push %ebp
		mov %esp, %ebp
		xor %ecx,%ecx
		push $0 # current emty count in -4(%ebp)
		findNFree_loop:
			cmp  memMax,%ecx
			jge findNFree_fail
			cmpb $0, memory(%ecx)
			jne findNFree_reset
			mov -4(%ebp), %eax
			inc %eax
			mov %eax, -4(%ebp)
			cmpl 8(%ebp), %eax
			je findNFree_finish
			findNFree_continue:
				inc %ecx
				jmp findNFree_loop
			findNFree_reset:
				movl $0, -4(%ebp)
				jmp findNFree_continue
		findNFree_fail:
			mov $-1,%eax
			addl $4, %esp
			pop %ebp
			ret
		findNFree_finish:
			sub 8(%ebp),%ecx
			mov %ecx, %eax
			inc %eax
			addl $4, %esp
			pop %ebp
		ret	
	addN: # 8-16 ebp:  start, length, fd
		push %ebp
		mov %esp, %ebp
		mov 8(%ebp), %eax
		mov 16(%ebp), %edx
		xor %ecx, %ecx
		addN_loop:
			cmp 12(%ebp), %ecx
			jge addN_end
			movb %dl, memory(%eax,%ecx)
			inc %ecx
			jmp addN_loop
	addN_end:
		popl %ebp
		ret
	ADD:
		push $0 # nr of read files in -4(%ebp)
		push $0 # file descriptor in -8(%ebp)
		push $0 # file size in -12(%ebp)
		lea -4(%ebp), %eax
		push %eax
		call readLong
		popl %eax
		xor %ecx, %ecx
		ADD_loop:
			mov -4(%ebp), %eax
			cmp %eax, %ecx
			jge ADD_end
			push %ecx
			# read file descriptor
			lea -8(%ebp), %eax
			push %eax
			call readLong
			popl %eax
			# read file size
			lea -12(%ebp), %eax
			push %eax
			call readLong
			popl %eax
			# transform into amount of blocks
			mov -12(%ebp), %eax
			movl $0, -12(%ebp)
			movl %eax, %edx
			sar $3, %eax
			sal $3, %eax # removed remainder
			subl %eax, %edx
			cmp $0, %edx # edx is fileSize MOD 8
			je ADD_loop1
		ADD_incompleteBlock:
			movl $1, -12(%ebp) # if we don't have multiple of 8kb, we add a non full block.
		ADD_loop1:
			sar $3, %eax
			addl %eax, -12(%ebp)
			push -12(%ebp)
			call findNFree # returns in eax.
			popl %ecx
			cmp $-1,%eax
			je ADD_fail_print
			push -8(%ebp) # file descriptor
			push -12(%ebp) # block count
			push %eax # start position
			call addN
			pop %eax
			addl $8, %esp
			jmp ADD_print
		ADD_fail_print:
			mov $0,%eax
			movl $1,-12(%ebp)
		ADD_print:
			mov %eax, %edx
			addl -12(%ebp), %edx
			dec %edx
			push %edx # end positions
			push %eax # start position
			push -8(%ebp) # fd
			call print_fileFD
			addl $12, %esp
		ADD_loop2:
			pop %ecx
			inc %ecx
			jmp ADD_loop
		ADD_end:
			addl $12,%esp
			ret
	GET:
		push %ebp
		mov %esp, %ebp
		push $0 # file descriptor in -4(%ebp)
		lea -4(%ebp), %eax
		push %eax
		call readLong
		popl %eax
		xor %ecx,%ecx
		push $-1 # start -8(%ebp)
		push $0 # end -12(%ebp)
		GET_loop:
			cmp  memMax,%ecx
			jge GET_tryPrint
			mov -4(%ebp), %eax
			cmpb %al, memory(%ecx)
			jne GET_continue
			cmpl $-1, -8(%ebp)
			jne GET_loop1
			movl %ecx, -8(%ebp)
		GET_loop1:
			movl %ecx, -12(%ebp)
		GET_continue:
			inc %ecx
			jmp GET_loop
		GET_tryPrint:
			cmpl $-1, -8(%ebp)
			jne GET_print
			movl $0, -8(%ebp)
			movl $0, -12(%ebp)
		GET_print:
			push -12(%ebp) # end positions
			push -8(%ebp) # start position
			push $getPrint
			call printf
			pushl $0
			call fflush
			addl $16, %esp
		GET_end:
			addl $12, %esp
			pop %ebp
			ret	
	DELETE:	
		push %ebp
		mov %esp, %ebp
		push $0 # file descriptor to delete in -4(%ebp)
		push %edi # callee-saved
		lea -4(%ebp), %eax
		push %eax
		call readLong
		popl %eax
		xor %ecx,%ecx
		lea memory, %edi
		DELETE_loop:
			cmp  memMax,%ecx
			jge DELETE_end
			xor %eax,%eax
			movb (%edi,%ecx), %al
			cmp -4(%ebp), %eax
			jne DELETE_loop1
			movb $0, (%edi,%ecx)
		DELETE_loop1:
			inc %ecx
			jmp DELETE_loop
		DELETE_end:
			call printFiles
			popl %edi
			addl $4, %esp
			popl %ebp
			ret
	DEFRAG:
		push %ebp
		mov %esp, %ebp
		push $-1 # position to move to -4(%ebp)
		push %esi # callee-saved
		xor %ecx, %ecx
		lea memory, %esi
		DEFRAG_loop:
			cmp  memMax,%ecx
			jge DEFRAG_end
			cmpb $0, (%esi,%ecx)
			je DEFRAG_continueLoop # we deliberately do not update left index -4(%ebp)
			movl -4(%ebp), %eax
			inc %eax
			movl %eax, -4(%ebp)
			cmp %eax, %ecx
			je DEFRAG_continueLoop # if no free spaces found we go to next position
			xor %edx, %edx
			movb (%esi, %ecx), %dl
			movb %dl, (%esi, %eax)
			movb $0, (%esi,%ecx)
		DEFRAG_continueLoop:
			inc %ecx
			jmp DEFRAG_loop
	DEFRAG_end:
		call printFiles
		pop %esi
		addl $4, %esp
		pop %ebp
		ret
.global main
	main:
	pushl $n
	call readLong
	pop %eax
	xor %ecx,%ecx
	loop_RunOperations:
		cmp n,%ecx
		jge exit
		push %ecx # saving the caller-saved
		pushl $op
		call readLong
		pop %eax
		mov op, %eax
		cmp $1, %eax
		je opAdd
		cmp $2, %eax
		je opGet
		cmp $3, %eax
		je opDelete
		cmp $4, %eax
		je opDefrag
		jmp loop_RunOperations1
		opAdd:
			call ADD
			jmp loop_RunOperations1
		opGet:
			call GET
			jmp loop_RunOperations1
		opDelete:
			call DELETE
			jmp loop_RunOperations1
		opDefrag:
			call DEFRAG
			jmp loop_RunOperations1
	loop_RunOperations1:
		pop %ecx # reget saved index
		inc %ecx
		jmp loop_RunOperations
	jmp exit