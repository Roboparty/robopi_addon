# robopi-addon

[English](README.md)

`robopi-addon` 是 RoboPi RK3588S（ARM64）的板级支持包，可独立安装，不强制依赖
`roboparty-base`。它把 Wi-Fi、BMS GPIO、风扇、WS2812、EtherCAN 维护工具和现场
诊断工具统一安装到 `/opt/roboparty`，并为常用命令提供 `/usr/bin` 入口。

这个包会配置并启用部分 systemd 服务。首次安装或升级前，建议保留串口或另一条
有线连接，避免 Wi-Fi 自动切换或设备重启影响当前 SSH 会话。

## 快速索引

| 需求 | 命令或文档 |
|---|---|
| 查看或切换 Wi-Fi | `robopi-wifi-select status` / [Wi-Fi 切换说明](docs/wifi-selection.md) |
| 控制 WS2812 灯带 | `sudo robopi-ws2812 --help` |
| 控制风扇 | `sudo robopi-fan on\|off\|status` |
| 检查以太网 MAC | `robopi-ethernet-mac check` |
| 查看 GPIO0_C2 驱动配置 | `sudo robopi-gpio0-c2-drive status` |
| 查看 BMS GPIO 行为 | [BMS GPIO 说明](docs/bms-gpio.md) |
| USB-CAN 故障抓包 | `sudo usbcan-debug-snapshot` / [抓包说明](docs/usbcan-dump.md) |
| 分析 USB-CAN 抓包 | `analyze-ethercan-pcap <pcap 文件或目录>` |
| 查看失败服务 | `systemctl --failed` |

## 默认服务行为

安装脚本以当前包内的 systemd 配置为准。默认状态如下：

| 服务 | 默认 | 用途 |
|---|---|---|
| `robopi-usb-wifi.service` | 启用 | 初始化 AIC8800 USB Wi-Fi |
| `robopi-wifi-autoselect.service` | 启用 | 开机选择 USB 或板载 Wi-Fi |
| `wifi-reset.service` | 启用 | 监测并重连当前选中的 Wi-Fi，不切换备用网卡 |
| `robopi-bms-gpio.service` | 启用 | 根据 BMS 状态控制双电池 GPIO 指示灯 |
| `robopi-fan.service` | 启用 | 开机打开 FAN_SW |
| `robopi-uart-bridge.service` | 启用 | 单向转发 UART3→UART7（ttyS3→ttyS7，默认 115200） |
| `robopi-ws2812-white.service` | 启用 | 开机执行 `solid 30 30 30`，停止时熄灯 |
| `hpm-reset.service` | 启用 | EtherCAN USB 连续缺失时硬复位板载 HPM |
| `robopi-ethernet-mac.service` | 禁用 | 仅在确认网卡名和网络影响后手动启用 |
| `robopi-hw-test.service` | 禁用 | 产测/诊断工具，与 BMS GPIO 服务互斥 |
| `robopi-sig-key.service` | 禁用 | SIG/按键诊断工具，与 BMS GPIO 服务互斥 |
| `usbcan-capture.service` | 禁用且不启动 | 问题复现期间才启用的 USB 环形抓包 |

`hpm-autoflash.service` 是静态维护单元，没有 `[Install]` 入口。当前包不安装它所需
的 HPM udev 触发规则，因此不要把它当作默认自动升级机制。

## Wi-Fi

软件包包含 UGREEN AX300（AIC8800DC）的预编译模块、固件及初始化工具。只有一个
受支持的 USB 无线网卡时，它会固定命名为 `wlan1`。自动选择默认优先 USB Wi-Fi；
没有检测到 USB 网卡时不会修改现有连接，已选中的 USB 网卡被拔出时也不会悄悄
回退到板载网卡。

```bash
robopi-wifi-select status
sudo robopi-wifi-select auto
sudo robopi-wifi-select usb
sudo robopi-wifi-select onboard
```

切换接口会中断现有无线连接。模块、固件、设备识别及恢复流程见
[USB Wi-Fi 随包交付说明](docs/usb-wifi-bundle.md) 和
[Wi-Fi 切换说明](docs/wifi-selection.md)。

## BMS GPIO

`robopi-bms-gpio.service` 只读取 `/tmp/bms.sock`，不会向 BMS 串口写命令。BMS
集成功能需要 `roboparty-base` 提供的 `/opt/roboparty/include/bms_driver.hpp` 和
`bms.service`；未安装 base 时，该服务通过 systemd 条件检查跳过，不影响 addon 的
其他功能或独立单元测试。它控制：

```text
/sys/class/leds/dual_battery_b0/brightness
/sys/class/leds/dual_battery_c2/brightness
```

服务要求上游写入与当前 C++ `BatteryStatus` 定义一致的 126 字节数据包；旧的 121
字节格式不兼容。详细状态映射、保守降级策略和联调方法见
[BMS GPIO 说明](docs/bms-gpio.md)。

`robopi-hw-test` 和 `robopi-sig-key` 也会操作相关 GPIO，因此安装时默认禁用。调试
这两个程序前，应先停止 BMS GPIO 服务，结束后再恢复：

```bash
sudo systemctl stop robopi-bms-gpio.service
sudo robopi-sig-key --help
# 完成诊断后
sudo systemctl start robopi-bms-gpio.service
```

## WS2812

`robopi-ws2812` 通过 `/dev/robopi-ws2812` 控制 PWM6_M1 上的 12 颗灯珠，需要 root
权限。建议先用较低 RGB 数值确认供电和接线。

```bash
sudo robopi-ws2812 solid 32 32 32
sudo robopi-ws2812 flash 0 255 0 500 10
sudo robopi-ws2812 chase 0 0 255 80 3
sudo robopi-ws2812 rainbow 40
sudo robopi-ws2812 off
robopi-ws2812 --help
```

持续动画可用 `Ctrl+C` 停止，程序退出时会熄灯。软件包只安装针对目标内核预编译
的 `robopi-ws2812.ko`，不会自动安装或修改设备树；系统必须使用匹配内核，并在
设备树中启用 PWM6_M1。升级内核后需要重新构建模块和软件包。

## 风扇

FAN_SW 使用 GPIO1_D7（全局 GPIO63），高电平接通风扇电源。默认服务在开机时
打开风扇，停止服务时关闭风扇。

```bash
sudo robopi-fan status
sudo robopi-fan on
sudo robopi-fan off
systemctl status robopi-fan.service
```

## EtherCAN 与 USB 抓包

HPM 是板载 EtherCAN 控制器，通过板载 USB Hub 接入 RK3588。软件包安装 EtherCAN
固件、HPM 维护工具和 HPM 硬复位服务。固件位于：

```text
/opt/roboparty/lib/firmware/ethercanfd_v1.0.5-20260829.bin
```

`usb_hub_reset`（GPIO4_B5）是板载 HPM 所在 USB Hub 的硬复位控制：高电平关闭
Hub 并保持 HPM 复位，低电平释放复位、恢复 Hub 和 HPM，默认状态为低电平。因此
给这个 GPIO 一个高脉冲即可刷新 HPM 状态并触发 USB 重新枚举：

```bash
# 关闭 Hub，让板载 HPM 进入硬复位
echo 1 | sudo tee /sys/class/leds/usb_hub_reset/brightness
sleep 0.5

# 释放复位，重新启动 Hub 和板载 HPM
echo 0 | sudo tee /sys/class/leds/usb_hub_reset/brightness

# 等待启动后确认 HPM 已重新枚举
sleep 15
lsusb -d 1209:2323
```

不要把 `brightness` 长时间留在 `1`，否则 HPM 会一直离线。

`hpm-reset.service` 会自动完成同样的高低电平脉冲。它默认每 2 秒检查一次 HPM 的
VID:PID `1209:2323`，连续 10 次缺失后拉高 GPIO 0.5 秒，再释放复位并等待 15 秒。
参数位于 `/etc/default/hpm-reset`。固件刷写脚本
`/opt/roboparty/bin/flash_hpm.sh` 属于维护入口，应在明确固件和设备状态后手动使用。

USB 抓包默认关闭。问题复现时可把未压缩环形 pcap 保存在 `/run/usbcan`，默认上限
为 `8 x 64 MiB = 512 MiB`；故障后再复制快照到磁盘并离线分析：

```bash
sudo systemctl start usbcan-capture.service
sudo usbcan-debug-snapshot
sudo systemctl stop usbcan-capture.service

analyze-ethercan-pcap /var/log/robopi/usbcan/<快照目录>
```

配置、依赖、抓包过滤器和资源开销见 [USB-CAN 抓包说明](docs/usbcan-dump.md)。

## 稳定以太网 MAC

`robopi-ethernet-mac` 从 `/proc/cpuinfo` 的 RK3588 `Serial` 派生稳定的、本地管理的
单播 MAC，不直接暴露 Chip ID。默认接口配置在
`/etc/default/robopi-ethernet-mac`：

```bash
ETHERNET_INTERFACE=enP4p65s0
ETHERNET_WAIT_SECONDS=60
```

该服务安装后明确保持禁用。先通过串口或备用网络执行只读检查：

```bash
robopi-ethernet-mac check
robopi-ethernet-mac status
```

确认接口名后再应用。`apply` 和 `restore` 都会使指定网卡重新连接并可能改变 IP：

```bash
sudo robopi-ethernet-mac apply [接口名]
sudo robopi-ethernet-mac restore [接口名]
```

需要开机自动应用时再显式启用：

```bash
sudo systemctl enable --now robopi-ethernet-mac.service
```

## GPIO0_C2 驱动强度

`robopi-gpio0-c2-drive` 可备份并修改当前启动 DTB，把 GPIO0_C2 配置为
`pcfg_pull_down_drv_level_5`。这是对设备树的显式维护操作，软件包安装过程不会自动
执行。

```bash
sudo robopi-gpio0-c2-drive status
sudo robopi-gpio0-c2-drive apply
sudo reboot

# 回退到首次 apply 保存的 DTB
sudo robopi-gpio0-c2-drive restore
sudo reboot
```

匹配内核源码的补丁也安装在：

```text
/usr/share/robopi-addon/patches/0001-rk3588s-robopi2-gpio0-c2-max-drive.patch
```

## 安装

安装前先确认架构和运行内核。这个包只支持 ARM64，并包含固定目标内核的预编译
模块：

```bash
dpkg --print-architecture
uname -r
sudo apt install ./robopi-addon_*_arm64.deb
```

安装后建议检查：

```bash
systemctl --failed
systemctl status robopi-bms-gpio.service robopi-fan.service
systemctl status robopi-wifi-autoselect.service wifi-reset.service
journalctl -b -p warning
```

## 构建与测试

ARM64 板上原生构建：

```bash
sudo apt install build-essential debhelper fakeroot kmod unzip binutils
dpkg-buildpackage -us -uc -b
```

在 x86_64/EPYC 主机上交叉构建 ARM64 包：

```bash
sudo apt install build-essential debhelper fakeroot kmod unzip binutils \
  gcc-aarch64-linux-gnu libc6-dev-arm64-cross
dpkg-buildpackage -us -uc -b -aarm64
```

软件包固定面向 `6.18.51-current-rockchip64`，模块位于对应的
`prebuilt/6.18.51-current-rockchip64/` 目录：

```bash
dpkg-buildpackage -us -uc -b -aarm64
```

不访问硬件的回归测试：

```bash
bash tests/usb-wifi-init-test.sh
bash tests/wifi-autoselect-test.sh
bash tests/wifi-reconnect-test.sh
python3 tests/bms-gpio-test.py
bash tests/usbcan-capture-test.sh
bash tests/usbcan-snapshot-test.sh
python3 -m unittest -v tests/test_analyze_ethercan_pcap.py
```

生成的 `.deb` 位于源码目录的上一级。

## 常用排障

```bash
systemctl --failed
journalctl -b -u <服务名>
lsusb -t
iw dev
ip -details link
uname -r
```

预编译模块加载失败时，首先比较 `uname -r` 与包内模块目录；网络异常时，先运行
`robopi-wifi-select status`，再查看 Wi-Fi 三个服务的本次启动日志。

## 卸载

```bash
sudo apt remove robopi-addon
sudo apt purge robopi-addon
```

卸载脚本会停止灯带、风扇和 USB 抓包服务，尝试卸载 WS2812 内核模块，并刷新
模块依赖。已有的 NetworkManager 连接配置以及运行期间生成的诊断快照不会被主动
删除。
