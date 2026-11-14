# CYT4BB7 底盘控制工程

英飞凌 CYT4BB7（Traveo II，双 Cortex‑M7）上的麦克纳姆轮底盘控制程序，
接收 FPGA 的色块追踪结果做视觉伺服，同时把车体状态回传给上位机。

## 双核分工

| 核 | 文件 | 职责 |
|---|---|---|
| CM7_0 | `user/main_cm7_0.c` | 主控制：色块追踪、运动控制、PID、电机、IMU、遥测 |
| CM7_1 | `user/main_cm7_1.c` | 协处理：中断服务与辅助任务 |

中断服务在 `user/cm7_0_isr.c`、`user/cm7_1_isr.c`。

## 源码模块

| 文件 | 作用 |
|---|---|
| `code/ColorTrack.c` | 色块追踪状态机：锁定、丢目标搜索、到达判定、横向居中 |
| `code/Control.c` | 车体运动学与速度指令分配（麦轮 LF/RF/LB/RB） |
| `code/Pid.c` | 位置式/增量式 PID |
| `code/Motor.c` | 电机 PWM 与方向 |
| `code/Encoder.c` | 编码器测速 |
| `code/IMU.c` | 陀螺零漂、航向积分、角速度 |
| `code/Telemetry.c` | 42 字节车端遥测帧，20 ms 一帧 |
| `code/Communication.c` | 通信帧收发与解析 |
| `code/mcar_comm.c` | 与飞控的目标/回执帧（`0xA5 … 0x5A`，12/10 字节） |
| `code/Wireless.c` | 逐飞无线串口模块初始化 |
| `code/Eeprom.c` `BAT.c` `Buzzer.c` `RC.c` | 参数存储、电压检测、蜂鸣器、遥控输入 |

## 数据接口

**FPGA → 车（UART_5，115200 8N1，60 Hz，7 字节）**

```text
AA | R_dev | R_wid | G_dev | G_wid | B_dev | B_wid
```

`dev` 为有符号 8 位横向偏差，`0x80` 表示无目标，`0x00` 为正中；实际像素偏差为 `dev×8`。
`wid` 为目标宽度 0–159，越近越大。`0xAA` 不会出现在数据字节里，因此靠帧头对齐即可。
接收口由 `ColorTrack.h` 的 `COLOR_TRACK_RX_PORT` 选择（1/2/5）。

**车 → 上位机（UART_1，115200 8N1，20 ms 一帧，42 字节）**

```text
C5 01 seq len flags mode locked dev wid
R_dev R_wid G_dev G_wid B_dev B_wid
cmdX cmdY cmdZ LF RF LB RB vx vy heading target gyro batt uptime crc8 5C
```

CRC8 多项式 `0x07`，覆盖前 40 字节。字段单位与位定义见 [code/Telemetry.h](code/Telemetry.h)。
上位机侧解析见 [../host/README.md](../host/README.md)。

## 编译

1. 用 IAR Embedded Workbench for ARM 打开 `iar/cyt4bb7.eww`。
2. **本仓库不含逐飞科技（SeekFree）的 `libraries/` 驱动库**。工程文件里写的是
   `$PROJ_DIR$\..\..\..\libraries\`，需要把逐飞 CYT4BB 开源库放到与 `iar/`、`code/` 同级的
   目录结构里，使其相对路径成立；也可以直接在 IAR 里把缺失文件替换成你本机 SDK 的路径。
3. 首次编译会生成 `Debug_m7_0/`、`Debug_m7_1/` 等输出目录，它们已被 `.gitignore` 排除。

## 无线凭据

`code/Wireless.h` 中的 WiFi 名称与密码已替换为占位符 `YOUR_WIFI_SSID` / `YOUR_WIFI_PASSWORD`，
使用前改成你自己的热点。车端与上位机必须处于同一网络。

## 已知问题

- 部分上游模板文件的头部注释在早期一次编码转换中被破坏成乱码（例如 `user/main_cm7_0.c`
  第 3 行的 `锟斤拷`）。这是逐飞模板的历史遗留，不影响代码内容；如需整洁可从逐飞原版重新拷贝该头部。
- `code/ColorTrack.h` 与 `code/mcar_comm.h` 都使用 UART_5，两者按运行场景二选一，不要同时启用。
