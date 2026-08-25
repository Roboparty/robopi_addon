# robopi-addon

[中文说明](README_CN.md)

Add-on toolkit for the RoboPi RK3588S platform: WS2812 strip control and
SIG/key GPIO helpers. It does not depend on `roboparty-base`.

- `robopi-ws2812`: controls 12 daisy-chained WS2812B-MINI-V3/W LEDs through PWM6_M1
- `robopi-sig-key`: SIG rising-edge LED output and key handling
- `robopi-ethernet-mac`: derives and applies a stable Ethernet MAC from the RK3588 Chip ID

This package does not install or modify the device tree. PWM6_M1 must already
be enabled by the system.

## What's included

- `robopi-ws2812` command-line controller
- `robopi-ws2812` kernel transmitter and `/dev/robopi-ws2812`
- Solid color, flash, chase, rainbow, and demo effects
- `robopi-sig-key` SIG/key GPIO helper
- Native ARM64 build support
- Prebuilt kernel module for Linux 6.1.99-rt36-rockchip-rk3588
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
| `width` | `1-12` | Number of illuminated chase pixels |

Start with low RGB values such as `16-64` to avoid excessive power draw.

The package enables `robopi-ws2812-white.service`. After the kernel module is
loaded during boot, the service sets all LEDs to steady full white
(`255 255 255`). Stopping the service turns the strip off:

```bash
systemctl status robopi-ws2812-white.service
sudo systemctl stop robopi-ws2812-white.service
sudo systemctl start robopi-ws2812-white.service
```

Full white has the highest power consumption. Make sure the 5 V supply and
wiring can carry the current required by all 12 LEDs.

## Build deb package

The package contains the prebuilt module for its fixed target kernel:

```text
prebuilt/6.1.99-rt36-rockchip-rk3588/robopi-ws2812.ko
```

Build the package on the ARM64 board:

```bash
sudo apt install build-essential debhelper
dpkg-buildpackage -us -uc -b
```

The `.deb` file will be generated in the parent directory.

## Install

The package installs a prebuilt module, so DKMS and kernel headers are not
required on the target:

```bash
sudo apt install ../robopi-addon_*_arm64.deb
```

The module is installed under `/lib/modules/6.1.99-rt36-rockchip-rk3588/extra/`
and loaded at boot via `/etc/modules-load.d/robopi-ws2812.conf`. Rebuild the
`.ko` and publish a new package whenever the target kernel changes.

## Stable Ethernet MAC experiment

`robopi-ethernet-mac` derives a stable, locally administered unicast MAC from
the RK3588 `Serial` field in `/proc/cpuinfo`. The Chip ID is not exposed directly
as the MAC.

The package enables `robopi-ethernet-mac.service`. On the next boot it applies
the derived MAC and requests DHCP again. The service is not started while the
deb is being installed, so installation does not interrupt the current network.
The default interface is configured in `/etc/default/robopi-ethernet-mac`:

```bash
ETHERNET_INTERFACE=enP4p65s0
```

Run the read-only checks from a serial console before the first reboot:

```bash
robopi-ethernet-mac check
robopi-ethernet-mac status
```

The tool stops if the Chip ID is empty, invalid, or all zero. `Derived MAC` and
`Check MAC` must match.

Applying the MAC interrupts Ethernet and requests a new DHCP address, so run it
from a serial console:

```bash
sudo robopi-ethernet-mac apply
```

Pass a different interface name as the second argument when needed:

```bash
sudo robopi-ethernet-mac apply enP4p65s0
```

Restore NetworkManager's permanent-MAC policy with:

```bash
sudo robopi-ethernet-mac restore
```

The tool does not remove DHCP lease files under `/var/lib/NetworkManager`.
Record the Chip ID, derived MAC, and assigned IPv4 address on multiple boards to
verify that each board receives a distinct identity and address.

Inspect the boot service with:

```bash
systemctl status robopi-ethernet-mac.service
journalctl -u robopi-ethernet-mac.service -b
```

## Uninstall

```bash
sudo apt remove robopi-addon
sudo apt purge robopi-addon
```

The removal scripts unload the running module and refresh the target kernel's
module dependency index.

## Compile-time configuration

The following settings are defined near the top of the kernel module
`src/robopi-ws2812.c` and require a rebuild after modification:

```c
#define LED_COUNT       12
#define PWM6_PHYS       0xfebd0020
#define WS2812_PERIOD_NS 1250
#define WS2812_T0H_NS     330
#define WS2812_T1H_NS     650
#define WS2812_RESET_US   300
```

The driver derives PWM register ticks from the actual PWM clock at load time.
At 24 MHz the values are 30/8/16 ticks. Validate timing changes with an
oscilloscope.

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

## FAN_SW fan switch

FAN_SW uses GPIO1_D7 (global GPIO 63). According to the board schematic, the signal is active high: a high level enables `VCC_5V_FAN`, while a low level turns the fan supply off.

```bash
# Turn the fan on
sudo robopi-fan on

# Turn the fan off
sudo robopi-fan off

# Show the current state
robopi-fan status
```

The command uses the GPIO sysfs interface so the selected output remains in effect after the command exits. The package enables `robopi-fan.service`, which turns FAN_SW on automatically at boot. Stopping the service turns the fan off:

```bash
systemctl status robopi-fan.service
sudo systemctl stop robopi-fan.service
sudo systemctl start robopi-fan.service
```
