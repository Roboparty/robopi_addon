# USB-CAN usbmon 抓包分析

本目录保存 Linux `usbmon` 抓包的分析脚本和结果，主要用于检查 RoboPi HPM
EtherCANFD 的 USB Bulk URB 是否丢失、溢出，以及错误后接收 URB 是否重新提交。

## 目录内容

```text
log/
├── usbmon_analyze.py       # 分析单个 pcap/pcapng 的 USB URB 状态
├── compare_usbmon.py       # 对比修复前后的两个抓包
├── analyze_timeline.py     # 按时间窗口统计流量、错误和最大断流
├── extract_error_windows.py # 截取错误前后的小型 pcapng
├── live_status.py          # 在线通信状态终端控制面板
├── check_snapshot.sh       # 检查 snapshot 文件和辅助日志
├── usbcan-all.pcap         # 修复前抓包，不提交到 Git
├── usbcan-merged.pcap      # 修复后合并抓包，不提交到 Git
├── usbcan-merged-classic.pcap # 传统 pcap，不提交到 Git
└── results/
    ├── comparison.md       # 对比报告
    ├── *.summary.json      # 完整统计结果
    └── *.errors.csv        # 非零 Complete/Error URB
```

抓包文件体积较大，统一放在 `log/`，并由 `.gitignore` 排除：

```text
usbcan-all.pcap             # 修复前抓包
usbcan-merged.pcap          # 修复后合并抓包，pcapng 格式
usbcan-merged-classic.pcap  # 转换后的传统 pcap，供 CAN 帧分析器使用
```

## 环境依赖

```bash
sudo apt-get update
sudo apt-get install -y tshark wireshark-common
```

检查工具：

```bash
tshark --version
capinfos --version
mergecap --version
```

## 在线状态控制面板

在板端集中查看服务、CAN 收发速率、错误计数、抓包文件和 HPM 串口日志：

```bash
sudo ./log/live_status.py --can can3
```

按 `Ctrl-C` 退出。实际接口不是 `can3` 时通过 `--can` 指定。

## 板端保存快照

先启动循环抓包，复现问题后将快照保存到 `/home/robo`：

```bash
sudo systemctl start usbcan-capture.service

sudo USBCAN_SNAPSHOT_DIR=/home/robo/usbcan-snapshots \
  usbcan-debug-snapshot
```

命令会输出带时间戳的实际目录，例如：

```text
/home/robo/usbcan-snapshots/20260912-093022
```

默认 snapshot 位置空间不足时，先检查分区：

```bash
df -h / /var /home /run
```

## 合并抓包

在板端进入快照目录，将循环文件按数据包时间戳合并：

```bash
cd /home/robo/usbcan-snapshots/20260912-093022
mergecap -F pcap -w usbcan-merged.pcap usbcan.pcap*
sudo chown robo:robo usbcan-merged.pcap
```

必须指定 `-F pcap`。`mergecap` 默认生成 pcapng，而
`analyze-ethercan-pcap` 只支持传统 pcap。本文的 `usbmon_analyze.py` 同时支持
pcap 和 pcapng。

下载到开发机：

```bash
scp robo@192.168.137.9:/home/robo/usbcan-snapshots/20260912-093022/usbcan-merged.pcap \
  /home/robo/roboparty_repo/deb/robopi_addon/log/
```

也可以下载所有分片后在开发机合并：

```bash
scp 'robo@192.168.137.9:/home/robo/usbcan-snapshots/20260912-093022/usbcan.pcap*' \
  /home/robo/usbcan-debug/

mergecap -F pcap -w /home/robo/roboparty_repo/deb/robopi_addon/log/usbcan-merged.pcap \
  /home/robo/usbcan-debug/usbcan.pcap*
```

## 分析单个抓包

在仓库根目录运行：

```bash
cd /home/robo/roboparty_repo/deb/robopi_addon

./log/usbmon_analyze.py log/usbcan-merged.pcap \
  --json log/results/usbcan-merged.summary.json \
  --errors-csv log/results/usbcan-merged.errors.csv
```

脚本自动选择流量最大的 USB Bulk-IN 端点，因此 HPM 重新枚举、Device address
变化后不需要手工修改参数。

## 检查快照

在合并或下载前检查所有循环文件能否读取，并确认辅助日志是否齐全：

```bash
./log/check_snapshot.sh +  /home/robo/usbcan-snapshots/20260912-093022
```

脚本显示每个 PCAP 的包数、时间范围、时间顺序和总大小。损坏的 PCAP 会返回非零
退出码，缺少的辅助日志会标记为 `MISSING`。

## 分析时间线

默认按一秒统计最繁忙的 Bulk-IN 端点：

```bash
./log/analyze_timeline.py log/usbcan-merged.pcap \
  --csv log/results/usbcan-merged.timeline.csv \
  --json log/results/usbcan-merged.timeline.json
```

调整为 100 ms 时间桶：

```bash
./log/analyze_timeline.py log/usbcan-merged.pcap \
  --interval 0.1 \
  --csv log/results/usbcan-merged.timeline-100ms.csv
```

报告包含每个时间桶的 Submit、Complete、成功 Complete、错误和数据量，以及连续
成功 Complete 之间的最大间隔。

## 提取错误窗口

根据 `usbmon_analyze.py` 生成的错误 CSV，截取每次错误前 2 秒、后 5 秒：

```bash
./log/extract_error_windows.py \
  log/usbcan-merged.pcap \
  log/results/usbcan-merged.errors.csv \
  --before 2 --after 5 \
  --output-dir log/results/usbcan-merged-error-windows
```

只截取第一个错误用于快速检查：

```bash
./log/extract_error_windows.py \
  log/usbcan-merged.pcap \
  log/results/usbcan-merged.errors.csv \
  --limit 1 \
  --output-dir /tmp/usbcan-error-window
```

每个窗口保存为独立 pcapng，可直接用 Wireshark 打开；`windows.csv` 记录源帧、
错误状态、起止时间和输出文件。

## 对比两个抓包

```bash
cd /home/robo/roboparty_repo/deb/robopi_addon

./log/compare_usbmon.py log/usbcan-all.pcap log/usbcan-merged.pcap \
  --output-dir log/results
```

输出包括：

- `comparison.md`：适合直接阅读的汇总表和解释。
- `<文件名>.summary.json`：端点、URB、状态码和时间统计。
- `<文件名>.errors.csv`：所有非零 Complete/Error URB，便于逐条定位。

## 分析 CAN 帧

USB URB 分析和 CAN 帧分析是两件事。传统 pcap 可使用 `robopi-addon` 中的分析器：

```bash
python3 scripts/analyze_ethercan_pcap.py \
  log/usbcan-merged-classic.pcap --top 50
```

指定本次捕获的 HPM 位置：

```bash
python3 scripts/analyze_ethercan_pcap.py \
  log/usbcan-merged-classic.pcap --bus 3 --device 8 --top 50
```

## 指标说明

- `errors`：Bulk Complete/Error 记录中的非零 URB 状态。
- `errors_resubmitted`：错误后，相同 URB ID 后续再次出现 Submit。
- `successful_completes_after_last_error`：最后一次错误之后的成功 Complete 数量，用于
  区分“只尝试重提”和“重提后持续恢复收包”。
- `errors_not_resubmitted`：错误后未观察到相同 URB ID 再提交，可能导致 RX URB
  池逐渐缩小。
- `max_observed_pending`：抓包期间观察到的最大在途 URB 数量。抓包可能从通信中途
  开始，因此它只是下界。
- `pending_at_capture_end`：抓包结束时仍在途的 URB。直接停止抓包时非零属于正常
  现象，不能单独判断为泄漏。
- `orphan_completions`：未在当前抓包中看到对应 Submit 的 Complete。抓包从通信中途
  开始时可能出现。
- `urb_lengths`：Submit 请求的缓冲区大小，可用于确认驱动实际使用的 RX buffer。
- `silence_to_capture_end_s`：目标端点最后一条记录到整个抓包结束的间隔。

Submit 记录中的 `-115` 是 `EINPROGRESS`，属于正常状态。脚本只把 Complete 或
Error 记录中的非零状态计为错误。当前报告中的 `-75` 是 `EOVERFLOW`。

## 当前结果

当前 [comparison.md](results/comparison.md) 显示：

- 修复前 `usbcan-all.pcap` 有 15 次 Bulk-IN `-75`，均未观察到同 URB ID 再提交。
- 修复后 `usbcan-merged.pcap` 有 10 次 Bulk-IN `-75`，10 次均观察到同 URB ID
  再提交，Bulk-IN 流量在错误后继续。
- 修复后 HPM 位于 Bus 3、Device 8、Endpoint `0x81`。
- 当前 Submit buffer 仍是 76 字节，不是 512 字节。

这些结果能证明错误后的重新提交路径已执行；是否彻底解决长期运行问题，还需要更长
时间的压力测试和多次抓包对比。
