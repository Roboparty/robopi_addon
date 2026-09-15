# AIC USB 无线网卡支持

支持已验证的 UGREEN AX300 / AIC8800DC。`aic_load_fw` 和 `aic8800_fdrv`
内核驱动由 RoboPi BSP 提供，本包不再安装或加载内核模块。

安装 `sudo apt install ./robopi-addon_<version>_arm64.deb` 后，无需另行编译驱动：

- 启用 `robopi-usb-wifi.service`，处理已经插入的虚拟存储设备。
- 已插入的 AIC 存储设备按 USB VID/PID 匹配处理，不弹出其他磁盘。

从 1.6.19 起默认自动选择 USB 网卡并停用其他无线接口，详情见
[网卡自动选择](wifi-selection.md)。不复制密码，不抢占其他接口正在使用的热点。
手动选择 USB 接口仍可使用以下命令（通过有线 SSH 或串口）：

```bash
sudo robopi-wifi-select usb
sudo nmcli --ask device wifi connect RoboParty ifname wlx6c1ff7e149c0
```

诊断：

```bash
systemctl status robopi-usb-wifi --no-pager
journalctl -b -u robopi-usb-wifi --no-pager
lsusb -t
iw dev
```

服务成功仅表示准备命令完成；实际 USB 识别以 `iw dev`、扫描及连接测试为准。
没有 USB 网卡也可以安装；后续插入依靠 udev 规则和 BSP 驱动识别。

## 来源及复现

驱动和固件均由 BSP 提供，本仓库不再保存或再分发厂商驱动归档。
