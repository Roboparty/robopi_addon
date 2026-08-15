# SIG、LED 与按键联动

`robopi_addon` 现在会同时生成两个程序：

- `roboparty-ws2812`：原有的 WS2812 灯带程序。
- `robopi-sig-key`：新增的 SIG 检测、LED 控制和按键门控程序。

## 默认引脚

| 功能 | GPIO | gpiochip3 偏移 | 默认有效电平 |
|---|---|---:|---|
| SIG 输入 | GPIO3_B1 | 9 | 高有效 |
| LED 输出 | GPIO3_B6 | 14 | 高有效 |
| 按键输入 | GPIO3_B4 | 12 | 低有效 |

程序逻辑如下：SIG 有效时 LED 点亮；SIG 无效时 LED 熄灭；只有 SIG 有效、LED 点亮期间按键才有效。有效按键会输出 `KEY_PRESSED`，也可以启动指定命令。

## 编译与直接运行

```bash
cd robopi_addon
make
sudo ./build/robopi-sig-key
```

按键有效时启动业务程序：

```bash
sudo ./build/robopi-sig-key --on-press '/opt/my-app/start.sh'
```

GPIO3_B5 的偏移是 13。如果按键接在 B5：

```bash
sudo ./build/robopi-sig-key --key 13
```

其他常用配置：

```bash
# LED 低电平点亮
sudo ./build/robopi-sig-key --led-active-low

# SIG 低有效
sudo ./build/robopi-sig-key --sig-active-low

# 按键高电平有效
sudo ./build/robopi-sig-key --key-active-high
```

## Debian 包与开机服务

构建并安装项目原有的 Debian 包后，两个程序和 `robopi-sig-key.service` 都会被安装。服务不会在安装时强制启动，需要确认接线后手动启用：

```bash
sudo systemctl enable --now robopi-sig-key.service
journalctl -u robopi-sig-key.service -f
```

如果需要按键启动业务程序，执行：

```bash
sudo systemctl edit robopi-sig-key.service
```

填入：

```ini
[Service]
ExecStart=
ExecStart=/usr/bin/robopi-sig-key --chip /dev/gpiochip3 --sig 9 --led 14 --key 12 --on-press /opt/my-app/start.sh
```

然后运行：

```bash
sudo systemctl daemon-reload
sudo systemctl restart robopi-sig-key.service
```

注意：GPIO 只能使用 3.3 V 电平。默认按键接在 GPIO3_B4 和 GND 之间，并通过约 10 kΩ 上拉到 3.3 V。
