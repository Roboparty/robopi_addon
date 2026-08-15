CC ?= gcc
CFLAGS ?= -O3 -Wall -Wextra
PREFIX ?= /usr
KERNEL_RELEASE ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KERNEL_RELEASE)/build

.PHONY: all clean install package

all: build/roboparty-ws2812 build/robopi-sig-key build/roboparty_ws2812.ko

build/roboparty-ws2812: src/ws2812_pwm6.c
	mkdir -p build
	$(CC) $(CFLAGS) -o $@ $< -lm

build/robopi-sig-key: src/sig_led_key.c
	mkdir -p build
	$(CC) $(CFLAGS) -o $@ $<

build/roboparty_ws2812.ko: kernel/roboparty_ws2812.c kernel/Makefile
	$(MAKE) -C $(KDIR) M=$(CURDIR)/kernel modules
	cp kernel/roboparty_ws2812.ko $@

install: all
	install -D -m 0755 build/roboparty-ws2812 $(DESTDIR)$(PREFIX)/bin/roboparty-ws2812
	install -D -m 0755 build/robopi-sig-key $(DESTDIR)$(PREFIX)/bin/robopi-sig-key
	install -D -m 0644 systemd/robopi-sig-key.service \
		$(DESTDIR)/lib/systemd/system/robopi-sig-key.service
	install -D -m 0644 build/roboparty_ws2812.ko \
		$(DESTDIR)/lib/modules/$(KERNEL_RELEASE)/extra/roboparty_ws2812.ko
	install -D -m 0644 packaging/roboparty-ws2812.modules-load \
		$(DESTDIR)/etc/modules-load.d/roboparty-ws2812.conf

package:
	dpkg-buildpackage -us -uc -b

clean:
	-$(MAKE) -C $(KDIR) M=$(CURDIR)/kernel clean
	rm -rf build debian/roboparty-ws2812 debian/.debhelper debian/files debian/debhelper-build-stamp
