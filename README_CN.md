# robopi-addon

[English](README.md)

RoboPi RK3588S 平台的附加工具包，包含 WS2812 灯带控制和 SIG/按键 GPIO 辅助工具，
不依赖 `roboparty-base`。

- `robopi-ws2812`：通过 PWM6_M1 控制 18 颗串联 WS2812 灯珠
- `robopi-sig-key`：SIG 上升沿触发 LED 输出与按键处理
- `robopi-ethernet-mac`：从 RK3588 Chip ID 派生并应用稳定的以太网 MAC

本软件包不会安装或修改设备树。使用前需要确保系统已经启用 PWM6_M1。

## 包含内容

- `robopi-ws2812` 命令行控制程序
- 常亮、闪烁、流水灯、彩虹和综合演示效果
- `robopi-sig-key` SIG/按键 GPIO 辅助程序
- 支持 ARM64 原生构建
- 通过 DKMS 安装内核模块，内核升级时自动重新编译
- 用于安装和卸载的 Debian 软件包配置

## 控制命令

程序通过内核模块设备节点 `/dev/robopi-ws2812` 发送 GRB 帧，必须使用 root 权限运行。

```bash
# 使用默认低亮度白色开灯（48, 48, 48）
sudo robopi-ws2812 on

# 使用自定义 RGB 颜色开灯
sudo robopi-ws2812 on 255 80 0

# 关灯
sudo robopi-ws2812 off

# 常亮：R G B
sudo robopi-ws2812 solid 255 0 0

# 闪烁：R G B [间隔毫秒] [次数]
# 次数省略或设为0：持续运行，直到按 Ctrl+C
sudo robopi-ws2812 flash 0 255 0 500 10
sudo robopi-ws2812 flash 0 0 255 200

# 流水灯：R G B [步进毫秒] [亮灯宽度]
sudo robopi-ws2812 chase 0 0 255 80 3

# 彩虹灯：[步进毫秒]
sudo robopi-ws2812 rainbow 40

# 短时间综合演示，结束后自动熄灯
sudo robopi-ws2812 demo

# 查看帮助
robopi-ws2812 --help
```

持续运行的效果可以按 `Ctrl+C` 停止，程序退出前会自动熄灭灯带。

## 参数说明

| 参数 | 范围 | 说明 |
|---|---:|---|
| `R G B` | `0-255` | 红、绿、蓝三种颜色的亮度 |
| `间隔毫秒` / `步进毫秒` | `10-60000` | 动画每一步的时间 |
| `次数` | `0-1000000` | 闪烁次数；`0` 表示持续运行 |
| `亮灯宽度` | `1-18` | 流水灯同时点亮的灯珠数量 |

建议先使用 `16-64` 的较低 RGB 数值测试，避免电源电流过大。

## 构建 deb 包

在 ARM64 板子上原生构建：

```bash
sudo apt install build-essential debhelper
dpkg-buildpackage -us -uc -b
```

`.deb` 安装包会生成在项目的上一级目录中。

## 安装

内核模块在安装时由 DKMS 针对当前运行内核编译，因此目标机器上需要安装对应的内核头文件：

```bash
sudo apt install dkms linux-headers-$(uname -r)
sudo apt install ../robopi-addon_*_arm64.deb
```

内核升级时 DKMS 会自动重新编译 `robopi-ws2812`。模块通过
`/etc/modules-load.d/robopi-ws2812.conf` 在开机时加载。

## 稳定以太网 MAC 实验

`robopi-ethernet-mac` 从 `/proc/cpuinfo` 的 RK3588 `Serial` 派生一个稳定的
locally administered 单播 MAC。Chip ID 不会直接作为 MAC 暴露。

软件包会启用 `robopi-ethernet-mac.service`，下次开机时自动应用派生 MAC 并重新
请求 DHCP。安装过程中不会立即启动该服务，因此不会在安装 deb 时中断当前网络。
默认网卡在 `/etc/default/robopi-ethernet-mac` 中配置：

```bash
ETHERNET_INTERFACE=enP4p65s0
```

首次重启前建议通过串口执行只读检查：

```bash
robopi-ethernet-mac check
robopi-ethernet-mac status
```

如果 Chip ID 为空、格式无效或全零，工具会拒绝继续。`Derived MAC` 和
`Check MAC` 应完全相同。

应用派生 MAC 会中断有线网络并重新请求 DHCP 地址，建议通过串口执行：

```bash
sudo robopi-ethernet-mac apply
```

如网卡名称不同，可将其作为第二个参数：

```bash
sudo robopi-ethernet-mac apply enP4p65s0
```

恢复 NetworkManager 的默认永久 MAC 策略：

```bash
sudo robopi-ethernet-mac restore
```

工具不会删除 `/var/lib/NetworkManager` 中的 DHCP lease。请分别在不同板卡上
记录 `Chip ID`、`Derived MAC` 和获得的 IPv4 地址，以验证板卡身份和地址均不同。

查看开机服务结果：

```bash
systemctl status robopi-ethernet-mac.service
journalctl -u robopi-ethernet-mac.service -b
```

## 卸载

```bash
sudo apt remove robopi-addon
sudo apt purge robopi-addon
```

卸载脚本会移除 DKMS 模块，从而一并删除所有内核上已编译安装的驱动。

## 编译时自定义配置

以下设置位于内核模块 `src/robopi-ws2812.c` 文件开头，修改后需要重新构建：

```c
#define LED_COUNT       18
#define PWM6_PHYS       0xfebd0020
#define PERIOD_TICKS    18
#define ZERO_TICKS      6
#define ONE_TICKS       12
```

修改 WS2812 时序参数后，必须使用示波器验证实际输出波形。

## SIG 上升沿触发 LED

| 功能 | GPIO | GPIO字符设备 | 有效状态 |
|---|---|---|---|
| SIG输入 | GPIO1_D5 | `/dev/gpiochip1` offset 29 | 上升沿 |
| LED输出 | GPIO0_C2 | `/dev/gpiochip0` offset 18 | 高电平点亮 |

`robopi-sig-key`启动时保持LED熄灭。SIG从低电平变为高电平时，程序检测上升沿并点亮LED；SIG随后恢复低电平不会直接熄灭LED。程序退出时会自动熄灭LED。

> SIG输入电压不得超过GPIO1_D5所在IO电源域的允许范围，禁止直接输入5V。

### 前台测试

默认在上升沿后锁存点亮：

```bash
sudo robopi-sig-key
```

正常启动和触发输出：

```text
Started: waiting for SIG rising edge; LED is off.
SIG rising edge -> LED on
KEY_PRESSED
```

按 `Ctrl+C` 退出并熄灭LED。

### 定时熄灭

每次上升沿触发后点亮LED 1000毫秒：

```bash
sudo robopi-sig-key --led-on-ms 1000
```

### 其他参数

```bash
robopi-sig-key --help
sudo robopi-sig-key --debounce-ms 30
sudo robopi-sig-key --on-press '/opt/my-app/start.sh'
sudo robopi-sig-key --sig-active-low
sudo robopi-sig-key --led-active-low
```

### systemd 服务

确认前台测试正常后，可以启用开机自启动服务：

```bash
sudo systemctl enable --now robopi-sig-key.service
journalctl -u robopi-sig-key.service -f
```
