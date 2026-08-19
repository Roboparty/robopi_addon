# SPDX-License-Identifier: GPL-3.0
# Copyright (C) 2025-2026 fanxiaobinggit
CC ?= gcc
CFLAGS ?= -O3 -Wall -Wextra
KERNEL_RELEASE ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KERNEL_RELEASE)/build
VERSION ?= $(shell dpkg-parsechangelog -S Version 2>/dev/null | cut -d'-' -f1)
DKMS_DIR ?= $(DESTDIR)/usr/src/robopi-ws2812-$(VERSION)

.PHONY: all clean install package kernel

all: build/robopi-ws2812 build/robopi-sig-key

build/robopi-ws2812: src/ws2812_pwm6.c
	mkdir -p build
	$(CC) $(CFLAGS) -o $@ $< -lm

build/robopi-sig-key: src/sig_led_key.c
	mkdir -p build
	$(CC) $(CFLAGS) -o $@ $<

kernel:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/src modules

install: all
	install -D -m 0755 build/robopi-ws2812 $(DESTDIR)/opt/roboparty/bin/robopi-ws2812
	install -D -m 0755 build/robopi-sig-key $(DESTDIR)/opt/roboparty/bin/robopi-sig-key
	install -d $(DESTDIR)/usr/bin
	ln -sf /opt/roboparty/bin/robopi-ws2812 $(DESTDIR)/usr/bin/robopi-ws2812
	ln -sf /opt/roboparty/bin/robopi-sig-key $(DESTDIR)/usr/bin/robopi-sig-key
	install -D -m 0644 etc/systemd/system/robopi-sig-key.service \
		$(DESTDIR)/lib/systemd/system/robopi-sig-key.service
	install -D -m 0644 etc/modules-load.d/robopi-ws2812.conf \
		$(DESTDIR)/etc/modules-load.d/robopi-ws2812.conf
	install -D -m 0644 etc/systemd/system/hpm-reset.service \
		$(DESTDIR)/lib/systemd/system/hpm-reset.service
	install -D -m 0644 etc/systemd/system/wifi-reset.service \
		$(DESTDIR)/lib/systemd/system/wifi-reset.service
	install -D -m 0644 etc/systemd/system/hpm-autoflash.service \
		$(DESTDIR)/lib/systemd/system/hpm-autoflash.service
	install -D -m 0755 scripts/reset_hpm.sh \
		$(DESTDIR)/opt/roboparty/bin/reset_hpm.sh
	install -D -m 0755 scripts/autoflash_hpm.sh \
		$(DESTDIR)/opt/roboparty/bin/autoflash_hpm.sh
	install -D -m 0755 scripts/wifi-reconnect.sh \
		$(DESTDIR)/opt/roboparty/bin/wifi-reconnect.sh
	install -D -m 0755 scripts/flash_hpm.sh \
		$(DESTDIR)/opt/roboparty/bin/flash_hpm.sh
	install -D -m 0755 scripts/hpmtool.py \
		$(DESTDIR)/opt/roboparty/bin/hpmtool
	install -D -m 0644 firmware/ethercanfd_v1.0.3-20260818.bin \
		$(DESTDIR)/opt/roboparty/lib/firmware/ethercanfd_v1.0.3-20260818.bin
	install -D -m 0644 etc/default/hpm-reset \
		$(DESTDIR)/etc/default/hpm-reset
	install -D -m 0644 etc/default/wifi-reset \
		$(DESTDIR)/etc/default/wifi-reset
	mkdir -p $(DKMS_DIR)
	sed 's/@VERSION@/$(VERSION)/g' dkms.conf.in > $(DKMS_DIR)/dkms.conf
	chmod 0644 $(DKMS_DIR)/dkms.conf
	install -D -m 0644 src/Makefile $(DKMS_DIR)/Makefile
	install -D -m 0644 src/robopi-ws2812.c $(DKMS_DIR)/robopi-ws2812.c

package:
	dpkg-buildpackage -us -uc -b

clean:
	-$(MAKE) -C $(KDIR) M=$(CURDIR)/src clean
	rm -rf build debian/robopi-addon debian/.debhelper debian/files debian/debhelper-build-stamp
