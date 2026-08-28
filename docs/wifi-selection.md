# USB / 板载 Wi-Fi 切换

## 1.6.19 起：USB 自动选择

默认启用 USB 优先：安装软件包、开机及 USB 无线接口出现时自动扫描。
udev 仅匹配 USB 无线接口，通过 SYSTEMD_WANTS 启动
`robopi-wifi-autoselect.service`；不会匹配 USB 有线网卡或 CAN 设备。
服务等待 NetworkManager 发现接口后保存新接口名，停用其他无线接口并更新重连监控。
更换不同 MAC 的 USB 网卡无需再指定旧接口名。

安装/插入 USB 网卡会断开板载 Wi-Fi，请用有线 SSH 或串口操作。
无 USB 时不修改配置；多个 USB 时保留仍在场的已选网卡，否则不自动猜选。
拔掉已选 USB 不自动恢复板载无线。其他接口已运行 AP 时跳过自动切换，
需要手动选择或关闭 AP 后再运行 auto。

```bash
# 恢复自动 USB 优先并立即扫描
sudo robopi-wifi-select auto
# 选择板载，同时持久暂停 USB 自动切换
sudo robopi-wifi-select onboard wlan0
robopi-wifi-select status
journalctl -b -u robopi-wifi-autoselect.service --no-pager
```

自动切换不等于自动知道 Wi-Fi 密码：首次连接仍需 nmcli --ask。
旧连接若绑定了旧接口名/MAC，不会强行改写，新网卡可能仍需连接一次。
已选接口的连接/AP 保留。一次性服务成功后 inactive (dead) 正常，
请结合日志和 nmcli device status 验证。

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
1.6.19 自动模式会识别更换后的 USB 网卡；手动模式需再次选择或恢复 auto。

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

从 1.6.18 起，软件包内置当前目标内核的 AIC8800 驱动、固件和 udev 规则，
无需手动编译安装。详情及内核限制见 [USB 驱动说明](usb-wifi-bundle.md)。
选择网卡前仍需确认 USB 已绑定 aic8800_fdrv，并出现在 iw dev。

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
