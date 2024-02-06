# gcc -o always_inline always_inline.c
gcc -o function.S -S function.c
gcc -o always_inline.S -S  always_inline.c
gcc -o macro.S -S  macro.c
