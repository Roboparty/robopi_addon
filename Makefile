# SPDX-License-Identifier: GPL-3.0
# Copyright (C) 2025-2026 fanxiaobinggit

# Build settings. A package must contain modules built for exactly one kernel.
CC ?= gcc
CFLAGS ?= -O3 -Wall -Wextra
TARGET_KERNEL_RELEASE := 6.18.51-current-rockchip64
KDIR ?= /lib/modules/$(TARGET_KERNEL_RELEASE)/build
PREBUILT_MODULE ?= prebuilt/$(TARGET_KERNEL_RELEASE)/robopi-ws2812.ko

.PHONY: all clean install package kernel check-prebuilt-module check-prebuilt-wifi

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

# Optional developer target; Debian packages normally use the prebuilt module.
kernel:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/src modules

# Fail packaging early instead of producing a deb with missing/mismatched modules.
check-prebuilt-module:
	@test -f $(PREBUILT_MODULE) || { \
		echo "Missing prebuilt module: $(PREBUILT_MODULE)" >&2; \
		echo "Build it against the exact $(TARGET_KERNEL_RELEASE) kernel headers first." >&2; \
		exit 1; \
	}

check-prebuilt-wifi:
	sh scripts/check-prebuilt-wifi.sh $(TARGET_KERNEL_RELEASE)

# Stage the complete filesystem tree under DESTDIR. During Debian builds,
# DESTDIR is debian/robopi-addon rather than the host system root.
install: all check-prebuilt-module check-prebuilt-wifi
	install -D -m 0755 scripts/robopi-ethernet-static.sh $(DESTDIR)/opt/roboparty/bin/robopi-ethernet-static
	install -D -m 0644 etc/systemd/system/robopi-ethernet-static.service $(DESTDIR)/lib/systemd/system/robopi-ethernet-static.service
	# BMS GPIO daemon and opt-in USB-CAN capture/analysis tools.
	install -D -m 0755 scripts/robopi-bms-gpio.py $(DESTDIR)/opt/roboparty/bin/robopi-bms-gpio
	install -D -m 0755 scripts/analyze_ethercan_pcap.py $(DESTDIR)/opt/roboparty/bin/analyze-ethercan-pcap
	install -D -m 0755 scripts/usbcan-capture.sh $(DESTDIR)/opt/roboparty/bin/usbcan-capture
	install -D -m 0755 scripts/usbcan-debug-snapshot.sh $(DESTDIR)/opt/roboparty/bin/usbcan-debug-snapshot
	install -D -m 0755 scripts/hpm-log-capture.sh $(DESTDIR)/opt/roboparty/bin/hpm-log-capture
	install -D -m 0644 etc/systemd/system/robopi-bms-gpio.service $(DESTDIR)/lib/systemd/system/robopi-bms-gpio.service
	install -D -m 0644 etc/systemd/system/usbcan-capture.service $(DESTDIR)/lib/systemd/system/usbcan-capture.service
	install -D -m 0644 etc/systemd/system/hpm-log-capture.service $(DESTDIR)/lib/systemd/system/hpm-log-capture.service
	install -D -m 0644 etc/default/usbcan-capture $(DESTDIR)/etc/default/usbcan-capture
	install -D -m 0644 etc/default/hpm-log-capture $(DESTDIR)/etc/default/hpm-log-capture
	install -D -m 0644 docs/bms-gpio.md $(DESTDIR)/usr/share/doc/robopi-addon/bms-gpio.md
	install -D -m 0644 docs/log.md $(DESTDIR)/usr/share/doc/robopi-addon/log.md
	install -D -m 0644 docs/usbcan-dump.md $(DESTDIR)/usr/share/doc/robopi-addon/usbcan-dump.md

	# AIC8800 USB Wi-Fi naming, hotplug selection, kernel modules, and firmware.
	install -D -m 0644 etc/udev/rules.d/70-robopi-usb-wifi-name.rules $(DESTDIR)/etc/udev/rules.d/70-robopi-usb-wifi-name.rules
	install -D -m 0644 etc/udev/rules.d/90-robopi-usb-wifi-select.rules $(DESTDIR)/etc/udev/rules.d/90-robopi-usb-wifi-select.rules
	install -D -m 0644 etc/systemd/system/robopi-wifi-autoselect.service $(DESTDIR)/lib/systemd/system/robopi-wifi-autoselect.service
	install -d $(DESTDIR)/lib/modules/$(TARGET_KERNEL_RELEASE)/kernel/drivers/net/wireless/aic8800
	install -m 0644 prebuilt/$(TARGET_KERNEL_RELEASE)/aic_load_fw.ko prebuilt/$(TARGET_KERNEL_RELEASE)/aic8800_fdrv.ko $(DESTDIR)/lib/modules/$(TARGET_KERNEL_RELEASE)/kernel/drivers/net/wireless/aic8800/
	mkdir -p build/aic-vendor
	unzip -oq prebuilt/UGREEN_AIC-AX300_LinuxDriver_V1.6.zip 'aic8800_linux_drvier/fw/*' -d build/aic-vendor
	install -d $(DESTDIR)/lib/firmware/aic8800DC
	install -m 0644 build/aic-vendor/aic8800_linux_drvier/fw/aic8800DC/* $(DESTDIR)/lib/firmware/aic8800DC/
	install -D -m 0644 etc/udev/rules.d/aic.rules $(DESTDIR)/etc/udev/rules.d/aic.rules
	mkdir -p $(DESTDIR)/opt/roboparty/bin $(DESTDIR)/lib/systemd/system

	install -D -m 0755 scripts/robopi-usb-wifi-init.sh $(DESTDIR)/opt/roboparty/bin/robopi-usb-wifi-init
	install -D -m 0644 etc/systemd/system/robopi-usb-wifi.service $(DESTDIR)/lib/systemd/system/robopi-usb-wifi.service
	install -D -m 0644 etc/modules-load.d/robopi-aic-wifi.conf $(DESTDIR)/etc/modules-load.d/robopi-aic-wifi.conf
	install -D -m 0644 etc/modprobe.d/robopi-blacklist-onboard-wifi.conf $(DESTDIR)/etc/modprobe.d/robopi-blacklist-onboard-wifi.conf

	# Keep operator documentation and the original vendor archive for traceability.
	install -D -m 0644 docs/usb-wifi-bundle.md $(DESTDIR)/usr/share/doc/robopi-addon/usb-wifi-bundle.md
	install -D -m 0644 prebuilt/UGREEN_AIC-AX300_LinuxDriver_V1.6.zip $(DESTDIR)/usr/share/doc/robopi-addon/vendor/UGREEN_AIC-AX300_LinuxDriver_V1.6.zip
	install -D -m 0644 docs/wifi-selection.md $(DESTDIR)/usr/share/doc/robopi-addon/wifi-selection.md

	# Install operator-facing commands under /opt, then expose stable PATH entries.
	install -D -m 0755 scripts/robopi-wifi-select.sh $(DESTDIR)/opt/roboparty/bin/robopi-wifi-select
	install -D -m 0755 build/robopi-ws2812 $(DESTDIR)/opt/roboparty/bin/robopi-ws2812
	install -D -m 0755 build/robopi-sig-key $(DESTDIR)/opt/roboparty/bin/robopi-sig-key
	install -D -m 0755 build/robopi-hw-test $(DESTDIR)/opt/roboparty/bin/robopi-hw-test
	install -d $(DESTDIR)/usr/bin
	ln -sf /opt/roboparty/bin/robopi-wifi-select $(DESTDIR)/usr/bin/robopi-wifi-select
	ln -sf /opt/roboparty/bin/robopi-ws2812 $(DESTDIR)/usr/bin/robopi-ws2812
	ln -sf /opt/roboparty/bin/robopi-sig-key $(DESTDIR)/usr/bin/robopi-sig-key
	ln -sf /opt/roboparty/bin/robopi-hw-test $(DESTDIR)/usr/bin/robopi-hw-test
	ln -sf /opt/roboparty/bin/analyze-ethercan-pcap $(DESTDIR)/usr/bin/analyze-ethercan-pcap
	ln -sf /opt/roboparty/bin/usbcan-debug-snapshot $(DESTDIR)/usr/bin/usbcan-debug-snapshot

	# Board maintenance commands that are intentionally run by an operator.
	install -D -m 0755 scripts/robopi-ethernet-mac.sh \
		$(DESTDIR)/opt/roboparty/bin/robopi-ethernet-mac
	install -D -m 0755 scripts/robopi-fan.sh \
		$(DESTDIR)/opt/roboparty/bin/robopi-fan
	install -D -m 0755 scripts/robopi-gpio0-c2-drive.sh \
		$(DESTDIR)/opt/roboparty/bin/robopi-gpio0-c2-drive
	ln -sf /opt/roboparty/bin/robopi-ethernet-mac $(DESTDIR)/usr/bin/robopi-ethernet-mac
	ln -sf /opt/roboparty/bin/robopi-fan $(DESTDIR)/usr/bin/robopi-fan
	ln -sf /opt/roboparty/bin/robopi-gpio0-c2-drive $(DESTDIR)/usr/bin/robopi-gpio0-c2-drive

	# SIG diagnostic service, then WS2812 autoload configuration and kernel module.
	install -D -m 0644 etc/systemd/system/robopi-sig-key.service \
		$(DESTDIR)/lib/systemd/system/robopi-sig-key.service
	install -D -m 0644 etc/modules-load.d/robopi-ws2812.conf \
		$(DESTDIR)/etc/modules-load.d/robopi-ws2812.conf
	install -D -m 0644 $(PREBUILT_MODULE) \
		$(DESTDIR)/lib/modules/$(TARGET_KERNEL_RELEASE)/extra/robopi-ws2812.ko

	# Remaining board service units. Enable/start policy lives in Debian maintainer scripts.
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
	install -D -m 0755 scripts/robopi-uart-bridge.py \
		$(DESTDIR)/opt/roboparty/bin/robopi-uart-bridge
	install -D -m 0644 etc/systemd/system/robopi-uart-bridge.service \
		$(DESTDIR)/lib/systemd/system/robopi-uart-bridge.service
	install -D -m 0644 etc/default/robopi-uart-bridge \
		$(DESTDIR)/etc/default/robopi-uart-bridge

	# HPM firmware maintenance and Wi-Fi recovery helpers used by systemd services.
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
	install -D -m 0644 firmware/ethercanfd_v1.0.5-20260829.bin \
		$(DESTDIR)/opt/roboparty/lib/firmware/ethercanfd_v1.0.5-20260829.bin

	# Administrator-editable runtime defaults.
	install -D -m 0644 etc/default/hpm-reset \
		$(DESTDIR)/etc/default/hpm-reset
	install -D -m 0644 etc/default/wifi-reset \
		$(DESTDIR)/etc/default/wifi-reset
	install -D -m 0644 etc/default/robopi-ethernet-mac \
		$(DESTDIR)/etc/default/robopi-ethernet-mac

	# Optional source patch for systems that need maximum GPIO0_C2 drive strength.
	install -D -m 0644 patches/0001-rk3588s-robopi2-gpio0-c2-max-drive.patch \
		$(DESTDIR)/usr/share/robopi-addon/patches/0001-rk3588s-robopi2-gpio0-c2-max-drive.patch

# Convenience wrapper used by developers and CI.
package:
	dpkg-buildpackage -us -uc -b

# Remove generated user-space binaries and Debian staging metadata.
clean:
	-$(MAKE) -C $(KDIR) M=$(CURDIR)/src clean
	rm -rf build debian/robopi-addon debian/.debhelper debian/files debian/debhelper-build-stamp
