# roboparty-ws2812

[English](README.md)

RoboParty RK3588S 平台的独立 WS2812 控制包。程序通过 PWM6_M1 控制
18 颗串联灯珠，不依赖 `roboparty-base`。

本软件包不会安装或修改设备树。使用前需要确保系统已经启用 PWM6_M1。

## 包含内容

- `roboparty-ws2812` 命令行控制程序
- 常亮、闪烁、流水灯、彩虹和综合演示效果
- 支持 ARM64 原生构建和 amd64 到 ARM64 交叉构建
- 用于安装和卸载的 Debian 软件包配置

## 控制命令

程序需要访问 `/dev/mem` 和 PWM sysfs 接口，因此必须使用 root 权限运行。

```bash
# 使用默认低亮度白色开灯（48, 48, 48）
sudo roboparty-ws2812 on

# 使用自定义 RGB 颜色开灯
sudo roboparty-ws2812 on 255 80 0

# 关灯
sudo roboparty-ws2812 off

# 常亮：R G B
sudo roboparty-ws2812 solid 255 0 0

# 闪烁：R G B [间隔毫秒] [次数]
# 次数省略或设为0：持续运行，直到按 Ctrl+C
sudo roboparty-ws2812 flash 0 255 0 500 10
sudo roboparty-ws2812 flash 0 0 255 200

# 流水灯：R G B [步进毫秒] [亮灯宽度]
sudo roboparty-ws2812 chase 0 0 255 80 3

# 彩虹灯：[步进毫秒]
sudo roboparty-ws2812 rainbow 40

# 短时间综合演示，结束后自动熄灯
sudo roboparty-ws2812 demo

# 查看帮助
roboparty-ws2812 --help
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
chmod +x build-deb.sh
./build-deb.sh
```

在 amd64 Ubuntu 电脑上交叉构建：

```bash
sudo apt install build-essential debhelper crossbuild-essential-arm64
chmod +x build-deb.sh
./build-deb.sh
```

`.deb` 安装包会生成在项目的上一级目录中。

## 安装

```bash
sudo apt install ../roboparty-ws2812_*_arm64.deb
```

## 卸载

```bash
sudo apt remove roboparty-ws2812
sudo apt purge roboparty-ws2812
```

## 编译时自定义配置

以下设置位于 `src/ws2812_pwm6.c` 文件开头，修改后需要重新构建：

```c
#define LED_COUNT       18
#define PWM6_ADDR       0xfebd0020u
#define PWMCHIP_DIR     "/sys/class/pwm/pwmchip2"

static uint32_t period_ticks = 30;
static uint32_t zero_ticks = 8;
static uint32_t one_ticks = 19;
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
