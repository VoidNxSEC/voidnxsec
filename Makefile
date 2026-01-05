CC := gcc
CFLAGS := -Wall -Wextra -O2 -std=c11
LDFLAGS := -lncurses
TARGET := voidnx-tui
SOURCES := voidnx-tui.c
OBJECTS := $(SOURCES:.c=.o)

all: $(TARGET)

$(TARGET): $(OBJECTS)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) -c $<

install: $(TARGET)
	cp $(TARGET) /usr/local/bin/
	chmod +x /usr/local/bin/$(TARGET)
	@echo "Installed to /usr/local/bin/$(TARGET)"

clean:
	rm -f $(OBJECTS) $(TARGET)

help:
	@echo "Void Fortress TUI Makefile"
	@echo "  make       - Build TUI"
	@echo "  make install - Install to /usr/local/bin"
	@echo "  make clean - Remove build artifacts"

.PHONY: all install clean help
