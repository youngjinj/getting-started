CC = gcc

INCDIR=$(CUBRID)/cci/include
LIBDIR=$(CUBRID)/lib/libcascci.so
BIN = cci_schema_info
OBJ = $(BIN).o
SRC = $(BIN).c
CFLAG = -g

all: $(BIN)

$(BIN): $(OBJ)
	$(CC) $(CFLAG) -o $(BIN) $(OBJ) -ldl

$(OBJ): $(SRC)
	$(CC) $(CFLAG) -c $(SRC) -I$(INCDIR) -lnsl $(LIBDIR) -lpthread

clean:
	rm -rf $(BIN) $(OBJ) 
