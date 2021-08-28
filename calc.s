%macro fprintf_macro 3
	pushad

	push %3
	push %2
	push dword [%1]

	call fprintf
	add esp, 12

	popad
%endmacro

%macro fprintf_macro_new_line 2
	pushad

	push %2
	push dword [%1]

	call fprintf
	add esp, 8

	popad
%endmacro

%define BUFFER_SIZE 82

%define LINK_SIZE 5

section	.rodata			; we define (global) read-only variables in .rodata section
	stack_error: db "Error: Operand Stack Overflow", 10, 0	; stack overflow error
	arguments_error: db "Error: Insufficient Number of Arguments on Stack", 10, 0	; stack arguments error
	format_decimal: db "%d", 0	; format decimal
	format_string: db "%s", 0	; format string
	format_octal: db "%o", 0	; format octal
	calc_string: db "calc: ", 0
	format_new_line: db 10, 0
	debug_mode_on_read_number: db "Debug Mode: the number that was read from the user is: %s", 0	; stack overflow error
	debug_mode_on_push_to_operand_stack: db "Debug Mode: the result pushed onto the operand stack is:", 0	; stack overflow error
	

section .data
	debug_mode: dd 0 		;initiliazied debug_mode to 0 --> means no debug
	arg_stack_size: dd 5	; for stack size	
	counter: dd 0
	carry: dd 0		; carry = 0 there is no carry, otherwise, carry = 1
	remove_next: dd 0	; remove_next = 0 the next link is not NULL, otherwise, next link = NULL
	bytes_counter: dd 0
	op_counter: dd 0	; count successful and unsuccessful operations
	

section .bss			
	buffer: resb BUFFER_SIZE	; 80+2 for '\n' and '\0'
	stack_arg_pointer: resd 1
	stack_arg_base: resd 1
	
section .text
  align 16
  global main
  extern printf
  extern fprintf 
  extern fflush
  extern malloc 
  extern calloc 
  extern free 
  extern getchar 
  extern fgets 
  extern stdout
  extern stdin
  extern stderr

main:
	push ebp
	mov ebp, esp

	mov esi, [ebp + 12]         ; esi = char **argv
	add esi, 4 

	call args_loop

	call allocate_stack

	call myCalc

	.end_main:
	fprintf_macro stdout, format_octal, dword[op_counter] ; print both successful and unsuccessful operations
	fprintf_macro_new_line stdout, format_new_line
	pop ebp
	ret

myCalc:

	.loop_myCalc:
		fprintf_macro stdout, format_string, calc_string

		call get_input

		cmp byte [buffer], 'q'
		je .end_myClac

		call check_input
	
		jmp .loop_myCalc

	.end_myClac:
		ret

args_loop: 		;going through args in argv untill null
		mov ebx, dword [esi]    	; eax = argv[i]
		cmp ebx, 0              	; Null pointer?
		je .end_args_loop           ; Yes -> end of loop

		cmp byte [ebx], '-'
		jne .number

		mov dword [debug_mode], 1
		jmp .next_arg

	.number:
		call convert_octal_to_decimal
		mov dword [arg_stack_size], eax

	.next_arg:
		add esi, 4
		jmp args_loop                     
	.end_args_loop:
		ret

convert_octal_to_decimal:
		; ebx = pointer to octal string
		xor eax, eax
	.loop:
		movzx ecx, byte [ebx]	; ecx = current char in string 

		cmp ecx, 0				; check ecx is Null
		je .end_loop

		sub ecx, '0'			; get num value
		shl eax, 3
		add eax, ecx

		inc ebx
		jmp .loop
	.end_loop:
		ret

allocate_stack:
		mov ebx, dword [arg_stack_size]
		shl ebx, 2

		push ebx
		call malloc
		add esp, 4

		; now eax = pointer to malloced stack
		mov dword [stack_arg_base], eax
		mov dword [stack_arg_pointer], eax

	.end_allocate_stack:
		ret

get_input: 			
	push dword [stdin]
	push BUFFER_SIZE
	push buffer
	call fgets
	add esp, 12
	
	ret		

check_input:
	inc dword [op_counter]
	cmp byte [buffer], '+'
	je plus
	cmp byte [buffer], 'p'
	je print
	cmp byte [buffer], 'n'
	je count_bytes
	cmp byte [buffer], '&'
	je bitwise_and
	cmp byte [buffer], 'd'
	je duplicate
	
	; else its a number
	dec dword [op_counter]
	
	cmp dword[debug_mode], 1 	; check is debug_mode is ON
	jne .continue
	fprintf_macro stderr, debug_mode_on_read_number, buffer

	.continue:
		call create_list		;make a list of a number and push it to the operand stack
		ret

create_list:	; create linkedlist to represent a number and push it to the operand stack
		mov edx, 0			; last link
		mov ecx, buffer
	.loop:
		cmp byte [ecx], 10		;check if we got '\n' (it was said we may assume each number is in seperate line)
		je .end_create_list

		push ecx
		push edx

		push LINK_SIZE
		call malloc		;returned value is in eax (pointer from malloc)
		add esp, 4

		pop edx
		pop ecx

		; eax = address of new link

		mov bl, byte [ecx]			;add 'next' byte from ecx to eax link.data
		sub bl, '0'

		mov byte [eax], bl
		mov dword [eax + 1], edx	;make 'next' to point on previous link
		inc ecx
		mov edx, eax
		jmp .loop

	.end_create_list:
		call _push	 ;push the linkedlist to the operand stack - eax hold the head of the linkedlist
		call set_for_remove_padding 	; remove padding of '0' from the linkedlist
		ret

set_for_remove_padding:		; assuming eax hold the head of the linkedlist
	cmp dword [eax + 1] , 0 	; check if there is a next link (if not-only 1 digit)
	je .end_without_padding

	push eax ; backup eax which point to the first link in the linkedlist

	mov eax, dword [eax + 1]	; move to the 'next' link in the  linkList

	call remove_padding

	cmp eax, 0	; check if eax which point to the second link in the linkedlist = NULL 
	jne .second_link_not_null

	pop eax 	; eax point to the first ink in the linkedlist
	mov dword [eax + 1], 0  	; set eax.next to NULL
	jmp .end_without_padding

	.second_link_not_null:
		cmp dword [remove_next], 1 	; we did not find a non zero msb --> link.data = '0'
		je .back_to_head_of_list

		call free_list		; eax point to a '0' linkedlist
		pop eax
		mov dword [eax + 1], 0  	; set eax.next to NULL
		jmp .end_without_padding

	.back_to_head_of_list:
		pop eax 	; eax point to the first ink in the linkedlist

	.end_without_padding:
		mov dword [remove_next], 0  ;turn OFF the 'remove_next' flag
		ret

_push:
	mov ebx, dword [counter]	; counter count the args in operand stack
	cmp ebx, dword [arg_stack_size]
	jl .has_space_in_stack

	; print error message in case not enough space in stack
	fprintf_macro stdout, format_string, stack_error
	jmp .end_push

	.has_space_in_stack:
	mov ebx, dword [stack_arg_pointer]	; ebx = address of stack pointer
	mov dword [ebx], eax	; eax = first link of linked list to push
	
	cmp dword[debug_mode], 1 	; check is debug_mode is ON
	jne .continue
	fprintf_macro_new_line stderr, debug_mode_on_push_to_operand_stack ; macro of print with 2 agrs
	call print_debud_mode_ON
	
	.continue:
		add dword [stack_arg_pointer], 4
		inc dword [counter]

		.end_push:
		ret

_pop:
	mov ebx, dword [counter]	; counter count the args in operand stack
	cmp ebx, 0
	je .empty_stack

	mov ebx, dword [stack_arg_pointer]	; ebx = address of stack pointer
	sub ebx, 4
	mov eax, dword [ebx]

	sub dword [stack_arg_pointer], 4
	dec dword [counter]
	jmp .end_pop

	.empty_stack:	; print error message in case the stack is empty
	fprintf_macro stdout, format_string, arguments_error
	mov eax, 0

	.end_pop:
	ret

print_debud_mode_ON:
		cmp eax, 0		; chack if eax is null
		je .end_print_debug
		
		call print_rec_debug	
		fprintf_macro_new_line stderr, format_new_line 	; print new line
		fprintf_macro_new_line stderr, format_new_line 	; print new line
	
	.end_print_debug:
		ret

print_rec_debug:	;recursion for printing starting from the end of the linkedlist
		cmp eax, 0	; check if eax = NULL (check if the link is NULL)
		jne .continue
		ret

	.continue:
		push eax	; save the link before entering a new 'frame'
		mov eax, dword [eax + 1]	; eax = to the next link in linkList
		call print_rec_debug
		pop eax		; return the previous link
	
		movzx ebx, byte[eax]	; move with padding of '0'
		fprintf_macro stderr, format_decimal, ebx
		ret

print:
		call _pop		; returned value from stack is in eax
		cmp eax, 0		; chack if eax is null
		je .end_print
		call print_rec	
		fprintf_macro_new_line stdout, format_new_line 	; print new line
	.end_print:
		ret

print_rec:		;recursion for printing starting from the end of the linkedlist
		cmp eax, 0	; check if eax = NULL (check if the link is NULL)
		jne .continue
		ret

	.continue:
		push eax	; save the link before entering a new 'frame'
		mov eax, dword [eax + 1]	; eax = to the next link in linkList
		call print_rec
		pop eax		; return the previous link
	
		movzx ebx, byte[eax]	; move with padding of '0'
		fprintf_macro stdout, format_decimal, ebx
		ret

duplicate:
	call _pop	; returned value from stack is in eax
	call _push
	call _push
	ret

plus:
		call _pop 	; returned value from stack is in eax
		cmp eax, 0		; chack if eax in null
		je .end_plus
		mov ecx, eax	; first operand is in ecx
		
		call _pop 	; returned value from stack is in eax
		cmp eax, 0		; chack if eax in null
		je .sec_operand_NULL
		mov edx, eax	; second operand is in edx

		push edx
		push ecx

		push LINK_SIZE	; create new line
		call malloc		; returned value is in eax (pointer from malloc)
		add esp, 4
		
		pop ecx
		pop edx

		push eax
		
	.loop:
		cmp ecx, 0	; check if ecx = NULL (check if the link is NULL)
		je .add_second_operand
		mov bl, byte [ecx]
		add byte [eax], bl
		mov ecx, dword [ecx + 1]	; eax = to the next link in linkList

		.add_second_operand:
			cmp edx, 0	; check if eax = NULL (check if the link is NULL)
			je .end_loop
			mov bl, byte [edx]
			add byte [eax], bl
			mov edx, dword [edx + 1]	; eax = to the next link in linkList

			cmp byte [eax], 8		; there is carry	
			jl .continue			; there is no carry - can continue

			sub byte[eax], 8		; handle carry
			inc dword [carry]		; turn ON the carry 'flag'

		.continue:
			mov ebx, eax	; ebx now point to the previous link
			push ebx
			push ecx
			push edx

			push LINK_SIZE	; create new line
			call malloc		; returned value is in eax (pointer from malloc)
			add esp, 4
			
			pop edx
			pop ecx
			pop ebx

			mov dword [ebx + 1], eax	; make 'next' of the previous link to the new link
			cmp dword[carry], 1
			jne .loop
			inc byte[eax]
			mov dword[carry], 0		; reset curry flag for next iteration
			
			jmp .loop

	.end_loop:	
		cmp ecx, 0		; check if ecx is null - both operand are null
		jne .loop

		cmp byte[eax], 0 	
		jne .no_carry
		mov dword [ebx + 1], 0
		push eax
		call free	; free the new allocation of unused link
		add esp, 4
	
	.no_carry:	
		pop eax			; restore eax -> head of the linkedList
		call _push 		; insert the new linkedlist to the argiments stack
		
	.end_plus:
		ret
	
	.sec_operand_NULL:
		mov eax, ecx	
		call _push		; return the stack to its previous state
		ret
	
bitwise_and:
	call _pop 	; returned value from stack is in eax
	cmp eax, 0		; chack if eax in null
	je .end_bitwise_and
	mov ecx, eax	; first operand is in ecx
	
	call _pop 	; returned value from stack is in eax
	cmp eax, 0		; chack if eax in null
	je .sec_operand_NULL
	mov edx, eax	; second operand is in edx

	push edx
	push ecx

	push LINK_SIZE	; create new line
	call malloc		; returned value is in eax (pointer from malloc)
	add esp, 4
	
	pop ecx
	pop edx

	push eax	; backup the head of the list before calling to another function
	push ebx 

	.loop:
		xor ebx, ebx
		cmp ecx, 0	; check if ecx = NULL (check if the link is NULL)
		je .end_loop
		mov bl, byte [ecx]
		mov ecx, dword [ecx + 1]	; eax = to the next link in linkList

		.add_second_operand:
			cmp edx, 0	; check if eax = NULL (check if the link is NULL)
			je .end_loop
			mov bh, byte [edx]
			mov edx, dword [edx + 1]	; eax = to the next link in linkList

			and bh, bl
			mov byte [eax], bh

			pop ebx
		
		.continue:
			mov ebx, eax	; ebx now point to the previous link
			push ebx
			push ecx
			push edx

			push LINK_SIZE	; create new line
			call malloc		; returned value is in eax (pointer from malloc)
			add esp, 4
			
			pop edx
			pop ecx
			pop ebx

			mov dword [ebx + 1], eax	; make 'next' of the previous link to the new link
			push ebx
			jmp .loop

	.end_loop:	; we always add another link in the loop so we need to delete it in the end
		pop ebx 

		mov dword [ebx + 1], 0  	; set next to be NULL
		push eax
		call free	; free the new and last allocation of unused link
		add esp, 4

		pop eax		; returned value is in eax ->point to the head of the link
		
		push eax	; backup the head of the list before calling to another function
		call set_for_remove_padding 	; remove padding of '0' from the linkedlist
		pop eax		; restore eax which is the head of the list
		
		call _push	; return the last linkList to the stack & still eax point to the last linkList
	
	.end_bitwise_and:
		ret

	.sec_operand_NULL:
		mov eax, ecx	
		call _push		; return the stack to its previous state
		ret
	
remove_padding:	
		cmp eax, 0	; check if eax = NULL 
		jne .continue
		ret

	.continue:
		push eax	; save the link before entering a new 'frame'
		mov eax, dword [eax + 1]	; eax = to the next link in linkList
		call remove_padding
		pop eax		; return the previous link

		cmp dword [remove_next], 1
		jne .check_curr_link_is_zero
		jmp .end_rec

	.check_curr_link_is_zero:	
		; in case we did not found yet a non zero link from the end
		cmp byte [eax], 0		; check if eax.data = '0'
		jne .new_msb_not_zero	; arrived to the first non zero link from the end of the linkedlist
		ret


	.new_msb_not_zero:
		mov dword [remove_next], 1  ;turn ON the 'remove_next' flag
		push eax			; backup eax which point to the last non zero link
		mov eax, dword [eax + 1] 	; eax point to a linkedlist of '0'
		call free_list
		pop eax
		mov dword [eax + 1], 0  	; set next to be NULL
		ret

	.end_rec:	
		ret 

count_bytes:
		call _pop 	; returned value from stack is in eax
		cmp eax, 0		; chack if eax in null
		je .end_count_bytes_null
	.loop:
		cmp dword [eax + 1], 0	; check if eax.next is NULL (check eax is the MSB)
		je .msb

		add dword[bytes_counter], 3	; increase the number of bits by 3
		mov eax, dword [eax + 1] 	; continue to next link in linkedList
		jmp .loop

	.msb:
		cmp byte [eax], 4	; check if eax.data = '4'
		jl .count_bytes_from_bits	;; the number is less than '4', therefor its include 1 or 2 '0' which can be removed
		
		add dword[bytes_counter], 3	; increase the number of bits by 3	

	.count_bytes_from_bits:  ; counting in decimal
		mov eax, dword [bytes_counter]
		
		mov edx, 0
		mov edi, 8
		div edi		;the register eax contains the quotient and edx contains the remainder
	
		cmp edx, 0	; check if there is reminder from the devision
		je .finish_count_bytes 	; no reminder

		add eax , 1	; add 1 more byte to the counter (round up)
	
	.finish_count_bytes:	; convert the number of bytes from decimal to octal
		mov edx, 0
		mov edi, 8
		div edi		;the register eax contains the quotient and edx contains the remainder

		mov ecx, eax	; ecx is the quotient of the devision

		push edx	; backup reminder from the devision
		push ecx	; backup quotient from the devision

		push LINK_SIZE	; create new link 
		call malloc		; returned value is in eax (pointer from malloc)
		add esp, 4
		
		pop ecx
		pop edx

	
		mov byte[eax] , dl		; eax.data = reminder from the devision
	
		cmp ecx, 0	; check if there is quotient from the devision 
		jne .quotient
		mov dword [eax+1] , 0	; set eax.next = NULL (only 1 link)
		jmp .end_count_bytes
	
	
	.quotient:
		mov edx, eax	; move the allocation of the new link to edx

		push edx	; backup a link of the reminder from the devision
		push ecx	; backup quotient from the devision

		push LINK_SIZE	; create new line
		call malloc		; returned value is in eax (pointer from malloc)
		add esp, 4
		
		pop ecx
		pop edx

		mov byte[eax], cl	; eax.data = the quotient from the devision
		mov dword[edx+1], eax	; edx.next = eax which point to the quotient from the devision
		mov dword[eax+1], 0	; eax.next = NULL

		mov eax, edx	; move the head of the list to eax

	.end_count_bytes:
		call _push
		mov dword[bytes_counter], 0
		ret

	.end_count_bytes_null:
		ret

free_list:	; assuming eax hold the head of the linkedlist
		cmp eax, 0	; check if eax = NULL (check if the link is NULL)
		jne .continue
		ret

	.continue:
		push eax	; save the link before entering a new 'frame'
		mov eax, dword [eax + 1]	; eax = to the next link in linkList
		call free_list
		pop eax		; return the previous link

		push eax
		call free	; free the last allocation of the linkedlist
		add esp, 4
		ret







	