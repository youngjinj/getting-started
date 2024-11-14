#!/bin/bash

if [ $# != 3 ]; then
    echo -e \
        "\nUsage  : $0 src_tty_or_file   dst_tty_or_file   pid" \
        "\nExample: $0 /dev/pts/2        /dev/pts/10       3358301" \
        "\nExample: $0 /path/to/old_file /path/to/new_file 3395191"
    exit 1
fi

if ! gdb --version > /dev/null 2>&1; then
    echo "Unable to find gdb."
    exit 1
fi

FD_SRC=$1
FD_DST=$2
FD_PID=$3

echo -e \
"FD_SRC: $FD_SRC" \
"\nFD_DST: $FD_DST" \
"\nFD_PID: $FD_PID"

# Check if FD_DST exists as a symbolic link
if [ ! -L "$FD_DST" ] && [ ! -e "$FD_DST" ]; then
    echo "Source file descriptor $FD_DST does not exist."
    exit 1
fi

(
    # O_RDWR : 0x02 ( 2)
    # O_CREAT: 0x40 (64)
    # O_RDWR | O_CREAT:  0x42 (66)
    # RWX: 0600
    echo "attach $FD_PID"
    echo "set \$fd_open = (int) open(\"$FD_DST\", 66, 0600)"

    # Check if open was successful in gdb
    echo "if (\$fd_open == -1)"
    echo     "printf \"Error: Unable to open destination file: $FD_DST\n\""
    echo     "detach"
    echo     "quit"
    echo "end"

    # Execute dup2 for each matching file descriptor
    for FD_TARGET in $(find /proc/$FD_PID/fd \( -lname "$FD_SRC" -o -lname "$FD_SRC (deleted)" \) -printf '%f\n'); do
        echo "call (int) dup2(\$fd_open, $FD_TARGET)"
        echo "if (\$ == -1)"
        echo     "printf \"Error: dup2 failed for target $FD_TARGET\n\""
        echo "end"
    done

    # Close the file descriptor
    echo "call (int) close(\$fd_open)"
    echo "detach"
    echo "quit"
) | gdb -q -x -
