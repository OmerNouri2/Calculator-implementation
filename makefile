calc: calc.o
	gcc -m32 -g -Wall -o calc calc.o

calc.o: calc.s
	nasm -f elf calc.s -o calc.o

clean :
	rm calc *.o
