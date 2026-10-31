# FPGA Vision Console

Windows 图形化监控与管理端。程序只传输控制和遥测数据，不传图像，也不参与 FPGA 视觉计算或底层电机控制。网络短时中断不会停止 FPGA 图像流水线。

界面依据项目内 [`DESIGN.md`](DESIGN.md) 实现 Apple-inspired 视觉语言：羊皮纸背景、
近黑文字、单一 Action Blue 交互色、发丝边框和无阴影卡片。规范来源于
VoltAgent `awesome-design-md` 的 Apple 参考，并针对 Windows Tkinter 与实时遥测做了适配。

## 启动与网络

双击 `启动上位机_网页版.bat`（或 `python server.py`），浏览器打开 <http://localhost:8000>。
端口被占用、页面像旧版本时，用 `重启网页上位机.bat`，它会先结束占用 8000 的旧进程再启动。

`app.py` 是原来的桌面版 Tkinter 界面，网页服务会复用它里面的 UDP 接收线程，运行网页版时不需要打开它。

电脑“以太网 2”设置为 `192.168.137.1/24`；FPGA 地址为 `192.168.137.2`。程序监听 UDP `6001`，向 FPGA UDP `6002` 发送命令。

## 功能

- 设备总览：在线状态、固定 IP、PHY 链路、运行时长、当前模式。
- 目标监控：红/绿/蓝有效状态、质心 X/Y、横向偏差、目标宽度和二维位置图。
- 性能监控：FPS、16 位循环帧计数、以帧为单位的采集到显示延迟、运动区域计数、通信包数。
- 远程控制：切换五种 FPGA 显示模式；选择上位机重点监控的目标颜色。
- 异常告警：网络中断、目标连续丢失、低帧率、运动区域超阈值；只在状态变化时记录。
- 车端监控（模式 5）：通过逐飞无线串口读取小车遥测，显示目标色块二维位置图、速度指令、四轮实测、航向与供电。
- 数据记录：交互/告警日志、包数与告警数统计、UTF-8 CSV 导出。

“监控目标”和三个告警阈值仅作用于上位机显示与告警，不会修改 FPGA 的颜色阈值或追踪算法。五种模式切换会真实下发到 FPGA。

> FPGA 侧另有模式 5–7（AWB 左右对照、Gamma 左右对照、AE 实时数值）。以太网 `0x01` 命令只接受 0–4，
> 这三个模式只能在板上按键切换，因此本上位机不提供对应按钮。

## UDP 协议

下行：`01 mode` 设置模式（0~4），`02` 请求状态，`03` 请求色块遥测，`04` 请求运动框遥测。

新版状态帧（12 字节）：

```text
AA mode fps_lo fps_hi link frame_lo frame_hi latency_lo latency_hi motion_lo motion_hi 55
```

新版色块帧（11 字节）：

```text
AB r_dev r_width r_y4 g_dev g_width g_y4 b_dev b_width b_y4 55
```

新版运动框帧（12 字节）：

```text
AC box[7:0] .. box[63:56] motion_lo motion_hi 55
```

`box` 为 64 位小端，位布局与 FPGA `isp_top.O_mot_box` 一致：`[42]=valid`、`[41:31]=left`、`[30:20]=right`、`[19:10]=top`、`[9:0]=bottom`，坐标以 1280×720 画面为基准。

`dev` 是有符号 8 位横向偏差，实际像素偏差为 `dev×8`；`80` 表示该颜色无效。实际宽度为 `width×8`，Y 坐标为 `y4×4`。上位机也兼容旧版 6 字节状态帧和原 UART 7 字节色块帧。

## 车端监控（模式 5，网页版）

网页版侧栏“5 车端监控”是独立页面，只读串口，不向 FPGA 下发任何命令，0~4 模式的行为保持不变。

PC 端插一个与车上配对的逐飞无线串口模块（虚拟 COM 口，115200 8N1），在页面里点“刷新”选中串口后点“连接”。

`pyserial` 已随 `vendor/` 目录携带，不需要联网安装；如果串口列表为空又分不清是驱动还是库的问题，双击 `安装串口依赖.bat`，它会打印 Python 路径、pyserial 状态、COM 口列表和 Windows 里带感叹号的串口设备。

数据来自车端 `project/code/Telemetry.c`，每 20 ms 一帧、42 字节：

```text
C5 01 seq len flags mode locked dev wid R_dev R_wid G_dev G_wid B_dev B_wid
cmdX cmdY cmdZ LF RF LB RB vx vy heading target gyro batt uptime crc8 5C
```

CRC8 多项式 0x07，覆盖前 40 字节；`dev=0x80` 表示该颜色无效；`heading/target/gyro` 为 0.1° 定点，`batt` 为 0.1 V。

## 自检

```powershell
cd host
python -m unittest -v test_protocol.py
python -m unittest -v test_car_protocol.py
python app.py --self-test-ui
```

依赖只有 Python 3.10+ 标准库；串口监控用到的 pyserial 已随 `vendor/` 携带，无需联网安装。

设备端的基本跟随/停车逻辑独立于本软件。若比赛要求“通信丢失后电机必须安全停车”，还需在电机控制 MCU 中增加并验证通信看门狗；上位机不能替代该安全功能。
