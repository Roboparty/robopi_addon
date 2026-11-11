# robopi-addon

[中文说明](README_CN.md)

`robopi-addon` is the board support package for RoboPi RK3588S (ARM64). It can
be installed independently and does not require `roboparty-base`. It installs
Wi-Fi, BMS GPIO, fan, and WS2812 board support tools under `${ROBOOS_PREFIX:-/opt/roboparty}`.
EtherCAN maintenance and field diagnostics are provided separately by
`roboparty-analyze`. Frequently used addon commands are also exposed through
`/usr/bin`.

The package configures and enables several systemd services. Keep a serial
console or an alternative wired connection available during the first
installation or upgrade, because Wi-Fi selection and device restarts may
interrupt the current SSH session.

## Quick reference

USB-CAN, HPM, CAN, and synchronized diagnostic commands below require the
separate `roboparty-analyze` package.

| Task | Command or documentation |
|---|---|
| Inspect or select Wi-Fi | `robopi-wifi-select status` / [Wi-Fi selection](docs/wifi-selection.md) |
| Control the WS2812 strip | `sudo robopi-ws2812 --help` |
| Control the fan | `sudo robopi-fan on\|off\|status` |
| Check the Ethernet MAC | `robopi-ethernet-mac check` |
| Review BMS GPIO behavior | [BMS GPIO](docs/bms-gpio.md) |
| Capture a USB-CAN fault snapshot | `sudo usbcan-debug-snapshot` / `/usr/share/doc/roboparty-analyze/usbcan-dump.md.gz` |
| Analyze a USB-CAN capture | `analyze-ethercan-pcap <pcap-file-or-directory>` |
| Restart all four CAN links | `sudo robopi-can-restart` |
| Capture four CAN links as ASC | `sudo robopi-can-capture /home/robo/can.asc` |
| Capture synchronized seven-dimensional diagnostics | `sudo robopi-sixd-capture /home/robo/robopi-logs/session` |
| Analyze a synchronized session | `robopi-sixd-analyze /home/robo/robopi-logs/session` |
| Export session ZIP with SHA-256 | `robopi-sixd-export /home/robo/robopi-logs/session` |
| List failed services | `systemctl --failed` |

## PMIC firmware candidates

The current pin mapping, feature inventory, and verification status are in the
[PMIC pinout and function list](docs/pmic-pinout-functions.md) (Chinese).

The package installs STM32F103C8 and GD32F503VET6 bootloader/application
bundles from the
[PMIC v0.1.13 engineering release](https://github.com/Roboparty/roboparty_pmic/releases/tag/v0.1.13)
for STM32F103C8; the GD32F503 candidate remains at v0.1.11. Each bundle
has a SHA-256 manifest under `${ROBOOS_PREFIX:-/opt/roboparty}/share/pmic/candidate/`.
The earlier v0.1.8 GD32 asset had the wrong version string and is superseded.
The `-left` firmware version suffix is a historical build name, not a second MCU.
These are not production-qualified firmware. Installing this
package never flashes the PMIC.

Use `robopi-pmic-ota inspect --port /dev/ttyUSB0` for read-only UID and
firmware-version queries on the PMIC USART1 port (PA9/PA10, RK3588 UART7 `/dev/ttyS7`; 115200 8N1). The STM32
candidate uses internal Flash serial OTA with a resident bootloader. Its first
installation requires SWD: `boot.bin` at `0x08000000`, `ChargeBAT.bin` at
`0x08001000`.
The v0.1.13 STM32 build moves the host/control UART to USART1 on PA9/PA10.
The 0.1.8-left notes below describe the earlier USART3 wiring.

In `0.1.8-left`, PB4 is unused and the BMS driver/thread and USART1 are not
built or initialized. The charge thread automatically enables PB3 EN and PA3
ICTRL after three valid ADC samples when the input is 16-32 V, CH224 reports
adapter current, and no fault is latched. Independent cutoff protection in
the battery pack is required. Saved settings and host `CHG_EN`/`ICTRL` writes
cannot bypass the automatic conditions. Legacy `BAT_INST` returns 0 and
`BAT_SOC`/`BAT_SOH` return `BMS_DISABLED;`.
The same charge logic in `0.1.5-left` was tested: EN stayed off at 5 V and PB3
went high at 20 V, with no battery pack attached. The previous `0.1.8-left`
image was flashed and verified on the test board. PA5 is green while charging
below 54 V output; PA4 is red while charging at or above 54 V. PA6 is high for PA1 at 1.39-1.50 V,
and PA7 for 1.21-<1.39 V; host R/G writes cannot override these outputs.
The 54 V lamp threshold does not stop charging. External voltage/current and loaded charge
termination have not been measured. SWD tests confirmed the physical colors
of PA4-PA7; the 20 V open-circuit case lit only the charge red LED.
PA1 voltage windows and the loaded green state remain untested on hardware.

Validate either installed image pair without opening a serial device:

```bash
robopi-pmic-ota verify-bundle \
  --bundle ${ROBOOS_PREFIX:-/opt/roboparty}/share/pmic/candidate/stm32f103c8/manifest.json
robopi-pmic-ota verify-bundle \
  --bundle ${ROBOOS_PREFIX:-/opt/roboparty}/share/pmic/candidate/gd32f503/manifest.json
```

The packaged `0.1.10` STM32 application supports USART1 serial OTA. Serial
transfer, application-initiated entry, and recovery after an interrupted
transfer passed with byte-for-byte SWD readback. The suffix-free
`FW_VER:0.1.10;` passed 6/6 read-only HIL after OTA. For subsequent manual
updates, stop the PMIC monitor, ensure no battery is charging, and use the
installed application image:

```bash
robopi-pmic-ota flash-stm32 --port /dev/ttyUSB0 \
  --bin ${ROBOOS_PREFIX:-/opt/roboparty}/share/pmic/candidate/stm32f103c8/ChargeBAT.bin \
  --uid 0669FF555553787287104058
```

If transfer was interrupted and the board remains in its bootloader, repeat
with `--recover` instead of `--uid`. BMS 1.6.5 defaults `FORWARD_ENABLE=0`;
if an older config still forwards to `/dev/ttyS7`, disable it first. The bootloader has no second image slot or
automatic rollback; keep SWD available for service recovery. Battery charging
and output polarity remain unqualified.

The GD32F503VET6 reference target uses boot at `0x08000000`, application at
`0x08008000`, and reports `FW_VER:0.1.1-gd32;` plus its 96-bit chip UID on
USART0 (PA9/PA10, 115200 8N1). Its firmware has an internal-Flash OTA path,
but this addon tool does not perform OTA. There is no verified matching GD32
board: the packaged image forces charging EN off, and GD32 flashing and OTA
have not been tested on hardware.

`robopi-pmic-monitor.service` is installed but disabled by default. Set the
verified bidirectional host UART as `PMIC_PORT` in `/etc/default/robopi-pmic-monitor`,
then run `sudo systemctl enable --now robopi-pmic-monitor.service`. It polls
`CHRG_INFO:1;` every five seconds and publishes voltage, current, charge state,
and communication errors to `/run/roboparty/pmic-status.json` and the journal.
Stop the service before using `robopi-pmic-ota inspect` on the same serial port.

BMS 1.6.5 defaults `FORWARD_ENABLE=0`, so `/dev/ttyS7` is free for the PMIC
host port. If an older `/etc/default/bms_daemon` still forwards raw bytes from
`/dev/ttyS3` to `/dev/ttyS7`, set `FORWARD_ENABLE=0` and restart `bms.service`
before enabling the monitor. The monitor and OTA tool still refuse S7 while
forwarding is enabled; one serial owner is required. The older `0.1.8-left`
image omits `CHG_FAULT` from `CHRG_INFO`, so its `mcu_fault` is `null`.
The packaged `0.1.10` and `0.1.1-gd32` candidates expose `CHG_FAULT:0/1;`.
The previous STM32 image was flashed, read back byte for byte, and passed 6/6 serial checks on
2026-11-06. On that earlier image, `OTA_BEGIN:41740,0;` returned `OTA_ERR;`, and
SWD readback afterward showed no application change. GD32 remains untested
on hardware. Transport errors are reported
as `communication_fault`.
`robopi-pmic-ota` remains an operator command. Neither package installation nor
the monitor flashes PMIC firmware.

## Default service policy

The package maintainer scripts apply the following default policy:

| Service | Default | Purpose |
|---|---|---|
| `robopi-usb-wifi.service` | Enabled | Initialize AIC8800 USB Wi-Fi |
| `robopi-wifi-autoselect.service` | Enabled | Select USB or onboard Wi-Fi at boot |
| `robopi-bms-gpio.service` | Enabled | Drive the dual-battery GPIO indicators from BMS state |
| `robopi-fan.service` | **Removed** | Unit no longer shipped; use the `robopi-fan` CLI (see Fan) |
| `robopi-ws2812-white.service` | Enabled | Run `solid 30 30 30` at boot and turn the strip off when stopped |
| `robopi-ethernet-mac.service` | Disabled | Enable manually only after checking the interface name and network impact |
| `robopi-hw-test.service` | Disabled | Manufacturing/diagnostic tool; conflicts with the BMS GPIO service |
| `robopi-sig-key.service` | Disabled | SIG/key diagnostic tool; conflicts with the BMS GPIO service |
| `robopi-pmic-monitor.service` | Disabled | Read-only PMIC monitoring after a bidirectional UART is configured; never flashes |

`usbcan-capture.service` and `hpm-log-capture.service` belong to
`roboparty-analyze`; this package does not manage their state.

One-way UART3→UART7 forwarding is no longer a service of its own. It moved into
`bms_daemon` (`roboparty-bms` ≥ 1.6.0), which taps the bytes it already reads
from the BMS instead of letting a second process read the same tty — the two
readers used to steal bytes from each other on `robopi2`, where the daemon owns
`/dev/ttyS3`. Configure it with `FORWARD_ENABLE`, `FORWARD_PORT_A`,
`FORWARD_PORT_B` and `FORWARD_BAUD` in `/etc/default/bms_daemon`; see that
package's README.

## Wi-Fi

The BSP provides the AIC8800 kernel drivers and firmware. This package contains
device naming and initialization tools for the UGREEN AX300 (AIC8800DC). When
exactly one supported USB adapter is present,
it is assigned the stable name `wlan1`. Automatic selection prefers USB
Wi-Fi. It leaves existing connections unchanged when no USB adapter is found,
and it does not silently fall back to onboard Wi-Fi if the selected USB adapter
is unplugged.

```bash
robopi-wifi-select status
sudo robopi-wifi-select auto
sudo robopi-wifi-select usb
sudo robopi-wifi-select onboard
```

Changing interfaces interrupts the current wireless connection. See
[Bundled USB Wi-Fi support](docs/usb-wifi-bundle.md) and
[Wi-Fi selection](docs/wifi-selection.md) for firmware, device
identification, and recovery procedures.

## BMS GPIO

`robopi-bms-gpio.service` only reads `/tmp/bms.sock`; it never sends commands
to the BMS serial port. BMS integration needs
`${ROBOOS_PREFIX:-/opt/roboparty}/include/bms_driver.hpp` and `bms.service` from
`roboparty-base`. Without base, a systemd condition skips this service without
affecting other addon features or standalone unit tests. It controls:

```text
/sys/class/leds/dual_battery_b0/brightness
/sys/class/leds/dual_battery_c2/brightness
```

The producer must write the 126-byte packet matching the current C++
`BatteryStatus` definition. The old 121-byte format is incompatible. See
[BMS GPIO](docs/bms-gpio.md) for the state mapping, conservative fallback
behavior, and integration procedure.

`robopi-hw-test` and `robopi-sig-key` also manipulate related GPIOs, so their
services are disabled during package installation. Stop the BMS GPIO service
before using either diagnostic tool, then restore it afterward:

```bash
sudo systemctl stop robopi-bms-gpio.service
sudo robopi-sig-key --help
# After diagnostics
sudo systemctl start robopi-bms-gpio.service
```

## WS2812

`robopi-ws2812` controls 12 LEDs on PWM6_M1 through
`/dev/robopi-ws2812` and requires root privileges. Start with low RGB values
to verify the power supply and wiring.

```bash
sudo robopi-ws2812 solid 32 32 32
sudo robopi-ws2812 flash 0 255 0 500 10
sudo robopi-ws2812 chase 0 0 255 80 3
sudo robopi-ws2812 rainbow 40
sudo robopi-ws2812 off
robopi-ws2812 --help
```

Press `Ctrl+C` to stop a continuous animation; the program turns the strip
off before exiting. The BSP provides the `robopi-ws2812` driver and enables
PWM6_M1 in the device tree; this package installs the user-space command and
service and loads the driver at boot through modules-load.d.

## Fan

FAN_SW uses GPIO1_D7 (global GPIO 63). A high level enables the fan supply.
The systemd service is **no longer shipped** (it kept failing at boot). Control
the fan manually with the CLI:

```bash
sudo robopi-fan on
sudo robopi-fan status
sudo robopi-fan off
```

## EtherCAN and USB capture (roboparty-analyze)

The HPM is the onboard EtherCAN controller and connects to the RK3588 through
an onboard USB hub. Install `roboparty-analyze` for EtherCAN firmware, HPM
maintenance tools, and USB capture. Its firmware is installed at:

```text
${ROBOOS_PREFIX:-/opt/roboparty}/lib/firmware/ethercanfd_v1.0.5-20260829.bin
```

`usb_hub_reset` (GPIO4_B5) controls the hardware reset for the USB hub that
hosts the onboard HPM. A high level disables the hub and holds the HPM in reset.
A low level releases reset and starts the hub and HPM; low is the default state.
Apply a short high pulse to refresh the HPM state and force USB
re-enumeration:

```bash
# Disable the hub and hold the onboard HPM in hardware reset
echo 1 | sudo tee /sys/class/leds/usb_hub_reset/brightness
sleep 0.5

# Release reset and restart the hub and onboard HPM
echo 0 | sudo tee /sys/class/leds/usb_hub_reset/brightness

# Wait for startup and verify that the HPM enumerated again
sleep 15
lsusb -d 1209:2323
```

Do not leave `brightness` at `1`; the HPM remains offline while reset is
asserted.

The firmware flasher, `${ROBOOS_PREFIX:-/opt/roboparty}/bin/flash_hpm.sh`, is a maintenance
interface and should only be run after confirming the firmware image and
device state.

USB capture is disabled by default. While reproducing a fault, uncompressed
ring-buffer pcaps can be kept in `/run/usbcan`, with a default limit of
`8 x 64 MiB = 512 MiB`. Copy a snapshot to persistent storage after the fault
and analyze it offline:

```bash
sudo systemctl start usbcan-capture.service
sudo usbcan-debug-snapshot
sudo systemctl stop usbcan-capture.service

analyze-ethercan-pcap /var/lib/robopi/usbcan-snapshots/<snapshot-directory>
```

Starting USB capture also records the HPM log from `/dev/ttyS4` at 115200 baud.
The snapshot stores that journal as `hpm-uart-journal.txt`.

See `/usr/share/doc/roboparty-analyze/usbcan-dump.md.gz` for configuration,
dependencies, capture filters, and resource costs.

## Stable Ethernet MAC

`robopi-ethernet-mac` derives a stable, locally administered unicast MAC from
the RK3588 `Serial` field in `/proc/cpuinfo` without exposing the Chip ID
directly. The default interface is configured in
`/etc/default/robopi-ethernet-mac`:

```bash
ETHERNET_INTERFACE=enP4p65s0
ETHERNET_WAIT_SECONDS=60
```

The service is explicitly left disabled after package installation. Run the
read-only checks from a serial console or an alternative network connection:

```bash
robopi-ethernet-mac check
robopi-ethernet-mac status
```

After confirming the interface name, apply the derived MAC. Both `apply` and
`restore` reconnect the selected interface and may change its IP address:

```bash
sudo robopi-ethernet-mac apply [interface]
sudo robopi-ethernet-mac restore [interface]
```

Explicitly enable the boot service only when this behavior is required:

```bash
sudo systemctl enable --now robopi-ethernet-mac.service
```

## Install

Check the architecture before installation. The package supports ARM64 only
and requires a RoboPi BSP containing the WS2812 and AIC8800 drivers:

```bash
dpkg --print-architecture
sudo apt install ./robopi-addon_*_arm64.deb
```

Recommended post-installation checks:

```bash
systemctl --failed
systemctl status robopi-bms-gpio.service
systemctl status robopi-wifi-autoselect.service
journalctl -b -p warning
```

## Build and test

Native build on an ARM64 board:

```bash
sudo apt install build-essential debhelper fakeroot
dpkg-buildpackage -us -uc -b
```

Cross-build an ARM64 package on an x86_64/EPYC host:

```bash
sudo apt install build-essential debhelper fakeroot \
  gcc-aarch64-linux-gnu libc6-dev-arm64-cross
dpkg-buildpackage -us -uc -b -aarm64
```

Regression tests that do not access hardware:

```bash
bash tests/usb-wifi-init-test.sh
bash tests/wifi-autoselect-test.sh
python3 tests/bms-gpio-test.py
```

The generated `.deb` is written to the parent directory.

## Troubleshooting

```bash
systemctl --failed
journalctl -b -u <service-name>
lsusb -t
iw dev
ip -details link
uname -r
```

If a BSP driver is unavailable, inspect the BSP kernel configuration and
`dmesg`. For Wi-Fi problems, run `robopi-wifi-select status` and inspect the
current-boot logs for the Wi-Fi services.

## Uninstall

```bash
sudo apt remove robopi-addon
sudo apt purge robopi-addon
```

The removal scripts stop the WS2812 and fan services. BSP-owned
kernel modules are not modified. Existing NetworkManager connection profiles
and diagnostic snapshots created at runtime are not removed automatically.
