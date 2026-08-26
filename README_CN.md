# robopi-addon

[English](README.md)

RoboPi RK3588S 平台的附加工具包，包含 WS2812 灯带控制和 SIG/按键 GPIO 辅助工具，
不依赖 `roboparty-base`。

- `robopi-ws2812`：通过 PWM6_M1 控制 12 颗串联 WS2812B-MINI-V3/W 灯珠
- `robopi-sig-key`：SIG 上升沿触发 LED 输出与按键处理
- `robopi-ethernet-mac`：从 RK3588 Chip ID 派生并应用稳定的以太网 MAC

本软件包不会安装或修改设备树。使用前需要确保系统已经启用 PWM6_M1。

## 包含内容

- `robopi-ws2812` 命令行控制程序
- 常亮、闪烁、流水灯、彩虹和综合演示效果
- `robopi-sig-key` SIG/按键 GPIO 辅助程序
- 支持 ARM64 原生构建
- 随软件包安装适配 Linux 6.1.99-rt36-rockchip-rk3588 的预编译内核模块
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

软件包会启用沿用旧名称的 `robopi-ws2812-white.service`。开机加载内核模块后，
该服务会将全部灯珠设置为蓝色（`0 0 255`）；停止服务时会关闭灯带：

```bash
systemctl status robopi-ws2812-white.service
sudo systemctl stop robopi-ws2812-white.service
sudo systemctl start robopi-ws2812-white.service
```

请确认电源和连接线能够承受 12 颗灯珠的总电流。

持续运行的效果可以按 `Ctrl+C` 停止，程序退出前会自动熄灭灯带。

## 参数说明

| 参数 | 范围 | 说明 |
|---|---:|---|
| `R G B` | `0-255` | 红、绿、蓝三种颜色的亮度 |
| `间隔毫秒` / `步进毫秒` | `10-60000` | 动画每一步的时间 |
| `次数` | `0-1000000` | 闪烁次数；`0` 表示持续运行 |
| `亮灯宽度` | `1-12` | 流水灯同时点亮的灯珠数量 |

建议先使用 `16-64` 的较低 RGB 数值测试，避免电源电流过大。

## 构建 deb 包

软件包包含固定目标内核的预编译模块：

```text
prebuilt/6.1.99-rt36-rockchip-rk3588/robopi-ws2812.ko
```

在 ARM64 板子上构建软件包：

```bash
sudo apt install build-essential debhelper
dpkg-buildpackage -us -uc -b
```

`.deb` 安装包会生成在项目的上一级目录中。

## 安装

软件包直接安装预编译模块，不需要 DKMS 或目标机器上的内核头文件：

```bash
sudo apt install ../robopi-addon_*_arm64.deb
```

模块安装到 `/lib/modules/6.1.99-rt36-rockchip-rk3588/extra/`，并通过
`/etc/modules-load.d/robopi-ws2812.conf` 在开机时加载。升级内核后必须针对新内核
重新编译 `.ko` 并发布新版软件包。

## 稳定以太网 MAC 实验

`robopi-ethernet-mac` 从 `/proc/cpuinfo` 的 RK3588 `Serial` 派生一个稳定的
locally administered 单播 MAC。Chip ID 不会直接作为 MAC 暴露。

软件包会启用 `robopi-ethernet-mac.service`，下次开机时自动应用派生 MAC 并重新
请求 DHCP。安装过程中不会立即启动该服务，因此不会在安装 deb 时中断当前网络。
默认网卡在 `/etc/default/robopi-ethernet-mac` 中配置：

```bash
ETHERNET_INTERFACE=enP4p65s0
ETHERNET_WAIT_SECONDS=60
```

开机时工具最多等待上述秒数，直到 NetworkManager 在指定网卡上建立活动连接；
如果 NetworkManager 仍未准备好，systemd 服务会在 5 秒后自动重试。

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

卸载时会卸载正在运行的模块并刷新目标内核的模块依赖索引。

## 编译时自定义配置

以下设置位于内核模块 `src/robopi-ws2812.c` 文件开头，修改后需要重新构建：

```c
#define LED_COUNT       12
#define PWM6_PHYS       0xfebd0020
#define WS2812_PERIOD_NS 1250
#define WS2812_T0H_NS     330
#define WS2812_T1H_NS     650
#define WS2812_RESET_US   300
```

驱动加载时会根据实际 PWM 时钟自动计算寄存器计数值，并使用连续 PWM 与锁存
占空比更新，避免逐 bit one-shot 产生额外低电平间隔。24 MHz 时为 30/8/16
ticks。必须使用示波器验证实际输出波形。

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

## FAN_SW 风扇开关

FAN_SW 使用 GPIO1_D7（全局 GPIO63）。根据板卡原理图，该控制信号为高电平有效：高电平接通 `VCC_5V_FAN`，低电平关闭风扇电源。

```bash
# 开启风扇
sudo robopi-fan on

# 关闭风扇
sudo robopi-fan off

# 查看当前状态
robopi-fan status
```

程序使用 GPIO sysfs 接口保持输出状态。软件包会启用 `robopi-fan.service`，开机时自动将 FAN_SW 设置为高电平并启动风扇。停止该服务会关闭风扇：

```bash
systemctl status robopi-fan.service
sudo systemctl stop robopi-fan.service
sudo systemctl start robopi-fan.service
```
