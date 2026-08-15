CC ?= gcc
CFLAGS ?= -O3 -Wall -Wextra
PREFIX ?= /usr

.PHONY: all clean install package

all: build/roboparty-ws2812

build/roboparty-ws2812: src/ws2812_pwm6.c
	mkdir -p build
	$(CC) $(CFLAGS) -o $@ $< -lm

install: all
	install -D -m 0755 build/roboparty-ws2812 $(DESTDIR)$(PREFIX)/bin/roboparty-ws2812

package:
	dpkg-buildpackage -us -uc -b

clean:
	rm -rf build debian/roboparty-ws2812 debian/.debhelper debian/files debian/debhelper-build-stamp
