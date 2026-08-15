# SIG 按键与 LED 联动

原理图只有两路 GPIO：

| 功能 | GPIO | gpiochip3 偏移 | 有效电平 |
|---|---|---:|---|
| 按键 SIG 输入 | GPIO1_D5 | gpiochip1 offset 29 | 高有效 |
| LED 输出 | GPIO0_C2 | gpiochip0 offset 18 | 高有效 |

按键未按下时，R2 将 SIG 下拉为低电平；按下 SW2 后，VCC 经过 R1 接到
SIG，使其变为高电平。C1 用于硬件滤波。程序检测到 SIG 为高时点亮 LED，
并输出一次 `KEY_PRESSED`；SIG 恢复低电平时熄灭 LED。

> 原理图中的 VCC 必须为 3.3V，不允许向 RK3588 GPIO 输入 5V。

## 前台测试

```bash
sudo robopi-sig-key
```

正常启动会显示当前状态：

```text
Started: SIG=0, LED=0. Button is active when SIG is high.
```

按下按键时应显示：

```text
SIG active -> LED on
KEY_PRESSED
```

松开按键时应显示：

```text
SIG inactive -> LED off
```

按 `Ctrl+C` 退出，程序会关闭 LED。

## 参数

```bash
robopi-sig-key --help
sudo robopi-sig-key --debounce-ms 30
sudo robopi-sig-key --on-press '/opt/my-app/start.sh'
```

如果硬件电平极性不同，可以使用：

```bash
sudo robopi-sig-key --sig-active-low
sudo robopi-sig-key --led-active-low
```

## systemd 服务

确认前台测试正确后再启用：

```bash
sudo systemctl enable --now robopi-sig-key.service
journalctl -u robopi-sig-key.service -f
```

默认服务命令为：

```text
/usr/bin/robopi-sig-key --sig-chip /dev/gpiochip1 --sig 29 --led-chip /dev/gpiochip0 --led 18
```
