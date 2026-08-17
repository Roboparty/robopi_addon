# robopi-addon

[中文说明](README_CN.md)

Add-on toolkit for the RoboPi RK3588S platform: WS2812 strip control and
SIG/key GPIO helpers. It does not depend on `roboparty-base`.

- `robopi-ws2812`: controls 18 daisy-chained WS2812 LEDs through PWM6_M1
- `robopi-sig-key`: SIG rising-edge LED output and key handling

This package does not install or modify the device tree. PWM6_M1 must already
be enabled by the system.

## What's included

- `robopi-ws2812` command-line controller
- `robopi-ws2812` kernel transmitter and `/dev/robopi-ws2812`
- Solid color, flash, chase, rainbow, and demo effects
- `robopi-sig-key` SIG/key GPIO helper
- Native ARM64 build support
- DKMS-based kernel module installation with automatic rebuild on kernel updates
- Debian packaging for installation and removal

## Commands

The program sends GRB frames through `/dev/robopi-ws2812`; the kernel
module generates the validated 800 kHz PWM6_M1 waveform.

```bash
# Turn on with the default dim white color (48, 48, 48)
sudo robopi-ws2812 on

# Turn on with a custom RGB color
sudo robopi-ws2812 on 255 80 0

# Turn off
sudo robopi-ws2812 off

# Solid color: R G B
sudo robopi-ws2812 solid 255 0 0

# Flash: R G B [interval_ms] [count]
# count=0 or omitted: run until Ctrl+C
sudo robopi-ws2812 flash 0 255 0 500 10
sudo robopi-ws2812 flash 0 0 255 200

# Chase: R G B [step_ms] [width]
sudo robopi-ws2812 chase 0 0 255 80 3

# Rainbow: [step_ms]
sudo robopi-ws2812 rainbow 40

# Short demonstration, then turn off
sudo robopi-ws2812 demo

# Show help
robopi-ws2812 --help
```

Continuous effects stop with `Ctrl+C` and turn the strip off before exiting.

## Parameters

| Parameter | Range | Description |
|---|---:|---|
| `R G B` | `0-255` | Red, green, and blue brightness |
| `interval_ms` / `step_ms` | `10-60000` | Animation interval in milliseconds |
| `count` | `0-1000000` | Flash count; `0` means continuous |
| `width` | `1-18` | Number of illuminated chase pixels |

Start with low RGB values such as `16-64` to avoid excessive power draw.

## Build deb package

Build natively on the ARM64 board:

```bash
sudo apt install build-essential debhelper
dpkg-buildpackage -us -uc -b
```

The `.deb` file will be generated in the parent directory.

## Install

The kernel module is built at install time by DKMS against the running kernel,
so the matching headers must be available on the target:

```bash
sudo apt install dkms linux-headers-$(uname -r)
sudo apt install ../robopi-addon_*_arm64.deb
```

DKMS rebuilds `robopi-ws2812` automatically whenever the kernel is updated.
The module is loaded at boot via `/etc/modules-load.d/robopi-ws2812.conf`.

## Uninstall

```bash
sudo apt remove robopi-addon
sudo apt purge robopi-addon
```

The `prerm` script removes the DKMS module so the driver is also uninstalled
from every kernel it was built for.

## Compile-time configuration

The following settings are defined near the top of the kernel module
`src/robopi-ws2812.c` and require a rebuild after modification:

```c
#define LED_COUNT       18
#define PWM6_PHYS       0xfebd0020
#define PERIOD_TICKS    18
#define ZERO_TICKS      6
#define ONE_TICKS       12
```

Validate all timing changes with an oscilloscope.

## SIG rising-edge LED trigger

| Function | GPIO | GPIO character device | Active state |
|---|---|---|---|
| SIG input | GPIO1_D5 | `/dev/gpiochip1`, offset 29 | Rising edge |
| LED output | GPIO0_C2 | `/dev/gpiochip0`, offset 18 | High level |

`robopi-sig-key` starts with the LED off. A low-to-high transition on SIG turns the LED on. A later falling level does not directly turn it off. Exiting the program always turns the LED off.

> SIG must remain within the voltage limits of the GPIO1_D5 IO domain. Never drive SIG directly with 5 V.

### Foreground test

Latch the LED on after a rising edge:

```bash
sudo robopi-sig-key
```

Expected startup and trigger output:

```text
Started: waiting for SIG rising edge; LED is off.
SIG rising edge -> LED on
KEY_PRESSED
```

Press `Ctrl+C` to exit and turn the LED off.

### Timed LED output

Keep the LED on for 1000 ms after each rising edge:

```bash
sudo robopi-sig-key --led-on-ms 1000
```

### Other options

```bash
robopi-sig-key --help
sudo robopi-sig-key --debounce-ms 30
sudo robopi-sig-key --on-press '/opt/my-app/start.sh'
sudo robopi-sig-key --sig-active-low
sudo robopi-sig-key --led-active-low
```

### systemd service

After validating the foreground test, enable the service at boot:

```bash
sudo systemctl enable --now robopi-sig-key.service
journalctl -u robopi-sig-key.service -f
```
