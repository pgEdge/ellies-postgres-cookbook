# --8<-- [start:deps]
# Build with libpq, using pg_config to find the headers and library.
CFLAGS += -Wall -Wextra -I$(shell pg_config --includedir)
LDFLAGS += -L$(shell pg_config --libdir)
LDLIBS += -lpq

main: main.c
# --8<-- [end:deps]

clean:
	rm -f main

.PHONY: clean
