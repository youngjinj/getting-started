# gcc -o always_inline always_inline.c
gcc -O2 -o if.S -S if.c
gcc -O2 -o trigraph.S -S trigraph.c

gcc -O2 -o if if.c
gcc -O2 -o trigraph trigraph.c
