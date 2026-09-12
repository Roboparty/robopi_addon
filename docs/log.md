# RoboPi USB-CAN 抓包与分析教程

本教程用于运控或 EtherCAN/HPM 异常时保存 USB 原始通信现场。抓包服务默认关闭，
只在复现问题期间启动。

这里有两类日志，不要混淆：

- `journalctl -u hpm-reset.service`：HPM 在线检测和硬复位日志。
- `usbcan-capture.service`：通过 Linux usbmon 保存 USB-CAN 原始数据包。

## 1. 确认工具

```bash
command -v usbcan-debug-snapshot
command -v analyze-ethercan-pcap
command -v tcpdump

sudo modprobe usbmon
sudo tcpdump -D | grep usbmon
```

如果命令不存在，先安装或升级 `robopi-addon`。单独补充抓包依赖可执行：

```bash
sudo apt-get update
sudo apt-get install -y tcpdump usbutils
```

## 2. 确认 USB-CAN 和 CAN 接口

```bash
lsusb
lsusb -t
ip -details link show type can
```

例如 `lsusb` 显示：

```text
Bus 003 Device 005: ID 1209:2323 ...
```

那么对应 USB 总线抓包接口是 `usbmon3`。其中 Device 编号可能在 HPM 复位或重新
枚举后改变，Bus 编号通常不变。

## 3. 检查配置

配置文件为 `/etc/default/usbcan-capture`，当前默认值为：

```bash
USBMON_IFACE=auto
CAN_INTERFACE=can3
CAPTURE_DIR=/run/usbcan
FILE_SIZE_MB=64
FILE_COUNT=8
```

`USBMON_IFACE=auto` 会沿 `CAN_INTERFACE` 的 sysfs 设备路径自动查找 USB Bus。
如果实际接口不是 `can3`，修改 `CAN_INTERFACE`；也可以将
`USBMON_IFACE` 显式设为 `usbmon3`。

不要使用 `usbmon0`，它会抓取全部 USB Bus，既增加负载，也可能记录无关设备。

抓包文件保存在内存文件系统 `/run/usbcan`。默认最多保留约：

```text
8 x 64 MB = 512 MB
```

文件达到上限后循环覆盖最旧内容。重启或断电会清空 `/run`，故障出现后必须及时
保存快照。

## 4. 开始抓包

本次调试临时启动：

```bash
sudo systemctl start usbcan-capture.service
```

检查服务、日志和环形文件：

```bash
systemctl status usbcan-capture.service --no-pager
sudo journalctl -u usbcan-capture.service -b --no-pager
sudo ls -lh /run/usbcan/
```

正常启动日志类似：

```text
usbcan-capture: recording usbmon3 to /run/usbcan (8 x 64 MB)
```

如果服务反复失败：

```bash
sudo journalctl -fu usbcan-capture.service
ls -l /sys/class/net/can3/device
lsusb -t
```

重点确认 `CAN_INTERFACE` 存在，并且它确实由 USB 设备提供。

### 在线查看通信状态

推荐直接使用仓库提供的终端控制面板：

```bash
cd /home/robo/roboparty_repo/deb/robopi_addon
sudo ./log/live_status.py --can can3
```

控制面板每秒刷新一次，集中显示服务状态、CAN 控制器状态、RX/TX 每秒速率、累计
错误/丢包、环形 pcap 大小和最近 HPM `ttyS4` 日志。只输出一次可执行：

```bash
sudo ./log/live_status.py --can can3 --once
```

如果抓包目录经过自定义，使用：

```bash
sudo ./log/live_status.py --can can3 \
  --capture-dir /run/usbcan
```

最轻量的方式是每秒查看 SocketCAN 链路状态和累计收发计数：

```bash
watch -n 1 'ip -details -statistics link show dev can3'
```

重点观察：

- `state ERROR-ACTIVE`：CAN 控制器处于正常通信状态。
- `RX`、`TX` packets 持续增加：通信仍在进行。
- `errors`、`dropped` 持续增加：链路、USB 或应用处理存在异常。
- `BUS-OFF`：CAN 总线已离线，需要排查接线、波特率和终端电阻。

短时间直接查看 CAN/CAN FD 帧需要安装 `can-utils`：

```bash
sudo apt-get install -y can-utils
timeout 10 candump -L can3
```

`candump` 使用独立 SocketCAN socket，不会抢走应用节点收到的帧，但高流量下持续
打印会增加终端和 CPU 开销，因此建议用 `timeout` 做短时观察。

查看 HPM 的 `ttyS4` 固件日志：

```bash
sudo journalctl -fu hpm-log-capture.service
```

该服务会随 `usbcan-capture.service` 一起启动。若只想确认服务是否正常：

```bash
systemctl is-active usbcan-capture.service hpm-log-capture.service hpm-reset.service
```

需要在线观察 USB Bulk Complete 错误时，先安装 `tshark`，再对实际 USB Bus 执行：

```bash
sudo apt-get install -y tshark
sudo tshark -l -n -i usbmon3 \
  -Y 'usb.transfer_type == 3 && usb.urb_type == 0x43 && usb.urb_status != 0' \
  -T fields \
  -e frame.time -e usb.device_address -e usb.endpoint_address \
  -e usb.urb_status -e usb.data_len
```

这里 `0x43` 是 Complete URB。命令没有输出表示观察期间没有发现非零完成状态；
出现 `-75` 表示 `EOVERFLOW`。`can3` 和 `usbmon3` 必须替换为当前机器的实际接口。
实时 `tshark` 只建议在定位问题时短时运行，长期记录继续使用环形抓包服务。

## 5. 保存故障现场

故障复现后立即执行：

```bash
sudo usbcan-debug-snapshot
```
sudo env USBCAN_SNAPSHOT_DIR=/home/robo/usbcan-snapshots \
    usbcan-debug-snapshot
命令最后输出的路径才是本次真实快照目录，例如：

```text
/var/lib/robopi/usbcan-snapshots/20260911-132307
```

时间戳只是示例。后续分析必须使用命令实际输出的路径，不能照抄教程中的旧时间戳。

快照默认写入根分区上的 `/var/lib/robopi/usbcan-snapshots`，不使用某些 Armbian
系统中容量很小的 `/var/log` zram。脚本会在复制前检查剩余空间；复制中途失败时会
删除本次半成品，并恢复原本运行的抓包服务。

快照期间服务会短暂停止，复制环形 pcap 和诊断信息后恢复到原来的运行状态。检查：

```bash
systemctl is-active usbcan-capture.service
sudo ls -lh /var/lib/robopi/usbcan-snapshots/20260911-132307
```

快照通常包含：

- `usbcan.pcap*`：USB 原始数据包。
- `lsusb.txt` 和 `lsusb-tree.txt`：USB 设备与拓扑。
- `can-interfaces.txt`：CAN 接口状态和统计。
- `usbcan-capture-journal.txt`：本次启动的抓包服务日志。
- `hpm-uart-journal.txt`：本次启动以来的 HPM `ttyS4` 固件日志。
- `dmesg.txt`：内核日志。

## 6. 分析快照

使用刚刚实际生成的目录：

```bash
sudo analyze-ethercan-pcap \
  /var/lib/robopi/usbcan-snapshots/20260911-132307
```

自动选择最新快照可以避免抄错时间戳：

```bash
latest=$(sudo find /var/lib/robopi/usbcan-snapshots \
  -mindepth 1 -maxdepth 1 -type d -printf '%p\n' | sort | tail -1)

printf 'Analyzing: %s\n' "$latest"
sudo analyze-ethercan-pcap "$latest"
```

如果目录为空或变量没有值，先检查：

```bash
sudo find /var/lib/robopi/usbcan-snapshots \
  -mindepth 1 -maxdepth 1 -type d -printf '%p\n' | sort
```

### 按 USB Bus 和 Device 过滤

先查看快照时记录的设备编号：

```bash
sudo cat "$latest/lsusb.txt"
```

假设 HPM 当时是 Bus 3、Device 5：

```bash
sudo analyze-ethercan-pcap "$latest" \
  --bus 3 --device 5 --top 50
```

HPM 复位后 Device 编号可能改变，因此应以该快照中的 `lsusb.txt` 为准。

### 导出 CSV

```bash
sudo analyze-ethercan-pcap "$latest" \
  --bus 3 --device 5 \
  --csv "$latest/usbcan-frames.csv"
```

## 7. 查看快照中的辅助日志

```bash
sudo less "$latest/usbcan-capture-journal.txt"
sudo less "$latest/dmesg.txt"
sudo cat "$latest/can-interfaces.txt"
sudo cat "$latest/lsusb-tree.txt"
```

HPM 自动复位服务的完整 journal 需要单独查看：

```bash
sudo journalctl -u hpm-reset.service -b --no-pager
```

将它与 pcap 时间范围对照，可以判断 USB 通信异常是否发生在 HPM 硬复位前后。

## 8. 停止抓包

调试结束后停止服务：

```bash
sudo systemctl stop usbcan-capture.service
```

确认状态：

```bash
systemctl is-active usbcan-capture.service
```

预期输出为 `inactive`。该服务默认不启用；只有确定需要每次开机持续抓包时才执行：

```bash
sudo systemctl enable --now usbcan-capture.service
```

恢复默认禁用：

```bash
sudo systemctl disable --now usbcan-capture.service
```

## 9. 常见错误

### 快照路径不存在

```text
error: 输入不存在或不是普通文件/目录
```

原因通常是使用了教程中的示例时间戳。列出实际目录后重新分析：

```bash
sudo ls -1 /var/lib/robopi/usbcan-snapshots/
```

### 没有 pcap 文件

```bash
sudo ls -lh /run/usbcan/
sudo journalctl -u usbcan-capture.service -b --no-pager
```

确认服务在故障发生前已经启动，并检查 `USBMON_IFACE` 或
`CAN_INTERFACE` 是否正确。

### 权限不足

快照和 pcap 默认由 root 创建。读取或分析时使用 `sudo`：

```bash
sudo analyze-ethercan-pcap "$latest"
```

### 抓包对运控的影响

服务仅记录、不实时解析或压缩，并使用低 CPU/I/O 调度优先级。默认绑定 CPU 0 和
CPU 1；部署前仍应通过 `lscpu -e` 确认它们没有分配给运控实时线程。不要在运控
运行期间压缩 512 MB 快照。

## 10. 保存到 `/home/robo`、合并并下载到本机

如果默认快照目录空间不足，先确认 `/home` 所在分区有足够空间：

```bash
df -h / /var /home /run
```

将本次快照保存到 `/home/robo/usbcan-snapshots`：

```bash
sudo USBCAN_SNAPSHOT_DIR=/home/robo/usbcan-snapshots \
  usbcan-debug-snapshot
```

命令会输出实际目录，例如：

```text
/home/robo/usbcan-snapshots/20260912-093022
```

此前因空间不足生成的半成品必须确认路径后再删除：

```bash
sudo du -sh /var/log/usbcan-snapshots/20260912-092937
sudo rm -rf /var/log/usbcan-snapshots/20260912-092937
```

### 在板端合并

`mergecap` 由 `wireshark-common` 提供。它会按数据包时间戳合并循环文件，不依赖
`usbcan.pcap0` 到 `usbcan.pcap7` 的文件名顺序：

```bash
sudo apt-get update
sudo apt-get install -y wireshark-common
sudo env USBCAN_SNAPSHOT_DIR=/home/robo/usbcan-snapshots \
    usbcan-debug-snapshot
cd /home/robo/usbcan-snapshots/20260912-093022
mergecap -F pcap -w usbcan-merged.pcap usbcan.pcap*
sudo chown robo:robo usbcan-merged.pcap
ls -lh usbcan-merged.pcap
```

在开发机上下载合并后的文件：

```bash
mkdir -p /home/robo/usbcan-debug
scp robo@192.168.137.9:/home/robo/usbcan-snapshots/20260912-093022/usbcan-merged.pcap \
  /home/robo/usbcan-debug/
```

### 在本机合并

如果不希望在板端安装 `mergecap`，直接下载所有分片：

```bash
mkdir -p /home/robo/usbcan-debug
scp 'robo@192.168.137.9:/home/robo/usbcan-snapshots/20260912-093022/usbcan.pcap*' \
  /home/robo/usbcan-debug/

mergecap -F pcap -w /home/robo/usbcan-debug/usbcan-merged.pcap \
  /home/robo/usbcan-debug/usbcan.pcap*
```

### 本机分析

```bash
analyze-ethercan-pcap \
  /home/robo/usbcan-debug/usbcan-merged.pcap \
  --top 50
```

需要查看 USB URB 原始细节时使用 Wireshark：

```bash
wireshark /home/robo/usbcan-debug/usbcan-merged.pcap
```

第一次分析不要指定 Bus、Device 或 Endpoint。先从分析报告中确认实际 USB 位置，
再使用 `--bus`、`--device` 和 `--endpoint` 缩小范围。
