# AE / AWB / Gamma 演示版 工作记录

**日期**：2026-10-30
**工作目录**：`D:\FPGA\last\integration_ae_isp_demo_60fps\Final`（提交版 `D:\FPGA\last\submission\AE60_no_buzzer_submission_20261026_2315\PH1P35_AE60_no_buzzer` 的独立副本，原提交工程与 bit 未改动）
**交付目录**：`D:\FPGA\last\deliverables\isp_demo_60fps_20261030_1218`

---

## 一、需求

1. AE 演示：固定机位，先调暗再开灯，显示曝光与增益数值。
2. AWB 演示：白纸 + 彩色物体，暖光/冷光下对照校正前后。
3. Gamma 演示：暗部与亮部同场景，左右对比关闭/开启。

追加要求：增加一个专门演示模式，**屏幕左半边不加算法、右半边加算法**，在 AE 最终版工程里改，最后交付 bit。

## 二、方案与时序限制

单摄像头同一时刻只能有一种曝光设置（曝光是整幅传感器参数），因此：

| 演示页 | 左半屏 | 右半屏 | 是否实时同帧 | 60 fps |
|---|---|---|---|---|
| 模式 5 — AWB | 不做白平衡 | 做白平衡 | 是 | 保持 |
| 模式 6 — Gamma | 不做 Gamma | 做 Gamma | 是 | 保持 |
| 模式 7 — AE | 实时闭环画面 + EXP/GAIN 数值 | — | 是 | 保持 |

AE 页不做左右双曝光：真实的两路曝光需要第二路摄像头与采集通路。模式 7 改为实时画面 + 十进制曝光值 + 增益 + 灯光变化前后对比，属于如实演示而非伪造。

## 三、时间线（修改了什么、什么时候）

| 时间 | 动作 |
|---|---|
| 11:15–11:20 | 从提交版复制出工作副本；核对 `isp_top.v`、`awb.v` 的 SHA-256 与提交版一致，确认为原始基线 |
| 11:21:50 | 改 `user_source/hdl_source/awb.v`：新增 `O_raw_tdata` 输出（AWB 前原始像素，与 `O_tdata` 同拍对齐）。仅加一条 assign，不改 AWB 算法参数 |
| 11:21:50 | 改 `user_source/hdl_source/design_top_wrapper.v`：按键模式循环由 0–4 扩到 0–7；新增 AE 曝光/增益 24 MHz→HDMI 双级同步寄存器（`S_ae_hdmi_meta/sync`、`S_ag_hdmi_meta/sync`）；把 mode/exp/gain 接到 `hdmi_mixer` |
| 11:22:13 | 改 `user_source/hdl_source/isp/isp_top.v`：新增模式 5 左半原图/右半 AWB（`awb_demo_tdata`，按 `awb_beat_x < 160` 判左半，1280 px ÷ 4 px/beat = 320 beat）；新增模式 6 左半 Gamma 前/右半 Gamma 后（`gamma_bypass_d` 保留一拍、`gamma_left_d` 对齐）；未新增帧缓存 |
| 11:23:20 | 改 `user_source/hdl_source/hdmi_mixer.v`：新增模式名 `MODE AWB` / `MODE GAMMA` / `MODE AE LIVE`，以及模式 7 的 `EXP:xxxx` 十进制曝光与 `L:OFF R:ON` 提示行；复用既有 Double Dabble 转换器 |
| 11:24–11:31 | 第一轮综合（TD 6.2.168116，`TD_STRAT=2`）：19044 寄存器 / 20451 LUT / 80 RAM / 39 DSP，无 RTL 错误 |
| 11:31–11:40 | 第一轮布局布线 + bitgen。Setup WNS **−0.231 ns**、Hold WNS +0.020 ns，**不合格** |
| 11:40–11:49 | 逐路径定位：15 个违例端点全部是新增 AE 曝光/增益 24 MHz→HDMI 双级同步器的**首级**；MIPI 图像主通路最差 +0.179 ns。用已布线数据库做非持久化约束试验，确认只加同步器首级例外即可转正（试验值 Setup +0.009 ns） |
| 11:49:40 | 改 `td_project/camera_to_dsi_display.sdc`：加 `set_false_path -from [get_clocks {pll_clk_24m}] -to [get_regs -nowarn {S_a?_hdmi_meta*}]`，**仅**覆盖 AE 同步寄存器，视频主通路与其他跨域路径不受影响 |
| 11:50:04–11:56:45 | 第二轮综合（读入新 SDC）：资源同上；剩余 5 个综合估算违例均在原有以太网 RGMII 输出端，第一轮布线后已通过 |
| 11:57:17–12:17:58 | 第二轮布局布线（route 15m18s） |
| 12:18:23 | bitgen 完成 |
| 12:23 | 复制 bit 与报告到交付目录 |

## 四、最终构建结果（第二轮，已写入 SDC 的正式结果）

- **Setup WNS：+0.136 ns，TNS 0，违例端点 0**
- **Hold WNS：+0.020 ns，TNS 0，违例端点 0**
- 全部 10 个时钟路径组均无违例：

| 路径组 | Setup WNS | Fmax |
|---|---|---|
| MIPI_RX_BYTE_CLK（图像主通路） | +0.147 ns | 60.53 MHz |
| HDMI_PIXEL_CLK | +1.150 ns | 82.08 MHz |
| a_tx_clk（以太网） | +0.136 ns | 127.16 MHz |
| DDR usr_clk | +0.877 ns | 70.81 MHz |
| 其余时钟域 | ≥ +1.125 ns | — |

- 资源：**19070 / 21216 Slice（89.88%）**，ERAM 80/108，DSP 39/40，PLL 4/6
- 较提交版 19158 Slice（90.30%）减少 88 Slice；DSP 与 ERAM 数量未变
- STA 覆盖率 95.78%，缺口即 AE 同步器首级例外区

## 五、交付物

| 文件 | 说明 |
|---|---|
| `camera_to_dsi_display_AE_ISP_demo.bit` | 本次 bitgen 产物，SHA-256 `bb5d0fe2d9705d4e78e4dd40430bb4093b9769dbf77271e4f4badaf895c7d83c` |
| `camera_to_dsi_display_AE_ISP_demo_compress.bit` | 压缩版 |
| `final_timing.rpt` | 第二轮布线后完整时序报告 |
| `final_area.rpt` | 第二轮布线后资源报告 |

原始产物位置：`integration_ae_isp_demo_60fps/Final/td_project/camera_to_dsi_display_Runs/phy_1/`（`camera_to_dsi_display.bit`，12:18:23）。第一轮 11:40 的 bit 未过时序，**不要使用**。

## 六、上板操作

按键循环：模式 0→1→2→3→4→**5（AWB 对照）→6（Gamma 对照）→7（AE 状态）**→0。

- **模式 5（MODE AWB）**：左半屏 AWB 关闭（原始偏色），右半屏 AWB 开启。放白纸 + 彩色物体，在暖光/冷光下各看一次。
- **模式 6（MODE GAMMA）**：左半屏 Gamma 关闭（暗部压死），右半屏 Gamma 开启（暗部细节出来）。
- **模式 7（MODE AE LIVE）**：实时闭环画面 + 屏显 `EXP:xxxx` 与增益。先遮暗画面再开灯，观察曝光值回升过程。

模式 0–4 的算法参数、视频时钟、Sobel/跟踪精度均未改动。

## 七、未完成 / 未验证

- **未上板验证**：以上均为静态时序与资源结果，实际画面、按键响应、屏显字符位置需上板确认。
- **模式 7 不是双曝光对比**：单摄像头物理限制，已在方案阶段与需求方确认改为实时状态演示。
- 模式 5/6 的左右分界在第 160 个 beat（640 像素），若需正中分界以外的位置需再调。
- AE 同步器例外只豁免 `pll_clk_24m → S_a?_hdmi_meta*`；该路径按双级同步器设计要求，首级本就不需要同周期收敛。
