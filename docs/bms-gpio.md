# BMS 双电池 GPIO 服务

1.6.21 起，robopi-bms-gpio.service 开机启动，并替代、禁用
robopi-hw-test.service 和 robopi-sig-key.service。
不再使用 SIG 短按/长按控制这两个输出。

只读 /tmp/bms.sock，不访问串口、不发送 BMS 控制指令。
GPIO1_B0 和 GPIO0_C2 使用现有设备树的 gpio-leds 接口：
/sys/class/leds/dual_battery_b0/brightness 和 dual_battery_c2/brightness。
两个控制文件依次写入，不承诺硬件同时翻转。

| 事件 | 两个输出 |
| --- | --- |
| 服务启动 | B0 高，C2 低 |
| 完整有效帧 io_state=0x0010000A 或 0x0010000F | B0 高，C2 低 |
| 完整有效帧 io_state=0x00100000 | B0 低，C2 低 |
| 其他有效 io_state（包括0x00000000） | B0 保持，C2 低 |
| socket EOF、连接失败或接收错误 | 高 |
| 没有数据、等待超时、仅收到部分帧 | 保持，不用超时判断断开 |
| 正常停止服务 | 保持最后电平 |

power_on 仅记录日志。连接恢复本身不改变输出，收到完整有效数据后按表处理。
仅改变 B0 的状态策略，SIG GPIO1_D5 的方向/复用不变，不增加 D0 或 D5 输出。
电池拔出但 BMS daemon 仍保持 socket 连接时，输出不会自动变高；
本服务只能检测 socket 通信断开，不能证明物理电池已拔出。
BMS 服务重启或异常退出也可能使输出变高。

要求已安装包含 io_state/power_on 的 packed 126 字节 BatteryStatus 版本。
旧版 121 字节协议不兼容；即使 BMS 包版本号同为1.4.3也不能混用。
启动前检查安装的头文件字段布局，不匹配则报错且不写 GPIO。
头文件与运行的 daemon 必须来自同一构建。协议本身无帧头/版本号。

检查：
```bash
systemctl status robopi-bms-gpio --no-pager
journalctl -u robopi-bms-gpio -n 30 --no-pager
cat /sys/class/leds/dual_battery_b0/brightness
cat /sys/class/leds/dual_battery_c2/brightness
```

GPIO LED 节点必须为 active-high，trigger 为 none。不要同时运行其他
写这些节点的脚本或硬件测试。真实电平需用万用表/示波器确认。
升级/首次启动会将 B0 设高、C2 设低；B0 仅收到明确关机值0x00100000后拉低。
请在允许切换电源控制信号时操作。

目标镜像可能使用 ext4 commit=600。手动部署后必须执行 sudo sync 并等待返回，
再进行断电测试；包安装脚本也会在切换 GPIO 服务前执行 sync。
建议先用 sudo reboot 验证自启动，而不是直接拔电池。
