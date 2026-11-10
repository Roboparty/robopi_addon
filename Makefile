# SPDX-License-Identifier: GPL-3.0
# Copyright (C) 2025-2026 fanxiaobinggit

CC ?= gcc
CFLAGS ?= -O3 -Wall -Wextra
ROBOOS_PREFIX ?= /opt/roboparty

.PHONY: all clean install package

# Small user-space hardware utilities compiled from this repository.
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

# Stage the complete filesystem tree under DESTDIR. During Debian builds,
# DESTDIR is debian/robopi-addon rather than the host system root.
install: all
	install -D -m 0755 scripts/robopi-ethernet-static.sh $(DESTDIR)$(ROBOOS_PREFIX)/bin/robopi-ethernet-static
	install -D -m 0644 etc/systemd/system/robopi-ethernet-static.service $(DESTDIR)/lib/systemd/system/robopi-ethernet-static.service
	# BMS GPIO daemon.
	install -D -m 0755 scripts/robopi-bms-gpio.py $(DESTDIR)$(ROBOOS_PREFIX)/bin/robopi-bms-gpio
	install -D -m 0644 etc/systemd/system/robopi-bms-gpio.service $(DESTDIR)/lib/systemd/system/robopi-bms-gpio.service
	install -D -m 0644 docs/bms-gpio.md $(DESTDIR)/usr/share/doc/robopi-addon/bms-gpio.md

# AIC8800 USB Wi-Fi naming and hotplug selection. Drivers and firmware are in BSP.
	install -D -m 0644 etc/udev/rules.d/70-robopi-usb-wifi-name.rules $(DESTDIR)/etc/udev/rules.d/70-robopi-usb-wifi-name.rules
	install -D -m 0644 etc/udev/rules.d/90-robopi-usb-wifi-select.rules $(DESTDIR)/etc/udev/rules.d/90-robopi-usb-wifi-select.rules
	install -D -m 0644 etc/systemd/system/robopi-wifi-autoselect.service $(DESTDIR)/lib/systemd/system/robopi-wifi-autoselect.service
	mkdir -p $(DESTDIR)$(ROBOOS_PREFIX)/bin $(DESTDIR)/lib/systemd/system

	install -D -m 0755 scripts/robopi-usb-wifi-init.sh $(DESTDIR)$(ROBOOS_PREFIX)/bin/robopi-usb-wifi-init
	install -D -m 0644 etc/systemd/system/robopi-usb-wifi.service $(DESTDIR)/lib/systemd/system/robopi-usb-wifi.service
	install -D -m 0644 etc/modprobe.d/robopi-blacklist-onboard-wifi.conf $(DESTDIR)/etc/modprobe.d/robopi-blacklist-onboard-wifi.conf

	# Keep operator documentation.
	install -D -m 0644 docs/usb-wifi-bundle.md $(DESTDIR)/usr/share/doc/robopi-addon/usb-wifi-bundle.md
	install -D -m 0644 docs/wifi-selection.md $(DESTDIR)/usr/share/doc/robopi-addon/wifi-selection.md

	# Install operator-facing commands under /opt, then expose stable PATH entries.
	install -D -m 0755 scripts/robopi-wifi-select.sh $(DESTDIR)$(ROBOOS_PREFIX)/bin/robopi-wifi-select
	install -D -m 0755 build/robopi-ws2812 $(DESTDIR)$(ROBOOS_PREFIX)/bin/robopi-ws2812
	install -D -m 0755 build/robopi-sig-key $(DESTDIR)$(ROBOOS_PREFIX)/bin/robopi-sig-key
	install -D -m 0755 build/robopi-hw-test $(DESTDIR)$(ROBOOS_PREFIX)/bin/robopi-hw-test
	install -d $(DESTDIR)/usr/bin
	ln -sf $(ROBOOS_PREFIX)/bin/robopi-wifi-select $(DESTDIR)/usr/bin/robopi-wifi-select
	ln -sf $(ROBOOS_PREFIX)/bin/robopi-ws2812 $(DESTDIR)/usr/bin/robopi-ws2812
	ln -sf $(ROBOOS_PREFIX)/bin/robopi-sig-key $(DESTDIR)/usr/bin/robopi-sig-key
	ln -sf $(ROBOOS_PREFIX)/bin/robopi-hw-test $(DESTDIR)/usr/bin/robopi-hw-test

	# Board maintenance commands that are intentionally run by an operator.
	install -D -m 0755 scripts/robopi-ethernet-mac.sh \
		$(DESTDIR)$(ROBOOS_PREFIX)/bin/robopi-ethernet-mac
	install -D -m 0755 scripts/robopi-fan.sh \
		$(DESTDIR)$(ROBOOS_PREFIX)/bin/robopi-fan
	install -D -m 0755 scripts/robopi-pmic-ota.py \
		$(DESTDIR)$(ROBOOS_PREFIX)/bin/robopi-pmic-ota
	install -D -m 0755 scripts/robopi-pmic-monitor.py \
		$(DESTDIR)$(ROBOOS_PREFIX)/bin/robopi-pmic-monitor
	install -D -m 0644 etc/systemd/system/robopi-pmic-monitor.service \
		$(DESTDIR)/lib/systemd/system/robopi-pmic-monitor.service
	install -D -m 0644 etc/default/robopi-pmic-monitor \
		$(DESTDIR)/etc/default/robopi-pmic-monitor
	install -D -m 0644 docs/pmic-pinout-functions.md \
		$(DESTDIR)/usr/share/doc/robopi-addon/pmic-pinout-functions.md
	for file in manifest.json boot.bin ChargeBAT.bin; do \
		install -D -m 0644 firmware/pmic/candidate/stm32f103c8/$$file \
			$(DESTDIR)$(ROBOOS_PREFIX)/share/pmic/candidate/stm32f103c8/$$file; \
	done
	for file in manifest.json boot.bin ChargeBAT_GD32.bin; do \
		install -D -m 0644 firmware/pmic/candidate/gd32f503/$$file \
			$(DESTDIR)$(ROBOOS_PREFIX)/share/pmic/candidate/gd32f503/$$file; \
	done
	ln -sf $(ROBOOS_PREFIX)/bin/robopi-ethernet-mac $(DESTDIR)/usr/bin/robopi-ethernet-mac
	ln -sf $(ROBOOS_PREFIX)/bin/robopi-fan $(DESTDIR)/usr/bin/robopi-fan
	ln -sf $(ROBOOS_PREFIX)/bin/robopi-pmic-ota $(DESTDIR)/usr/bin/robopi-pmic-ota
	ln -sf $(ROBOOS_PREFIX)/bin/robopi-pmic-monitor $(DESTDIR)/usr/bin/robopi-pmic-monitor

	# SIG diagnostic service.
	install -D -m 0644 etc/systemd/system/robopi-sig-key.service \
		$(DESTDIR)/lib/systemd/system/robopi-sig-key.service

	# WS2812 autoload entry for the BSP-provided driver.
	install -D -m 0644 etc/modules-load.d/robopi-ws2812.conf \
		$(DESTDIR)/etc/modules-load.d/robopi-ws2812.conf

	# Remaining board service units. Enable/start policy lives in Debian maintainer scripts.
	install -D -m 0644 etc/systemd/system/robopi-ethernet-mac.service \
		$(DESTDIR)/lib/systemd/system/robopi-ethernet-mac.service
	install -D -m 0644 etc/systemd/system/robopi-hw-test.service \
		$(DESTDIR)/lib/systemd/system/robopi-hw-test.service
	install -D -m 0644 etc/systemd/system/robopi-ws2812-white.service \
		$(DESTDIR)/lib/systemd/system/robopi-ws2812-white.service

	# Administrator-editable runtime defaults.
	install -D -m 0644 etc/default/robopi-ethernet-mac \
		$(DESTDIR)/etc/default/robopi-ethernet-mac

# Convenience wrapper used by developers and CI.
package:
	dpkg-buildpackage -us -uc -b

# Remove generated user-space binaries and Debian staging metadata.
clean:
	rm -rf build debian/robopi-addon debian/.debhelper debian/files debian/debhelper-build-stamp
