# PMIC 双目标 Pinout 与功能清单

更新日期：2026-11-11。当前实物只有一颗 STM32F103C8；GD32F503VET6 是按软件先定义
引脚的参考目标，尚无对应实板。安装包提供来自
[`roboparty_pmic v0.1.13`](https://github.com/Roboparty/roboparty_pmic/releases/tag/v0.1.13)
的 STM32F103C8 工程候选固件；GD32F503VET6 仍沿用 v0.1.11 候选，
STM32 版本号已去掉历史 `-left` 后缀。

## STM32F103C8 固件

| 项目 | 当前硬件 |
| --- | --- |
| MCU | STM32F103C8T6，8 MHz HSE，72 MHz 系统时钟 |
| 应用版本 | `0.1.10`，v0.1.13 工程候选，2026-11-11 经 USART1 OTA 烧录、SWD 回读匹配、串口 HIL 6/6 |
| 固件位置 | `firmware/pmic/candidate/stm32f103c8/` |
| Bootloader | `boot.bin`，烧录到 `0x08000000` |
| 应用 | `ChargeBAT.bin`，烧录到 `0x08001000` |
| 配置页 | `0x0800FC00` |
| 更新方式 | 首次通过 CMSIS-DAP/SWD 安装 bootloader；后续 USART1（PA9/PA10）串口 OTA，支持中断后重传，不支持自动回滚 |

安装 addon 不会自动烧录 PMIC。可运行
`robopi-pmic-ota verify-bundle --bundle ${ROBOOS_PREFIX:-/opt/roboparty}/share/pmic/candidate/stm32f103c8/manifest.json`
核对镜像 SHA-256、Flash 边界、向量和内嵌版本号。`robopi-pmic-ota inspect --port /dev/ttyUSB0`
通过 USART1（PA9/PA10，RK3588 UART7 `/dev/ttyS7`）只读查询芯片 UID 和固件版本。

## 引脚

方向以 MCU 为参照。下表记录固件实际分配；未用脚不代表硬件上可自由复用。
PA4–PA7 为普通 GPIO 输出，没有 LED PWM。

| 引脚 | 当前用途 | 模式 / 行为 |
| --- | --- | --- |
| PA0 | `I_IN` 充电电流采样 | ADC1 IN0 |
| PA1 | `U_BAT` 电池电压采样 | ADC1 IN1；PA6/PA7 按引脚原始电压判断 |
| PA2 | `U_IN` 输入电压采样 | ADC1 IN2 |
| PA3 | `ICTRL` 充电电流控制 | TIM2 CH4 PWM |
| PA4 | 充电红灯 | 充电使能且电池输出电压 >=54V 时拉高 |
| PA5 | 充电绿灯 | 充电使能且电池输出电压 <54V 时拉高 |
| PA6 | `BAT_G` 指示灯 | PA1 引脚电压在 1.39–1.50V 时拉高 |
| PA7 | `BAT_R` 指示灯 | PA1 引脚电压在 1.21–<1.39V 时拉高 |
| PA8 | 风扇 | TIM1 CH1 PWM |
| PA9/PA10 | 主机 TX/RX | USART1，115200 8N1，接 RK3588 UART7 `/dev/ttyS7` |
| PA13/PA14 | SWDIO/SWCLK | 调试接口，保留 |
| PB3 | `EN` 充电使能 | GPIO 输出，写 1 表示使能 |
| PB4 | 未连接 | 固件不配置、不读取 |
| PB8/PB9 | CH224/TMP100 SCL/SDA | 软件 I2C |
| PB10/PB11 | 未用 | 当前 left 构建不初始化 USART3 |
| PD0/PD1 | 8 MHz 晶振 | HSE 输入/输出 |
| NRST/BOOT0 | 复位/启动选择 | 硬件接口 |

PA11、PA12、PA15、PB0–PB2、PB5–PB7、PB12–PB15 等未在当前固件中分配。
电源和地脚仍须依照原理图连接。灯色已逐脚目视确认，实际电压未用外部仪表核验。

## 功能与验证

| 功能 | 当前行为 | 验证状态 |
| --- | --- | --- |
| 自动充电 | 有效 ADC 连续采样、输入 16–<32V、CH224 有电流能力且无故障时使能 PB3/PA3 | `0.1.8-left` 在 5V 关闭、20V PD 打开；未接电池包 |
| 充电灯 | PA5 绿灯到 54V；PA4 红灯从 54V 起；禁用充电时均关闭 | 四路 GPIO 逐脚实物灯色确认；20V 空载时只有充电红灯亮；低于 54V 的带载绿灯未测 |
| PA1 电压灯 | 1.39V 归 PA6；1.21–<1.39V 归 PA7；区间外或采样失败均关闭 | PA6/PA7 实物灯色确认；电压阈值单测通过，未安全注入 PA1 实测 |
| 主机协议 | USART1（PA9/PA10），ASCII `NAME:DATA;`；`SN_GET`、`FW_VER`、`CHRG_INFO`、`SYS_INFO` | 新镜像经 A100 只读 HIL 6/6 通过 |
| BMS/电池在位 | 无外置 BMS/485 与 PB4 输入；兼容查询返回占位或 `BMS_DISABLED;` | 代码确认 |
| 风扇/温度 | PA8 PWM；PB8/PB9 读取 TMP100 | 带载行为待测 |
| 配置保存 | `SAVE:1;` 写内部 Flash 配置页 | 断电保持待测 |
| 串口 OTA | `OTA_ENTER` 切换 bootloader；分块写入、CRC32 校验，首个应用页最后提交 | RK3588 UART7（`/dev/ttyS7`）实测成功；旧记录为 COM82/A100 |

54V 只切换灯，不是充满截止条件。电池包须有独立充电截止保护。
带载电流、充满截止、ADC 精度、温升、实际灯色和输出电平仍需实板验证。

源码位置：`boards/stm32f103_pmic/{pinout.h,board.c,drivers/adc.c,drivers/pwm.c}`、
`common/app/src/{app_charge.c,app_config.c,app_host.c}` 和
`boards/stm32f103_pmic/bootloader/boot_left.c`。

## GD32F503VET6 参考固件

| 项目 | 软件约定 |
| --- | --- |
| MCU | GD32F503VET6，512KB Flash、64KB SRAM，8MHz 外部晶振 |
| 应用版本 | `0.1.1-gd32`，未做 GD32 实板验证 |
| 固件位置 | `firmware/pmic/candidate/gd32f503/` |
| Bootloader / 应用 | `boot.bin` 位于 `0x08000000`；`ChargeBAT_GD32.bin` 位于 `0x08008000` |
| 分区 | boot 32KB、app 224KB、staging 224KB、config 32KB |
| 充电输出 | 默认镜像强制关闭 EN；需实板核对后重新构建 |
| 升级 | 固件包含内部 Flash OTA 路径；addon 命令尚不执行 OTA |

| 引脚 | 参考用途 | 外设 / 行为 |
| --- | --- | --- |
| PA0 / PA1 / PA2 | 充电电流 / 电池电压 / 输入电压采样 | ADC0 CH0/CH1/CH2 |
| PA3 | 充电电流控制 | TIMER16 CH1 PWM |
| PA4 / PA5 | 充电红灯 / 绿灯 | GPIO，高电平亮 |
| PA6 / PA7 | 电池绿灯 / 红灯 | GPIO，高电平亮 |
| PA8 | 风扇 | TIMER0 CH0 PWM |
| PA9 / PA10 | 主机 TX / RX | USART0，115200 8N1，RT-Thread 设备名 `uart3` |
| PB3 | 充电 EN | GPIO，高电平使能；默认镜像始终关闭 |
| PB8 / PB9 | CH224/TMP100 SCL / SDA | 开漏软件 I2C |

GD32 镜像可编译、可通过 manifest 校验，尚不能据此判断引脚、ADC 分压、
外部充电电路、OTA 和带载行为正确。安装 addon 不会烧录或启动 PMIC 守护进程。
