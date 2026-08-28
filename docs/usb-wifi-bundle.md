# AIC USB 无线网卡内置驱动（1.6.18）

支持已验证的 UGREEN AX300 / AIC8800DC，ARM64 内核版本必须为
`6.1.99-rt36-rockchip-rk3588`。相同版本字符串仍要求兼容的内核配置和符号 ABI；
换内核时必须重新编译、测试并更新预编译文件及 SHA256，不能强制加载。

安装 `sudo apt install ./robopi-addon_1.6.18-1_arm64.deb` 后，无需另行编译驱动：

- 包含 `aic_load_fw.ko`、`aic8800_fdrv.ko`。
- 从原厂归档安装 `/lib/firmware/aic8800DC` 固件。
- 安装 `/etc/udev/rules.d/aic.rules`，针对 AIC 虚拟存储盘自动执行 eject。
- 刷新目标内核模块索引，启用 `robopi-usb-wifi.service`。
- 在线安装和开机时加载驱动；chroot 镜像制作时不加载构建宿主机模块。
- 已插入的 AIC 存储设备按 USB VID/PID 匹配处理，不弹出其他磁盘。

旧系统手动创建过 aic.rules 时，dpkg 可能询问保留配置还是采用维护者版本。
先备份自定义规则；若只包含旧 AIC 规则，可采用新版。不要同时添加重复规则。

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
没有 USB 网卡也可以安装；后续插入依靠 udev 规则和模块别名识别。
内核不匹配时明确跳过加载，不为不同内核复制模块。

## 来源及复现

原始归档为用户提供的 `UGREEN_AIC-AX300_LinuxDriver_V1.6.zip`，保存在
`prebuilt/`，并随二进制包放入 `/usr/share/doc/robopi-addon/vendor/`。
归档包含本次编译使用的驱动源码及固件，校验值在 `prebuilt/aic8800.sha256`。
模块于 2026-08-27 在 RoboPi2 目标内核上原生编译，未修改厂商源码：

```bash
unzip UGREEN_AIC-AX300_LinuxDriver_V1.6.zip
cd aic8800_linux_drvier/drivers/aic8800
make
```

模块元数据声明 GPL；厂商文件保留其原始声明，不按本项目 GPL-3.0 重新授权。
归档未发现独立固件再分发许可证。对外发布捆绑包前须确认厂商固件及附带文档的
再分发许可；保留原始归档本身不等于取得该许可。
