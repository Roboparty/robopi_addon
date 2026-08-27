# USB / 板载 Wi-Fi 切换

安装新版 robopi-addon 后，通过有线 SSH 或串口执行。切换会断开非选中无线
接口，不能依赖正在被停用的 Wi-Fi SSH 会话。

```bash
# 自动选择唯一的 USB 无线网卡；存在多张时要求显式指定
sudo robopi-wifi-select usb
# 本次测试网卡也可直接指定
sudo robopi-wifi-select usb wlx6c1ff7e149c0
robopi-wifi-select status

# 连接已扫描到的热点（交互输入密码）
sudo nmcli --ask device wifi connect RoboParty ifname wlx6c1ff7e149c0

# 恢复板载 Wi-Fi；USB Wi-Fi 将停用
sudo robopi-wifi-select onboard wlan0
```

选择保存于 `/etc/roboparty/wifi-interface`，wifi-reset.service 会读取它，
重启后仍只监控那个接口。NetworkManager 配置保存在
`/etc/NetworkManager/conf.d/90-robopi-wifi-select.conf`。
其他无线接口设置为 unmanaged，不卸载驱动、不改设备树、不禁用蓝牙，也不影响
有线网络。拔掉选中的 USB 网卡后会等待其重新插入，不会偷偷切回板载无线。
更换不同 MAC 的 USB 网卡或接口名称变化后，需要再次执行选择命令。

保留所有原连接配置及密码；脚本不复制写 Wi-Fi 密码。原来绑定 wlan0 的配置
不会被自动改绑，可用上面的 nmcli 命令为 USB 接口建立连接。

## AP 模式

如果选中的 USB 接口已运行热点，切换命令和重连监控不会主动替换它。
重连监控只尝试启用自动连接的 infrastructure 配置，不会自动创建或选择热点。
如需热点开机启动，单独配置其 autoconnect 并验证，不能认为切换网卡等于开启热点。

```bash
sudo nmcli device wifi hotspot ifname wlx6c1ff7e149c0 con-name RoboPi-AP ssid RoboPi-AP band bg
iw dev wlx6c1ff7e149c0 info
```

## 前提与验收

本功能不下载、编译 AIC 驱动，不自动安装厂商固件或 udev 规则。
需要先确保 USB 网卡从存储模式切换完成，已绑定 aic8800_fdrv，并出现在 iw dev。
软件包增加 eject 与 iw 依赖；已有厂商 aic.rules 可调用 eject 完成模式切换。

```bash
lsusb -t
iw dev
nmcli device status
systemctl status wifi-reset.service --no-pager
journalctl -u wifi-reset.service -n 30 --no-pager
ip -4 address show dev wlx6c1ff7e149c0
ping -I wlx6c1ff7e149c0 -c 5 10.42.0.1
```

最后一条仅为接口绑定测试示例：客户端模式应换改为实际网关地址；AP 模式请从
手机/电脑 ping 板子热点 IP。切换、重启、拔插、AP 保持需在目标板验收。
