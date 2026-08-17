# SPDX-License-Identifier: GPL-3.0
# Copyright (C) 2025-2026 fanxiaobinggit
CC ?= gcc
CFLAGS ?= -O3 -Wall -Wextra
PREFIX ?= /usr
KERNEL_RELEASE ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KERNEL_RELEASE)/build
VERSION ?= 1.5.0
DKMS_DIR ?= $(DESTDIR)/usr/src/roboparty-ws2812-$(VERSION)

.PHONY: all clean install package kernel

all: build/roboparty-ws2812 build/robopi-sig-key

build/roboparty-ws2812: src/ws2812_pwm6.c
	mkdir -p build
	$(CC) $(CFLAGS) -o $@ $< -lm

build/robopi-sig-key: src/sig_led_key.c
	mkdir -p build
	$(CC) $(CFLAGS) -o $@ $<

kernel:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/src modules

install: all
	install -D -m 0755 build/roboparty-ws2812 $(DESTDIR)$(PREFIX)/bin/roboparty-ws2812
	install -D -m 0755 build/robopi-sig-key $(DESTDIR)$(PREFIX)/bin/robopi-sig-key
	install -D -m 0644 etc/systemd/system/robopi-sig-key.service \
		$(DESTDIR)/lib/systemd/system/robopi-sig-key.service
	install -D -m 0644 packaging/roboparty-ws2812.modules-load \
		$(DESTDIR)/etc/modules-load.d/roboparty-ws2812.conf
	install -D -m 0644 dkms.conf $(DKMS_DIR)/dkms.conf
	install -D -m 0644 src/Makefile $(DKMS_DIR)/Makefile
	install -D -m 0644 src/roboparty_ws2812.c $(DKMS_DIR)/roboparty_ws2812.c

package:
	dpkg-buildpackage -us -uc -b

clean:
	-$(MAKE) -C $(KDIR) M=$(CURDIR)/src clean
	rm -rf build debian/robopi-addon debian/.debhelper debian/files debian/debhelper-build-stamp
