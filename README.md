# roboparty-ws2812

[中文说明](README_CN.md)

Standalone WS2812 controller package for the RoboParty RK3588S platform. It
controls 18 daisy-chained LEDs through PWM6_M1 and does not depend on
`roboparty-base`.

This package does not install or modify the device tree. PWM6_M1 must already
be enabled by the system.

## What's included

- `roboparty-ws2812` command-line controller
- `roboparty_ws2812` kernel transmitter and `/dev/roboparty-ws2812`
- Solid color, flash, chase, rainbow, and demo effects
- Native ARM64 and amd64-to-ARM64 cross-build support
- Debian packaging for installation and removal

## Commands

The program sends GRB frames through `/dev/roboparty-ws2812`; the kernel
module generates the validated 800 kHz PWM6_M1 waveform.

```bash
# Turn on with the default dim white color (48, 48, 48)
sudo roboparty-ws2812 on

# Turn on with a custom RGB color
sudo roboparty-ws2812 on 255 80 0

# Turn off
sudo roboparty-ws2812 off

# Solid color: R G B
sudo roboparty-ws2812 solid 255 0 0

# Flash: R G B [interval_ms] [count]
# count=0 or omitted: run until Ctrl+C
sudo roboparty-ws2812 flash 0 255 0 500 10
sudo roboparty-ws2812 flash 0 0 255 200

# Chase: R G B [step_ms] [width]
sudo roboparty-ws2812 chase 0 0 255 80 3

# Rainbow: [step_ms]
sudo roboparty-ws2812 rainbow 40

# Short demonstration, then turn off
sudo roboparty-ws2812 demo

# Show help
roboparty-ws2812 --help
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
sudo apt install build-essential debhelper linux-headers-$(uname -r)
chmod +x build-deb.sh
./build-deb.sh
```

Cross-build on an amd64 Ubuntu computer:

```bash
sudo apt install build-essential debhelper crossbuild-essential-arm64
chmod +x build-deb.sh
./build-deb.sh
```

The `.deb` file will be generated in the parent directory.

## Install

```bash
sudo apt install ../roboparty-ws2812_*_arm64.deb
```

## Uninstall

```bash
sudo apt remove roboparty-ws2812
sudo apt purge roboparty-ws2812
```

## Compile-time configuration

The following settings are defined near the top of `src/ws2812_pwm6.c` and
require a rebuild after modification:

```c
#define LED_COUNT       18
#define PWM6_ADDR       0xfebd0020u
#define PWMCHIP_DIR     "/sys/class/pwm/pwmchip2"

static uint32_t period_ticks = 30;
static uint32_t zero_ticks = 8;
static uint32_t one_ticks = 19;
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
