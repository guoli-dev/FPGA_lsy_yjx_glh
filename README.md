# PH1P35 实时视觉感知与智能小车系统

一套面向全国大学生嵌入式芯片与系统设计竞赛（FPGA 创新设计赛道 · 安路）的完整机电系统作品：
安路 PH1P35 FPGA 完成 MIPI 摄像头采集、完整 ISP 流水线、实时视觉算法与 720p60 HDMI 显示；
Infineon CYT4BB7 双核 MCU 负责底盘运动控制；Windows 上位机经以太网做状态监控与模式切换。

```text
 SC500 摄像头 ──MIPI 2-lane──▶ PH1P35 FPGA ──HDMI 1280×720@60──▶ 显示器
                                  │   │
                     UART 115200  │   │  百兆以太网 UDP
                                  ▼   ▼
                            CYT4BB7 主控     上位机（监控 / 模式切换）
                            （底盘运动控制）
```

## 硬件平台

| 部分 | 型号 / 参数 |
|---|---|
| FPGA | 安路 PH1P35MDG324，Speed Grade ‑3，开发板 HX1P35 |
| 图像传感器 | SC500，MIPI 2-lane，输出 RAW10，1280×720@60 |
| 显示 | HDMI 1280×720@60（DSI/HDMI 发送核） |
| 主控 | Infineon CYT4BB7（Traveo II，双 Cortex‑M7） |
| 通信 | 百兆以太网（RGMII，UDP 6001/6002）、UART 115200 8N1 |
| 开发工具 | 安路 Tang Dynasty 6.2.168116、IAR Embedded Workbench for ARM |

## FPGA 图像流水线

数据通路以 **96 bit / 拍 = 4 像素** 并行（RGB888 × 4），行宽 1280 像素 = 320 拍：

```text
MIPI RX → csi_unpacket → raw10_unpacket → demosaic(4×2 bilinear)
        → data128_96(AXI4-Stream 位宽整理) → AWB → Gamma
        → ┌ 边缘检测 / 卡通化 / 颜色分类+CCL 跟踪 / 运动检测 ┐
          └─────────────── 按模式多路选择 ─────────────────┘
        → OSD + 模式名叠加 → HDMI 发送
```

- **AWB**：灰度世界假设，统计门限 `R+G+B < 720`，每拍采样 1 个像素；增益 Q16 定点，
  R、B 两路**共用同一个除法器**，靠移位链的任务标记区分归属。
- **Gamma**：四段折线，暗部提亮、亮部压缩。
- **颜色跟踪**：8×8 分块分类 + 连通域标记，输出质心、宽度与横向偏差。
- **运动检测**：分块帧差，输出运动外接框。
- **OSD**：模式名、坐标、跟踪标签，1:1 字模直绘。

## 显示模式

| 模式 | 屏幕显示 | 说明 |
|---|---|---|
| 0 | `MODE RAW` | 原始画面 |
| 1 | `MODE EDGE` | Sobel 边缘检测 |
| 2 | `MODE CARTOON` | 卡通化（双边滤波 + 量化） |
| 3 | `MODE TRACK` | 红/绿/蓝色块追踪 |
| 4 | `MODE MOTION` | 运动区域检测 |
| 5 | `MODE AWB` | 左半幅关闭 AWB、右半幅开启，同帧对比 |
| 6 | `MODE GAMMA` | 左半幅关闭 Gamma、右半幅开启，同帧对比 |
| 7 | `MODE AE LIVE` | 实时画面 + 屏显曝光值与增益 |

- 板上按键循环 **0→1→…→7→0**；`I_button[1]` 控制 Logo/OSD 显示。
- 以太网 `0x01` 模式命令**仅接受 0–4**（`eth_host.v` 中 `R_udp_data <= 8'd4`），
  5/6/7 只能在板上按键切换。
- 模式 5/6 是同一帧的左右空间区域，不是把整幅场景复制两遍；观察时让白纸或明暗结构横跨屏幕中线。
  分界线在第 160 个 beat（640 像素）。
- 模式 7 不做左右双曝光：单摄像头同一时刻只能有一种曝光参数，屏显的是真实闭环数值。

## 目录结构

```text
.
├── fpga/                 安路 PH1P35 工程（TD 可直接打开）
│   ├── bit/              已构建的 bit 文件（正式版 + 压缩版）
│   ├── project/
│   │   ├── td_project/   .al 工程、.sdc 约束、StratFlow.tcl 流程脚本
│   │   └── user_source/  RTL、IP 配置、引脚与时序约束
│   ├── reports/          最终布局布线后的时序 / 面积 / QoR 报告
│   └── docs/             构建记录、演示说明、上板操作记录、视频脚本
├── host/                 Windows 上位机（Python，网页版 + Tkinter 桌面版）
├── car/                  CYT4BB7 底盘控制工程（C，IAR）
└── NOTICE.md             第三方与厂商 IP 声明
```

## 快速开始

### 1. 直接烧录（最快看到效果）

用安路 TD 的下载器把 `fpga/bit/camera_to_dsi_display_AE_ISP_demo.bit` 烧进 PH1P35，
接好摄像头与 HDMI 显示器即可。压缩版 `..._compress.bit` 为备用。

正式 bit 的 SHA‑256：

```text
BB5D0FE2D9705D4E78E4DD40430BB4093B9769DBF77271E4F4BADAF895C7D83C
```

### 2. 打开 / 重新构建 FPGA 工程

用 Tang Dynasty 6.2 打开 `fpga/project/td_project/camera_to_dsi_display.al`。
工程里的源文件引用是相对于 `td_project/` 的相对路径，**保持 `project/` 目录结构不变**即可正常解析。

本包只带工程源文件，不带构建输出目录（`*_Runs/`）。第一次构建时 TD 会在
`td_project/` 下自动创建 `camera_to_dsi_display_Runs/syn_1`、`phy_1`，随后按工具栏依次执行
综合（Synth）与布局布线（P&R）即可。也可以用附带的 `StratFlow.tcl` 走脚本流程，
在 TD 生成的 `syn_1` / `phy_1` 目录里分别执行：

```powershell
$env:TD_STRAT = "2"
cd fpga/project/td_project/camera_to_dsi_display_Runs/syn_1
& "D:\TD_6.2\bin\td_commands_prompt.exe" ../../../StratFlow.tcl
cd ../phy_1
& "D:\TD_6.2\bin\td_commands_prompt.exe" ../../../StratFlow.tcl
```

> 产物在 `phy_1/camera_to_dsi_display.bit`，不要取 `best_result/` 里的旧文件。
> 同一份源码、同一策略的布局布线结果**不可复现**，判同源请看 Global CRC 而不是文件 MD5。

### 3. 上位机

```powershell
cd host
python server.py
```

浏览器打开 <http://localhost:8000>；也可双击 `启动上位机_网页版.bat`。
电脑网卡设为 `192.168.137.1/24`，FPGA 为 `192.168.137.2`；上位机监听 UDP 6001、向 6002 下发命令。
协议细节见 [host/README.md](host/README.md)。

### 4. 小车工程

用 IAR 打开 `car/iar/cyt4bb7.eww`。注意：本仓库**不含**逐飞科技（SeekFree）的
`libraries/` 驱动库，工程文件里的 `..\..\..\libraries\` 需从逐飞 SDK 补齐后才能编译，
详见 [car/README.md](car/README.md)。

## 构建结果

AE/AWB/Gamma 演示版（`fpga/bit/` 中的正式 bit）：

| 项 | 结果 |
|---|---|
| 器件 | PH1P35MDG324‑3 |
| Slice | 19070 / 21216（89.88%） |
| ERAM | 80 / 108 |
| DSP | 39 / 40 |
| PLL | 4 / 6 |
| Setup WNS | **+0.136 ns**（TNS 0，0 违例端点） |
| Hold WNS | **+0.020 ns**（TNS 0，0 违例端点） |
| 图像主通路 | MIPI_RX_BYTE_CLK +0.147 ns（Fmax 60.53 MHz） |

第一轮布线 Setup WNS 为 −0.231 ns，已判为不合格并弃用；最终 bit 是写入 CDC 例外后重跑的第二轮产物。

## 已知限制

- 本仓库记录的是**源码、综合与静态时序**结果，不等同于完成实物上板验收；视频与报告中的效果
  需以实际硬件为准。
- 以太网模式命令只支持 0–4，模式 5/6/7 需要板载按键。
- 模式 5/6 的左右分界固定在 640 像素。
- 同一份源码重新布局布线不一定得到相同 WNS，这是 TD 的正常行为，不是工程问题。
- `car/` 下的 IAR 工程缺少逐飞库，不能直接编译。
- 部分厂商参考设计文件带有原始版权头（MiLianKe / Anlogic / SEEKFREE / XiaoQingquan），
  它们保留各自版权，仅随工程分发以便复现，详见 [NOTICE.md](NOTICE.md)。

## 许可

本团队原创部分（上位机、底盘应用代码、顶层集成、约束、文档）采用 [MIT License](LICENSE)。
第三方与厂商 IP 不在 MIT 授权范围内，详见 [NOTICE.md](NOTICE.md)。

## 致谢

- 安路科技 Tang Dynasty 工具链与 PH1P35 参考设计
- 米联客（MiLianKe）MIPI/以太网参考实现
- 成都逐飞科技（SeekFree）CYT4BB 开源库
- pyserial（BSD‑3‑Clause）
