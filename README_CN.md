# robopi-addon

[English](README.md)

`robopi-addon` 是 RoboPi RK3588S（ARM64）的板级支持包，可独立安装，不强制依赖
`roboparty-base`。它把 Wi-Fi、BMS GPIO、风扇和 WS2812 板级工具安装到
`${ROBOOS_PREFIX:-/opt/roboparty}`；EtherCAN 维护工具和现场诊断工具由独立的 `roboparty-analyze`
软件包提供。常用的 addon 命令也有 `/usr/bin` 入口。

这个包会配置并启用部分 systemd 服务。首次安装或升级前，建议保留串口或另一条
有线连接，避免 Wi-Fi 自动切换或设备重启影响当前 SSH 会话。

## 快速索引

以下 USB-CAN、HPM、CAN 和同步诊断命令需另行安装 `roboparty-analyze`。

| 需求 | 命令或文档 |
|---|---|
| 查看或切换 Wi-Fi | `robopi-wifi-select status` / [Wi-Fi 切换说明](docs/wifi-selection.md) |
| 控制 WS2812 灯带 | `sudo robopi-ws2812 --help` |
| 控制风扇 | `sudo robopi-fan on\|off\|status` |
| 检查以太网 MAC | `robopi-ethernet-mac check` |
| 查看 BMS GPIO 行为 | [BMS GPIO 说明](docs/bms-gpio.md) |
| USB-CAN 故障抓包 | `sudo usbcan-debug-snapshot` / `/usr/share/doc/roboparty-analyze/usbcan-dump.md.gz` |
| 分析 USB-CAN 抓包 | `analyze-ethercan-pcap <pcap 文件或目录>` |
| 重启四路 CAN 接口 | `sudo robopi-can-restart` |
| 将四路 CAN 抓为 ASC | `sudo robopi-can-capture /home/robo/can.asc` |
| 同步采集七维诊断日志 | `sudo robopi-sixd-capture /home/robo/robopi-logs/session` |
| 分析七维诊断日志 | `robopi-sixd-analyze /home/robo/robopi-logs/session` |
| 导出七维日志 ZIP 并生成 SHA-256 | `robopi-sixd-export /home/robo/robopi-logs/session` |
| 查看失败服务 | `systemctl --failed` |

## PMIC 双目标固件候选

当前 STM32F103C8 的逐脚引脚定义、功能状态和待验证项见
[PMIC Pinout 与功能清单](docs/pmic-pinout-functions.md)。安装包内位于
`/usr/share/doc/robopi-addon/pmic-pinout-functions.md`。

本包从修正后的
[`roboparty_pmic v0.1.11 工程预发布版`](https://github.com/Roboparty/roboparty_pmic/releases/tag/v0.1.11)
收录 STM32F103C8 与 GD32F503VET6 两套 bootloader、应用镜像和 SHA-256 清单，
分别安装在 `${ROBOOS_PREFIX:-/opt/roboparty}/share/pmic/candidate/stm32f103c8/` 和
`${ROBOOS_PREFIX:-/opt/roboparty}/share/pmic/candidate/gd32f503/`。v0.1.8 的 GD32 镜像版本串有误，
已弃用。`-left` 是历史构建后缀，不代表第二颗 MCU。
**未完成量产放行**；安装本包不会自动烧录 PMIC。

先确认 PMIC 的 USART3 串口设备（115200 8N1），再只读查询：

```bash
robopi-pmic-ota inspect --port /dev/ttyUSB0
```

新版用内部 Flash 串口 OTA，首次安装新 bootloader 仍需用 CMSIS-DAP/SWD 烧录
`stm32f103c8/boot.bin` 和 `stm32f103c8/ChargeBAT.bin`，
地址分别为 `0x08000000` 和 `0x08001000`。
`0.1.8-left` 不使用 PB4，也不编译 BMS 通信或初始化 USART1（PA9/PA10）。
固件在 ADC 连续采样有效、输入为 16–32V、CH224 能读到适配器电流且无故障时
自动使能 PB3 `EN` 与 PA3 `ICTRL`；需要电池包自带独立充满截止保护。
保存值和主机 `CHG_EN`/`ICTRL` 写入不能绕过自动条件。旧协议查询
`BAT_INST` 返回 0，`BAT_SOC`/`BAT_SOH` 返回 `BMS_DISABLED;`。
相同控制逻辑的 `0.1.5-left` 已验证 5V 输入时关闭、
20V PD 输入时 PB3 拉高；这次测试未接电池包。旧版 `0.1.8-left` 已烧录回读；
先前 `0.1.9-left` 已于 2026-11-06 烧录到 STM32F103C8，并通过 SWD
逐字节回读和 6/6 串口只读 HIL；5V 下 `CHG_EN:0`、`CHG_FAULT:0`。
有效格式的 `OTA_BEGIN:41740,0;` 在旧版返回 `OTA_ERR;`，随后 SWD 再次回读应用
仍与当时的 Release 镜像一致。包内新版已经支持串口 OTA。
充电且输出电压低于 54V 时 PA5 绿灯亮，达到 54V 后 PA4 红灯亮；PA1 引脚电压
1.39–1.50V 时 PA6 拉高，1.21–<1.39V 时 PA7 拉高。54V 只切换灯，不停止充电；
主机 R/G 写入不能覆盖自动灯态。
SWD 逐脚测试确认 PA4 红、PA5 绿、PA6 电池绿、PA7 电池红；20V 空载时
实物仅充电红灯亮。PA1 电压区间和带载绿灯状态未实板验证；外部电压/电流
及实际充电截止尚未测量。

无需连接串口即可校验包内镜像：

```bash
robopi-pmic-ota verify-bundle \
  --bundle ${ROBOOS_PREFIX:-/opt/roboparty}/share/pmic/candidate/stm32f103c8/manifest.json
robopi-pmic-ota verify-bundle \
  --bundle ${ROBOOS_PREFIX:-/opt/roboparty}/share/pmic/candidate/gd32f503/manifest.json
```

包内 `0.1.10` 工程版已实现 USART3 串口 OTA：新 bootloader 首次仍需
通过 SWD 安装。后续更新时先停止 PMIC 监控服务、确认没有带电池充电，再显式提供
新版应用镜像，人工执行：

```bash
robopi-pmic-ota flash-stm32 --port /dev/ttyUSB0 \
  --bin ${ROBOOS_PREFIX:-/opt/roboparty}/share/pmic/candidate/stm32f103c8/ChargeBAT.bin \
  --uid 0669FF555553787287104058
```

更新中断后设备留在 bootloader，用相同命令加 `--recover` 并省略 `--uid` 重传。
命令会拒绝使用仍被 BMS 转发占用的 S7。实板已验证串口传输、应用自行进入更新、
中断恢复与 SWD 逐字节回读；去掉 `left` 后的 `FW_VER:0.1.10;` 也已通过串口 OTA
烧录及 6/6 只读 HIL。没有双镜像存储，也不能自动回滚旧版；保留 SWD 维修
入口。带电池充电闭环、输出极性和多板测试尚未完成，不能标注为量产固件。

GD32F503VET6 参考目标的 boot 地址为 `0x08000000`、应用地址为 `0x08008000`，
USART0（PA9/PA10，115200 8N1）可查询 `FW_VER:0.1.1-gd32;` 和 96 位芯片 UID。
固件包含内部 Flash OTA 路径，但 addon 的命令目前不执行 OTA；GD32 尚无匹配实板，
包内镜像强制关闭充电 EN，也没有完成烧录和 OTA 实测。

`robopi-pmic-monitor.service` 是只读 PMIC 监控服务，默认禁用。确认 PMIC 的
双向主机串口后，在 `/etc/default/robopi-pmic-monitor` 设置 `PMIC_PORT`，再执行
`sudo systemctl enable --now robopi-pmic-monitor.service`。服务每 5 秒发送一次
`CHRG_INFO:1;`，将输入电压、充电电流、使能状态和通信故障写入
`/run/roboparty/pmic-status.json`；`journalctl -u robopi-pmic-monitor` 可查看采样日志。
运行维护命令 `robopi-pmic-ota inspect` 前先停止服务，避免串口争用。

现有 BMS 默认从 `/dev/ttyS3` 单向转发原始字节到 `/dev/ttyS7`。当前没有
查询仲裁，监控服务会拒绝使用仍被 BMS 转发占用的 S7。若 PMIC 的双向主机串口
实际是 S7，必须先在 `/etc/default/bms_daemon` 设置 `FORWARD_ENABLE=0` 并重启
`bms.service`，确认不再占用 S7 后，才能启用监控。需要同时保留转发与 PMIC
交互时，应先增加单一串口所有者及协议仲裁，不能让两个进程并发写 S7。
旧版已烧录的 `0.1.8-left` 的 `CHRG_INFO` 不含内部故障位，因此 JSON 的
`mcu_fault` 为 `null`（未知）；包内 `0.1.10` 和 `0.1.1-gd32` 镜像会回
`CHG_FAULT:0/1;`；STM32 新版已烧录，GD32 仍未实板验证。串口读写错误会明确置 `connected=false`
和 `communication_fault`。
`robopi-pmic-ota` 仍是人工触发命令，安装服务不会自动刷机。

## 默认服务行为

安装脚本以当前包内的 systemd 配置为准。默认状态如下：

| 服务 | 默认 | 用途 |
|---|---|---|
| `robopi-usb-wifi.service` | 启用 | 初始化 AIC8800 USB Wi-Fi |
| `robopi-wifi-autoselect.service` | 启用 | 开机选择 USB 或板载 Wi-Fi |
| `robopi-bms-gpio.service` | 启用 | 根据 BMS 状态控制双电池 GPIO 指示灯 |
| `robopi-fan.service` | **已移除** | 不再随包安装；用 `robopi-fan` CLI 手动控制（见"风扇"） |
| `robopi-ws2812-white.service` | 启用 | 开机执行 `solid 30 30 30`，停止时熄灯 |
| `robopi-ethernet-mac.service` | 禁用 | 仅在确认网卡名和网络影响后手动启用 |
| `robopi-hw-test.service` | 禁用 | 产测/诊断工具，与 BMS GPIO 服务互斥 |
| `robopi-sig-key.service` | 禁用 | SIG/按键诊断工具，与 BMS GPIO 服务互斥 |
| `robopi-pmic-monitor.service` | 禁用 | 配好独立双向串口后只读监控 PMIC；不执行刷机 |

`usbcan-capture.service` 和 `hpm-log-capture.service` 属于 `roboparty-analyze`，
本包不管理它们的启停状态。

单向转发 UART3→UART7 不再是一个独立服务，已移入 `bms_daemon`（`roboparty-bms` ≥ 1.6.0）。
daemon 直接分流自己已经从 BMS 读到的字节，而不是让第二个进程去读同一个 tty —— 在 `robopi2`
上 daemon 本就占着 `/dev/ttyS3`，两个读者会互相抢走字节。配置项为 `/etc/default/bms_daemon`
中的 `FORWARD_ENABLE`、`FORWARD_PORT_A`、`FORWARD_PORT_B`、`FORWARD_BAUD`，详见该包的 README。

## Wi-Fi

内核驱动和固件由 BSP 提供。本包包含 UGREEN AX300（AIC8800DC）的设备命名和
初始化工具。只有一个
受支持的 USB 无线网卡时，它会固定命名为 `wlan1`。自动选择默认优先 USB Wi-Fi；
没有检测到 USB 网卡时不会修改现有连接，已选中的 USB 网卡被拔出时也不会悄悄
回退到板载网卡。

```bash
robopi-wifi-select status
sudo robopi-wifi-select auto
sudo robopi-wifi-select usb
sudo robopi-wifi-select onboard
```

切换接口会中断现有无线连接。固件、设备识别及恢复流程见
[USB Wi-Fi 随包交付说明](docs/usb-wifi-bundle.md) 和
[Wi-Fi 切换说明](docs/wifi-selection.md)。

## BMS GPIO

`robopi-bms-gpio.service` 只读取 `/tmp/bms.sock`，不会向 BMS 串口写命令。BMS
集成功能需要 `roboparty-base` 提供的 `${ROBOOS_PREFIX:-/opt/roboparty}/include/bms_driver.hpp` 和
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

持续动画可用 `Ctrl+C` 停止，程序退出时会熄灯。`robopi-ws2812` 驱动和 PWM6_M1
设备树配置由 BSP 提供；本包安装用户态命令和服务，并通过 modules-load.d 在
开机时加载该驱动。

## 风扇

FAN_SW 使用 GPIO1_D7（全局 GPIO63），高电平接通风扇电源。风扇 systemd 服务
**已不再随包安装**（此前开机持续失败），改为用 CLI 手动控制：

```bash
sudo robopi-fan on
sudo robopi-fan status
sudo robopi-fan off
```

## EtherCAN 与 USB 抓包（roboparty-analyze）

HPM 是板载 EtherCAN 控制器，通过板载 USB Hub 接入 RK3588。EtherCAN 固件、
HPM 维护工具和 USB 抓包功能需要另行安装 `roboparty-analyze`。其固件位于：

```text
${ROBOOS_PREFIX:-/opt/roboparty}/lib/firmware/ethercanfd_v1.0.5-20260829.bin
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

固件刷写脚本 `${ROBOOS_PREFIX:-/opt/roboparty}/bin/flash_hpm.sh` 属于维护入口，应在明确固件和设备
状态后手动使用。

USB 抓包默认关闭。问题复现时可把未压缩环形 pcap 保存在 `/run/usbcan`，默认上限
为 `8 x 64 MiB = 512 MiB`；故障后再复制快照到磁盘并离线分析：

```bash
sudo systemctl start usbcan-capture.service
sudo usbcan-debug-snapshot
sudo systemctl stop usbcan-capture.service

analyze-ethercan-pcap /var/lib/robopi/usbcan-snapshots/<快照目录>
```

启动 USB 抓包时会同时以 115200 波特率记录 `/dev/ttyS4` 上的 HPM 日志，快照内
保存为 `hpm-uart-journal.txt`。

配置、依赖、抓包过滤器和资源开销见
`/usr/share/doc/roboparty-analyze/usbcan-dump.md.gz`。

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

## 安装

安装前先确认架构。这个包只支持 ARM64，并要求 RoboPi BSP 已包含 WS2812 和
AIC8800 驱动：

```bash
dpkg --print-architecture
sudo apt install ./robopi-addon_*_arm64.deb
```

安装后建议检查：

```bash
systemctl --failed
systemctl status robopi-bms-gpio.service
systemctl status robopi-wifi-autoselect.service
journalctl -b -p warning
```

## 构建与测试

ARM64 板上原生构建：

```bash
sudo apt install build-essential debhelper fakeroot
dpkg-buildpackage -us -uc -b
```

在 x86_64/EPYC 主机上交叉构建 ARM64 包：

```bash
sudo apt install build-essential debhelper fakeroot \
  gcc-aarch64-linux-gnu libc6-dev-arm64-cross
dpkg-buildpackage -us -uc -b -aarm64
```

不访问硬件的回归测试：

```bash
bash tests/usb-wifi-init-test.sh
bash tests/wifi-autoselect-test.sh
python3 tests/bms-gpio-test.py
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

BSP 驱动不可用时，检查 BSP 内核配置和 `dmesg`；网络异常时，先运行
`robopi-wifi-select status`，再查看 Wi-Fi 服务的本次启动日志。

## 卸载

```bash
sudo apt remove robopi-addon
sudo apt purge robopi-addon
```

卸载脚本会停止灯带和风扇服务，不会修改 BSP 自带的内核模块。已有
的 NetworkManager 连接配置以及运行期间生成的诊断快照不会被主动删除。
