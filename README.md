# robopi-addon

[中文说明](README_CN.md)

`robopi-addon` is the board support package for RoboPi RK3588S (ARM64). It can
be installed independently and does not require `roboparty-base`. It installs
Wi-Fi, BMS GPIO, fan, WS2812, EtherCAN maintenance, and field diagnostic tools
under `/opt/roboparty`. Frequently used commands are also exposed through
`/usr/bin`.

The package configures and enables several systemd services. Keep a serial
console or an alternative wired connection available during the first
installation or upgrade, because Wi-Fi selection and device restarts may
interrupt the current SSH session.

## Quick reference

| Task | Command or documentation |
|---|---|
| Inspect or select Wi-Fi | `robopi-wifi-select status` / [Wi-Fi selection](docs/wifi-selection.md) |
| Control the WS2812 strip | `sudo robopi-ws2812 --help` |
| Control the fan | `sudo robopi-fan on\|off\|status` |
| Check the Ethernet MAC | `robopi-ethernet-mac check` |
| Inspect GPIO0_C2 drive strength | `sudo robopi-gpio0-c2-drive status` |
| Review BMS GPIO behavior | [BMS GPIO](docs/bms-gpio.md) |
| Capture a USB-CAN fault snapshot | `sudo usbcan-debug-snapshot` / [capture guide](docs/usbcan-dump.md) |
| Analyze a USB-CAN capture | `analyze-ethercan-pcap <pcap-file-or-directory>` |
| List failed services | `systemctl --failed` |

## Default service policy

The package maintainer scripts apply the following default policy:

| Service | Default | Purpose |
|---|---|---|
| `robopi-usb-wifi.service` | Enabled | Initialize AIC8800 USB Wi-Fi |
| `robopi-wifi-autoselect.service` | Enabled | Select USB or onboard Wi-Fi at boot |
| `wifi-reset.service` | Enabled | Monitor and reconnect the selected Wi-Fi interface without switching adapters |
| `robopi-bms-gpio.service` | Enabled | Drive the dual-battery GPIO indicators from BMS state |
| `robopi-fan.service` | Enabled | Turn on FAN_SW at boot |
| `robopi-uart-bridge.service` | Enabled | One-way forward UART3→UART7 (ttyS3→ttyS7, 115200) |
| `robopi-ws2812-white.service` | Enabled | Run `solid 30 30 30` at boot and turn the strip off when stopped |
| `hpm-reset.service` | Enabled | Hardware-reset the onboard HPM after repeated EtherCAN USB loss |
| `robopi-ethernet-mac.service` | Disabled | Enable manually only after checking the interface name and network impact |
| `robopi-hw-test.service` | Disabled | Manufacturing/diagnostic tool; conflicts with the BMS GPIO service |
| `robopi-sig-key.service` | Disabled | SIG/key diagnostic tool; conflicts with the BMS GPIO service |
| `usbcan-capture.service` | Disabled and not started | USB ring capture used only while reproducing a fault |

`hpm-autoflash.service` is a static maintenance unit with no `[Install]`
section. The package currently does not install the HPM udev trigger it expects,
so it must not be treated as an active automatic update mechanism.

## Wi-Fi

The package contains prebuilt modules, firmware, and initialization tools for
the UGREEN AX300 (AIC8800DC). When exactly one supported USB adapter is present,
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
[Wi-Fi selection](docs/wifi-selection.md) for modules, firmware, device
identification, and recovery procedures.

## BMS GPIO

`robopi-bms-gpio.service` only reads `/tmp/bms.sock`; it never sends commands
to the BMS serial port. BMS integration needs
`/opt/roboparty/include/bms_driver.hpp` and `bms.service` from
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
off before exiting. The package installs a prebuilt `robopi-ws2812.ko` for
one target kernel and does not install or modify the device tree. The running
kernel must match the module, and PWM6_M1 must already be enabled in the device
tree. A kernel upgrade requires rebuilt modules and a new package.

## Fan

FAN_SW uses GPIO1_D7 (global GPIO 63). A high level enables the fan supply.
The default service turns the fan on at boot and turns it off when stopped.

```bash
sudo robopi-fan status
sudo robopi-fan on
sudo robopi-fan off
systemctl status robopi-fan.service
```

## EtherCAN and USB capture

The HPM is the onboard EtherCAN controller and connects to the RK3588 through
an onboard USB hub. The package installs EtherCAN firmware, HPM maintenance
tools, and an HPM hardware-reset service. The firmware is installed at:

```text
/opt/roboparty/lib/firmware/ethercanfd_v1.0.5-20260829.bin
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

`hpm-reset.service` performs the same high-low pulse automatically. By
default, it checks HPM VID:PID `1209:2323` every 2 seconds. After 10
consecutive misses, it asserts the GPIO for 0.5 seconds, releases reset, and
waits 15 seconds. Settings are in `/etc/default/hpm-reset`. The firmware
flasher, `/opt/roboparty/bin/flash_hpm.sh`, is a maintenance interface and
should only be run after confirming the firmware image and device state.

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

See [USB-CAN capture](docs/usbcan-dump.md) for configuration, dependencies,
capture filters, and resource costs.

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

## GPIO0_C2 drive strength

`robopi-gpio0-c2-drive` can back up and modify the active boot DTB to select
`pcfg_pull_down_drv_level_5` for GPIO0_C2. This is an explicit device-tree
maintenance operation and is never performed automatically during package
installation.

```bash
sudo robopi-gpio0-c2-drive status
sudo robopi-gpio0-c2-drive apply
sudo reboot

# Restore the DTB saved by the first apply
sudo robopi-gpio0-c2-drive restore
sudo reboot
```

The matching kernel source patch is also installed at:

```text
/usr/share/robopi-addon/patches/0001-rk3588s-robopi2-gpio0-c2-max-drive.patch
```

## Install

Check the architecture and running kernel before installation. The package
supports ARM64 only and contains prebuilt modules for one fixed target kernel:

```bash
dpkg --print-architecture
uname -r
sudo apt install ./robopi-addon_*_arm64.deb
```

Recommended post-installation checks:

```bash
systemctl --failed
systemctl status robopi-bms-gpio.service robopi-fan.service
systemctl status robopi-wifi-autoselect.service wifi-reset.service
journalctl -b -p warning
```

## Build and test

Native build on an ARM64 board:

```bash
sudo apt install build-essential debhelper fakeroot kmod unzip binutils
dpkg-buildpackage -us -uc -b
```

Cross-build an ARM64 package on an x86_64/EPYC host:

```bash
sudo apt install build-essential debhelper fakeroot kmod unzip binutils \
  gcc-aarch64-linux-gnu libc6-dev-arm64-cross
dpkg-buildpackage -us -uc -b -aarm64
```

The package targets `6.18.51-current-rockchip64`; its modules are stored under
the matching `prebuilt/6.18.51-current-rockchip64/` directory:

```bash
dpkg-buildpackage -us -uc -b -aarm64
```

Regression tests that do not access hardware:

```bash
bash tests/usb-wifi-init-test.sh
bash tests/wifi-autoselect-test.sh
bash tests/wifi-reconnect-test.sh
python3 tests/bms-gpio-test.py
bash tests/usbcan-capture-test.sh
bash tests/usbcan-snapshot-test.sh
python3 -m unittest -v tests/test_analyze_ethercan_pcap.py
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

If a prebuilt module fails to load, first compare `uname -r` with the module
directory in the package. For Wi-Fi problems, run `robopi-wifi-select status`
and inspect the current-boot logs for the three Wi-Fi services.

## Uninstall

```bash
sudo apt remove robopi-addon
sudo apt purge robopi-addon
```

The removal scripts stop the WS2812, fan, and USB capture services, attempt to
unload the WS2812 kernel module, and refresh module dependencies. Existing
NetworkManager connection profiles and diagnostic snapshots created at runtime
are not removed automatically.
