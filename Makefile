# SPDX-License-Identifier: GPL-3.0
# Copyright (C) 2025-2026 fanxiaobinggit
CC ?= gcc
CFLAGS ?= -O3 -Wall -Wextra
TARGET_KERNEL_RELEASE ?= 6.1.99-rt36-rockchip-rk3588
KDIR ?= /lib/modules/$(TARGET_KERNEL_RELEASE)/build
PREBUILT_MODULE ?= prebuilt/$(TARGET_KERNEL_RELEASE)/robopi-ws2812.ko

.PHONY: all clean install package kernel check-prebuilt-module

all: build/robopi-ws2812 build/robopi-sig-key build/robopi-hw-test

build/robopi-ws2812: src/ws2812_pwm6.c
	mkdir -p build
	$(CC) $(CFLAGS) -o $@ $< -lm

build/robopi-sig-key: src/sig_led_key.c
	mkdir -p build
	$(CC) $(CFLAGS) -o $@ $<

build/robopi-hw-test: src/hw_test.c
	mkdir -p build
	$(CC) $(CFLAGS) -o $@ $<

kernel:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/src modules

check-prebuilt-module:
	@test -f $(PREBUILT_MODULE) || { \
		echo "Missing prebuilt module: $(PREBUILT_MODULE)" >&2; \
		echo "Build it against the exact $(TARGET_KERNEL_RELEASE) kernel headers first." >&2; \
		exit 1; \
	}

install: all check-prebuilt-module
	install -D -m 0755 build/robopi-ws2812 $(DESTDIR)/opt/roboparty/bin/robopi-ws2812
	install -D -m 0755 build/robopi-sig-key $(DESTDIR)/opt/roboparty/bin/robopi-sig-key
	install -D -m 0755 build/robopi-hw-test $(DESTDIR)/opt/roboparty/bin/robopi-hw-test
	install -d $(DESTDIR)/usr/bin
	ln -sf /opt/roboparty/bin/robopi-ws2812 $(DESTDIR)/usr/bin/robopi-ws2812
	ln -sf /opt/roboparty/bin/robopi-sig-key $(DESTDIR)/usr/bin/robopi-sig-key
	ln -sf /opt/roboparty/bin/robopi-hw-test $(DESTDIR)/usr/bin/robopi-hw-test
	install -D -m 0755 scripts/robopi-ethernet-mac.sh \
		$(DESTDIR)/opt/roboparty/bin/robopi-ethernet-mac
	install -D -m 0755 scripts/robopi-fan.sh \
		$(DESTDIR)/opt/roboparty/bin/robopi-fan
	ln -sf /opt/roboparty/bin/robopi-ethernet-mac $(DESTDIR)/usr/bin/robopi-ethernet-mac
	ln -sf /opt/roboparty/bin/robopi-fan $(DESTDIR)/usr/bin/robopi-fan
	install -D -m 0644 etc/systemd/system/robopi-sig-key.service \
		$(DESTDIR)/lib/systemd/system/robopi-sig-key.service
	install -D -m 0644 etc/modules-load.d/robopi-ws2812.conf \
		$(DESTDIR)/etc/modules-load.d/robopi-ws2812.conf
	install -D -m 0644 $(PREBUILT_MODULE) \
		$(DESTDIR)/lib/modules/$(TARGET_KERNEL_RELEASE)/extra/robopi-ws2812.ko
	install -D -m 0644 etc/systemd/system/hpm-reset.service \
		$(DESTDIR)/lib/systemd/system/hpm-reset.service
	install -D -m 0644 etc/systemd/system/wifi-reset.service \
		$(DESTDIR)/lib/systemd/system/wifi-reset.service
	install -D -m 0644 etc/systemd/system/robopi-ethernet-mac.service \
		$(DESTDIR)/lib/systemd/system/robopi-ethernet-mac.service
	install -D -m 0644 etc/systemd/system/hpm-autoflash.service \
		$(DESTDIR)/lib/systemd/system/hpm-autoflash.service
	install -D -m 0644 etc/systemd/system/robopi-hw-test.service \
		$(DESTDIR)/lib/systemd/system/robopi-hw-test.service
	install -D -m 0644 etc/systemd/system/robopi-fan.service \
		$(DESTDIR)/lib/systemd/system/robopi-fan.service
	install -D -m 0644 etc/systemd/system/robopi-ws2812-white.service \
		$(DESTDIR)/lib/systemd/system/robopi-ws2812-white.service
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
	install -D -m 0644 etc/default/robopi-ethernet-mac \
		$(DESTDIR)/etc/default/robopi-ethernet-mac
package:
	dpkg-buildpackage -us -uc -b

clean:
	-$(MAKE) -C $(KDIR) M=$(CURDIR)/src clean
	rm -rf build debian/robopi-addon debian/.debhelper debian/files debian/debhelper-build-stamp
