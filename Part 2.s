# Requirement: manager of contiguous memory.
# We have 8 MB * 8 MB split in blocks of 8kb. In this simplified version, we will only remember 1 byte per memory block.
# max 1 file/block.
# every file has a file descriptor (1-255).

.data
	lineSize: .long 1024 # ma
	maxMem: .long 300000 # size of memory > 256 * 1024
	n: .long 0 # number of operations
	op: .long 0 # current operation
	memory: .space 1048576 # 1 MB, simulated memory => 1024 lines of 1kb each

# printing formats:
	cin: .asciz "%ld" # format for scanf
	cout: .asciz "%ld " # format for printf
	nl: .asciz "\n"   # format for syscall with new line
	fdPrint: .asciz "%d: ((%d, %d), (%d, %d))\n"
 # fileDescriptor: (start,end).
	getPrint: .asciz "((%d, %d), (%d, %d))\n"
 # (start,end)
	
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

			cmpl maxMem, %ecx
			jge printMemory_end
			
			xor %eax, %eax
			movb (%esi,%ecx,1), %al # put into the smallest byte of eax.
			
			push %ecx
			push %eax
			call printLong
			pop %eax
			pop %ecx
			
			# note: idiv op (edx, eax) := (edx, eax) / op. edx will have the remainder.
			push %ecx
			xor %edx, %edx
			mov %ecx, %eax
			inc %eax
			idivl lineSize

		
			cmp $0, %edx
			jne printMemory_continue
			
			
			call printNewLine
			
		printMemory_continue:
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
			
	# 8-16 ebp: fd start end
	print_fileFD:
		push %ebp
		movl %esp, %ebp
	
		#end:
		xor %edx, %edx
		mov 16(%ebp), %eax
		idivl lineSize
		push %edx
		push %eax
		
		#start:
		xor %edx, %edx
		mov 12(%ebp), %eax
		idivl lineSize
		push %edx
		push %eax
		
		push 8(%ebp) # file descriptor
		push $fdPrint
		call printf
		pushl $0
		call fflush
		addl $28, %esp
		
		popl %ebp
		ret
	# 8-12 ebp: start end
	print_file_get: #without fd.
		push %ebp
		movl %esp, %ebp
	
		#end:
		xor %edx, %edx
		mov 12(%ebp), %eax
		idivl lineSize
		push %edx
		push %eax
		
		#start:
		xor %edx, %edx
		mov 8(%ebp), %eax
		idivl lineSize
		push %edx
		push %eax
		
		push $getPrint
		call printf
		pushl $0
		call fflush
		addl $24, %esp
		
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
		
			cmp maxMem,%ecx
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

	findNFree: #returns in eax start position of n ( = 8(ebp) ) free blocks in a row
		push %ebp
		mov %esp, %ebp
		
		xor %ecx,%ecx
		push $0 # current emty count in -4(%ebp)
		
		movl lineSize, %eax
		cmp 8(%ebp), %eax
		jl findNFree_fail
		
		findNFree_loop:
		
			cmp maxMem,%ecx
			jge findNFree_fail
			
			
			xor %edx, %edx
			mov %ecx, %eax
			idivl lineSize
			cmp $0, %edx
			
			jne findNFree_loop1
			movl $0, -4(%ebp) # soft reset
		
		findNFree_loop1:
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
	
	# gets parameters: length then fd. returns start, finish in eax,edx.
	ADD_FILE:
		push %ebp
		mov %esp, %ebp
		
		push 8(%ebp) # length
		call findNFree # returns in eax.
		addl $4, %esp
		
		cmp $-1, %eax
		je ADD_fail
		
		push %eax
		
		push 12(%ebp)
		call GET_FILE
		addl $4, %esp
		
		pop %eax
		
		cmp  $-1, %edx
		je ADD_fail # cannot add same fd twice.
			
		ADD_success:
		
			push 12(%ebp) # file descriptor
			push 8(%ebp) # block count
			push %eax # start position
			call addN
			pop %eax
			addl $8, %esp
			
			mov %eax, %edx
			dec %edx
			addl 8(%ebp), %edx
			pop %ebp
			ret
			
		ADD_fail:
			mov $0,%eax
			mov $0, %edx
			pop %ebp
			ret
			
			
	
	ADD:
		push %ebp
		mov %esp, %ebp
		
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
			
			push -8(%ebp) # fd
			push -12(%ebp) # length
			call ADD_FILE
			addl $8, %esp
			
			
		
		ADD_print:
			
			push %edx # end positions
			push %eax # start position
			push -8(%ebp) # fd
			call print_fileFD
			addl $12, %esp

		ADD_loop2:
			popl %ecx
			inc %ecx
			jmp ADD_loop
			
		ADD_end:
		
			addl $12,%esp
			pop %ebp
			ret
			
	# gets fd in 8(%ebp). returns in eax, edx the start and end index.
	GET_FILE:
		push %ebp
		mov %esp, %ebp
	
		push $-1 # start -4(%ebp)
		push $0 # end -8(%ebp)
		
		xor %ecx,%ecx
		GET_loop:
		
			cmp maxMem,%ecx
			jge GET_FILE_exit
			
			mov 8(%ebp), %eax
			cmpb %al, memory(%ecx)
			jne GET_continue
			
			cmpl $-1, -4(%ebp)
			jne GET_loop1
			movl %ecx, -4(%ebp)
		GET_loop1:
			movl %ecx, -8(%ebp)
			
		GET_continue:
			inc %ecx
			jmp GET_loop
			
		GET_FILE_exit:
			movl -4(%ebp), %eax
			movl -8(%ebp), %edx
			addl $8, %esp
			pop %ebp
			ret
		
	GET:
		push %ebp
		mov %esp, %ebp
		push $0 # file descriptor in -4(%ebp)
		
		lea -4(%ebp), %eax
		push %eax
		call readLong
		popl %eax
			
		call GET_FILE
		
		
		GET_tryPrint:
			cmpl $-1, %eax
			jne GET_print
			movl $0, %eax
			movl $0, %edx
			
		GET_print:

			push %edx # end positions
			push %eax # start position
			call print_file_get
			addl $8, %esp
			
		GET_end:
			addl $4, %esp
			pop %ebp
			ret	

	# gets fd to delete in 8(%ebp). Doesn't return value.
	DELETE_FILE:
		push %ebp
		mov %esp, %ebp
		push %edi # callee-saved
		
		
		xor %ecx,%ecx
		lea memory, %edi
		
		DELETE_loop:
			cmp maxMem,%ecx
			jge DELETE_end
			
			xor %eax,%eax
			movb (%edi,%ecx), %al
			
			cmp 8(%ebp), %eax
			jne DELETE_loop1
			movb $0, (%edi,%ecx)
			
		DELETE_loop1:
			inc %ecx
			jmp DELETE_loop
			
		DELETE_end:

			popl %edi
			popl %ebp
			ret

	DELETE:	
		push %ebp
		mov %esp, %ebp
		push $0 # file descriptor to delete in -4(%ebp)
		
		lea -4(%ebp), %eax
		push %eax
		call readLong
		popl %eax
		
		
		call DELETE_FILE
		call printFiles
		addl $4,%esp
		pop %ebp
		ret
			
	/*
	# read requirement wrong. This is more memory efficient (but slower); it doesn't hold the initial order.	
	# it just deletes and readds all the files.
	betterDefrag:
		push %ebp
		mov %esp, %ebp
		
		push $0 # fd
		push $0 # length
		push $0 # last
		
		push %esi # callee-saved
		xor %ecx, %ecx
		lea memory, %esi
		
		betterDefrag_loop:
			cmp maxMem,%ecx
			jge betterDefrag_end
			
			cmpb $0, (%esi,%ecx)
			je betterDefrag_continueLoop # we don't care about spaces
			push %ecx
			
			
			xor %eax, %eax
			movb (%esi,%ecx), %al
			movl %eax, -4(%ebp)
			
			push %eax
			call GET_FILE # gets fd. returns in eax, edx the start and end index.
			
			subl %eax, %edx # edx has length
			inc %edx
			movl %edx, -8(%ebp)
			
			call DELETE_FILE

			push -8(%ebp)
			call ADD_FILE # gets parameters: length then fd. returns start, finsih in eax,edx.
			addl $4, %esp
			movl %edx, -12(%ebp)

			call GET_FILE
			addl $4, %esp

			pop %ecx
			movl -12(%ebp), %edx
			cmp %ecx, %edx
			jle betterDefrag_continueLoop
					
			mov %edx, %ecx # Don't move the same file again. start from the end of it.

		betterDefrag_continueLoop:
			inc %ecx

			jmp betterDefrag_loop
		
	betterDefrag_end:
		call printFiles
		pop %esi
		addl $12, %esp
		pop %ebp
		ret
	*/
	
	DEFRAG:
		push %ebp
		mov %esp, %ebp
		push $-1 # position to move to -4(%ebp)
		push $-1 # file length
		push $-1 # fd
		push %esi # callee-saved
		
		xor %ecx, %ecx
		lea memory, %esi
		
		DEFRAG_loop:
			cmp  maxMem,%ecx
			jge DEFRAG_end
			
			push %ecx
			
			cmpb $0, (%esi,%ecx)
			je DEFRAG_continueLoop # we deliberately do not update left index -4(%ebp)
			
			movl -4(%ebp), %eax
			inc %eax
			movl %eax, -4(%ebp)
			
			cmp %eax, %ecx	
			je DEFRAG_continueLoop # if no free spaces ever found we go to next position
			
			xor %eax, %eax
			movb (%esi,%ecx), %al
			
			cmp -12(%ebp), %eax
			je DEFRAG_move
			
			mov %eax, -12(%ebp)
			
			push %eax
			call GET_FILE# gets fd. returns in eax, edx the start and end index.
			addl $4, %esp
			
			subl %eax, %edx 
			inc %edx # edx now has length of current file.
			movl %edx, -8(%ebp)S
			
			xor %edx, %edx
			movl -4(%ebp), %eax
			idivl lineSize
			movl -8(%ebp), %eax
			addl %edx, %eax
			
			cmp lineSize, %eax
			jle DEFRAG_move
			
			# start from an empty line:
			movl -4(%ebp), %eax
			addl lineSize, %eax
			subl %edx, %eax
			
			movl %eax, -4(%ebp)

		DEFRAG_move:
		
		pop %ecx
			
			movb $0, (%esi,%ecx)
			
			mov -4(%ebp), %eax
			mov -12(%ebp), %edx
			movb %dl, (%esi, %eax)
			
		push %ecx
			
		DEFRAG_continueLoop:
			
			pop %ecx
			inc %ecx
			jmp DEFRAG_loop
			
	DEFRAG_end:
		#call printMemory
		call printFiles
		pop %esi
		addl $12, %esp
		pop %ebp
		ret
	
	CONCRETE:
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
		
		cmp $5, %eax
		je opConcrete
		
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
		opConcrete:
			call CONCRETE
			jmp loop_RunOperations1
		
	loop_RunOperations1:
	
		pop %ecx # reget saved index
		inc %ecx
		
		jmp loop_RunOperations
		
	jmp exit