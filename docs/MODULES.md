# 模块逐个说明（161 个模块定义 / 综合实际例化 143 个）

> 数据来源：`syn_1/run.log` 的 `elaborate module` 清单（综合阶段实际例化的模块），
> 与 `fpga/project/user_source/` 下的全部 `.v` 文件交叉核对。
>
> 三种标记：
> - **【自研】** 本项目编写
> - **【改造】** 基于参考设计改写（去马赛克、采集打包、网络栈等）
> - **【厂商】** 安路 / 米联客 / 逐飞 提供的 IP 或参考实现，随工程分发以便复现，版权见 `NOTICE.md`

---

## 0. 一句话总览

| 统计 | 数值 |
|---|---|
| 仓库内模块定义 | 150 个（另有 TD 原语 11 个由工具自动例化）|
| 综合实际例化 | 124 个（自研/改造）+ 厂商 IP |
| 未参与综合 | 26 个（备选实现或参考设计遗留，见第 10 节）|
| RTL 文件 | 128 个，约 3.2 MB |
| ISP 核心 | `isp_top.v` 单文件 3389 行 / 13 个模块 |

---

## 1. 系统顶层

### `design_top_wrapper` 【自研】 `design_top_wrapper.v` 1236 行
**全系统唯一顶层。** 把所有子系统接在一起：

- 例化 PLL、MIPI 接收、ISP、DDR、视频输入/输出、HDMI、以太网、人机接口
- 按键模式机（`I_button[0]` 循环 0→7→0，`I_button[1]` 开关 Logo）
- **所有跨时钟域同步器**集中在这里（2 级触发器）
- 把 16 位调参字 `S_tune_csi` 从以太网域搬到 ISP 域，供判色门限在线调整

**讲点**：顶层只做连线、同步和状态机，不做算法——保证任何一层可独立替换。

---

## 2. 采集链路（摄像头 → 数字像素）

| 模块 | 文件:行数 | 类型 | 职责 |
|---|---|---|---|
| `ph1p_mipiio_rx_wrapper` | ph1p_mipiio_rx_wrapper.v:539 | 厂商 | 安路 MIPI D-PHY 接收原语封装，2-lane 差分输入 |
| `hs_detect` | hs_detect.enc.v:115 | 厂商 | 高速串行进出状态检测（HS/LP 切换）|
| `byte_aligner` | byte_aligner.enc.v:369 | 厂商 | 字节对齐：在串并转换后找到正确的字节边界 |
| `channel_aligner` | channel_aligner.enc.v:135 | 厂商 | **通道对齐**：2 条 lane 之间的 skew 校正 |
| `csi_unpacket_2lane` | csi_unpacket_2lane.v:139 | 改造 | CSI-2 协议解包：拆出长包头部、行有效、帧起始 |
| `raw10_unpacket_2lane` | raw10_unpacket_2lane.v:235 | 改造 | **RAW10 解包**：4 个 10 bit 像素压成 5 字节，重新拼成 40 bit/拍 |
| `uial2axis` | uial2axis.v:84 | 改造 | 把采集侧信号转成标准 AXI4-Stream（tdata/tvalid/tuser/tlast）|
| `mipi_rx_error_detect` | mipi_rx_error_detect.v:91 | 参考 | 统计 MIPI 接收错误（当前未例化，`I_mipi_rx_error` 接常 0）|

**讲点（带宽计算）**：
RAW10 1280×720@60 = **552.96 Mbps**；2-lane × 480 Mbps = 960 Mbps，占用 58%，留有余量。

### 摄像头寄存器配置（I²C）

| 模块 | 文件:行数 | 类型 | 职责 |
|---|---|---|---|
| `uicfgcs500_720p` | uicfgcs500_720p.v:140 | 改造 | **配置总控**：按索引把寄存器表逐条写进 SC500，写完置 `cfg_done` |
| `uics500reg_720p60` | uics500reg_720p60.v:82 | 改造 | 720p60 模式寄存器表（116 项）：MIPI 速率、曝光、增益、镜像等 |
| `uics500regAE` | uics500regAE.v:55 | 改造 | AE 闭环专用的曝光/增益寄存器写入 |
| `SC500GainTbl` | SC500GainTbl.v:27 | 改造 | 传感器增益码表（模拟增益是分段非线性的，需要查表换算）|
| `uii2c` | uii2c.v:262 | 厂商 | I²C 主机，3 态机（起始/写/停止），供配置寄存器用 |
| `ae_set` | ae_set.v:85 | 改造 | **AE 闭环决策**：根据统计结果判断偏亮/偏暗，输出期望曝光值 |
| `uics500reg` | uics500reg.v:175 | 参考 | 早期通用寄存器表（未例化，被 `_720p60` 版本取代）|
| `uicfgcs500` | uicfgcs500.v:168 | 参考 | 早期通用配置总控（未例化）|

**讲点**：AE 是**闭环**的——ISP 统计 → 判断偏亮/偏暗 → I²C 改寄存器 → 下一帧生效。

---

## 3. ISP 图像处理核心 ★重点

全部 13 个模块都在 `isp_top.v`（3389 行）里，另加独立的 `awb.v` 和 `signal_delay.v`。

### 3.1 像素打包格式（讲之前必须先说这个）

```
96 bit / 拍 = 4 个像素 × RGB888
一行 1280 像素 = 320 拍
```
**为什么**：像素时钟 75 MHz 下，一拍处理 1 个像素需要内部逻辑跑到 75 MHz；打成 4 像素并行后，**等效内部速率降到 18.75 MHz**，为布局布线留出时序余量。

### 3.2 逐模块

| # | 模块 | 行数量级 | 职责与设计点 |
|---|---|---|---|
| 1 | `isp_top` | 主壳 | 串起整条 ISP：解包 → 去马赛克 → 位宽整理 → tint → AWB → Gamma → 饱和度 → 四路算法 → 模式选择 → 输出 |
| 2 | `demosaic`（+子模块）| 110 | **去马赛克**：Bayer 阵列 → RGB。调用 `zhenghe` → `raw_matrix_3x3_buffer` → `bilinear_interpolation` 三级 |
| 3 | `zhenghe` | 195 | 去马赛克的时序整合层：把 4 像素并行的原始流整理成 3×3 窗口所需的节拍 |
| 4 | `raw_matrix_3x3_buffer` | 328 | **3×3 窗口生成**：用 2 个行缓冲（ERAM）把相邻两行的数据对齐，输出 3 条 96 bit 行数据 |
| 5 | `line_buffer_demosaic` | 109 | 单行行缓冲，是上面 3×3 窗口的存储单元 |
| 6 | `mipi_to_raw_converter` | 79 | 把 MIPI 下的 RAW 打包格式转成去马赛克需要的排布 |
| 7 | `bilinear_interpolation` | 912 | **双线性插值核心**：每个像素按所在 Bayer 相位，用邻居插出缺失的两个通道 |
| 8 | `blk_mem_gen_demosaic` / `blk_mem_gen_zhenghe` | 53 | TD 生成的行缓冲 IP 包装（内部为 `ram_*` 原语）|
| 9 | `data128_96` | 19 | **位宽转换** 128→96 bit：把上游 128 bit 流拆成 96 bit/4 像素 |
| 10 | `data_96bit_to_128bit` | 79 | **位宽转换** 96→128 bit：送 DDR 前重新打包，**每 4 拍出 3 个 128 bit 字**（384 bit = 3×128）|
| 11 | `radial_tint_96` | 模块 | **镜头色阴影校正**（见下） |
| 12 | `awb` | 820 | **自动白平衡**（见下）|
| 13 | `signal_delay` | 131 | AWB 内部的行延时/时序再生：控制信号与数据同步等长延迟 |
| 14 | `divider` | 64550 | TD 生成的除法器 IP（**当前未例化**——AWB 用的是自己写的时序除法器）|
| 15 | `blk_mem_gen_awb_delay_signal` | 98 | AWB 行延时用的 RAM 包装 |
| 16 | `gamma_96` | 模块 | **Gamma + 饱和度**（见下）|
| 17 | `aec_stats_96` | 模块 | **AE 统计**：逐块统计亮度，输出偏亮/偏暗标志给 `ae_set` |
| 18 | `BLC` | BLC.v:95 | 黑电平校正（**当前未例化**，黑阶在 Gamma 段内扣除）|

#### `radial_tint_96` 【自研】——镜头色阴影校正

- 几何：`r² = dx² + 3·dy²`（**16:9 椭圆**，不是正圆），`zone = r² >> 16`
- 8 档系数表，中心全 0，四角 R 压 −9.4%、B 压 −4.7%
- **关键：它放在 AWB 之前**

**为什么顺序重要**：AWB 是灰度世界假设，会把四周的固有色偏当成"场景颜色"一起平均掉。先补偿、再统计，AWB 才看到干净的场景。

**为什么全用负系数**：旧版中心是 +3（正值），`f_adj` 就必须同时实现"加法+饱和"和"减法"两条路；改成全非正后，综合直接剪掉加法那半条 —— 实测省 **1664 个 slice**。

#### `awb` 【自研】——自动白平衡

- 灰度世界假设，统计门限 `R+G+B < 720`（滤掉过曝点，否则高光会带偏白平衡）
- 每拍采样 1 个像素，帧末算出 Q16 定点增益
- **R、B 两路共用同一个除法器**：靠移位链里的"任务标记"区分这次算的是谁

**讲点**：除法是全设计最贵的组合逻辑。共用除法器是**用时间换面积**的典型手段。

#### `gamma_96` 【自研】——Gamma + 饱和度

- Gamma：四段折线，暗部提亮（<64 段 ×1.75）、亮部压缩（>192 段 ×0.25）
- 饱和度：`mid = (R+G+B)>>2`，`out = C + (C−mid)·3/8`
- **双向钳位**：加法侧截到 255，减法侧截到 0

**讲点（一个真实 bug）**：旧代码减法用 10 位无符号，`c < (mid−c)>>2` 时会下溢成接近 1024，再被 `>255` 判真 —— **暗通道直接烧成白色**。全色域扫描发现 **5.8% 的通道受影响**，例如青色 (20,200,200) 会变成 (255,223,223)。加上低侧钳位后归零。

---

## 4. 视觉算法（四路并行）★重点

四路算法**同时运行**，由模式多路选择器输出其中一路到屏幕。**颜色检测始终在跑**，不受显示模式影响。

| 模块 | 职责与设计点 |
|---|---|
| `color_detect_96` | **判色核心**（见下）|
| `color_box_ccl_96` | **连通域标记 + 跟踪**（见下）|
| `color_box_hold_96` | 轨迹保持：短时间内短暂丢失不立即撤框，抑制闪烁 |
| `box_overlay_96` | 把包围盒画到画面上（红/绿/蓝三色框）|
| `color_box_96` | 早期的"分块引导"跟踪器（**未例化**，被 CCL 版取代）|
| `classify_overlay_96` | 判色染色视图（**已从综合中移除**，模式 7 改为 AE 实时显示）|
| `edge_detect_96` | **Sobel 边缘检测**：3×3 梯度，2 个行缓冲，输出强边标志供卡通化复用 |
| `cartoon_effect_96` | **卡通化**：3 点水平平滑 → 每通道量化到 8 级 → 强边处保留边界 |
| `motion_detect_96` | **运动检测**：分块帧差，块计数超过阈值判为运动，输出运动外接框 |

### `color_detect_96` 【自研】——判色核心

**判据**（以绿为例）：
```verilog
is_green = (g >= I_min_bright)      // 亮度门，默认 45
        && (g >= r) && (g >= b)      // 绿必须是最大通道
        && ((g-r) >= m) && ((g-b) >= m);   // 相对饱和度门限
```

**门限 `m` 的两个关键设计**：

1. **运行时可配**（2 位档位，来自 16 位调参字）：
   `0 = 2/16`、`1 = 3/16`、`2 = 4/16`、`3 = 5/16`
   → **比赛现场换场地不用重编译**，上位机改一个字即可
2. **绝对下限 8 个码值**：
   ```verilog
   color_margin = (m < 8) ? 8 : m;
   ```
   **为什么**：`m` 是纯比例的，画面变暗时按 `g>>3` 会塌到 2~3 个码值，传感器噪声本身就能满足 → **暗场景满屏假绿框**。加下限后**越暗越严**，方向才正确。

**去噪**：判色之后、进跟踪之前有**水平 3 点中值**（"3 个里至少 2 个命中"），消掉孤立单点。垂直方向的中值实现已写好但当前用 `BYPASS_VMED = 1'b1` 旁路（大面积实测无明显收益，且行内组号需要按帧复位才安全）。

**延迟对齐**（容易出 bug 的地方）：`hit` 和 `tuser/tvalid` 必须**一起延同样一拍**，否则跟踪器里 `I_tuser && !I_tvalid` 的条件会失效。

### `color_box_ccl_96` 【自研】——连通域标记与跟踪

```
逐组判色 → 横向连续性 → 连通域标记 → 面积筛选 → 包围盒 + 质心
```

| 参数 | 值 | 作用 |
|---|---|---|
| `MIN_RUN` | 红 3 / 绿 3 / 蓝 2 | 一个 4 像素组至少几个像素命中才算"活跃" |
| `AREA_TH` | 300 像素 | 单个连通域小于此值不报（滤散点）|
| `AREA_MAX` | 250000 | 大于此值不报（防止整片背景）|
| `NTRK` | 4 | 每色最多同时跟踪几条轨迹 |
| `GAPX/GAPY` | 4 / 16 | 断链容差（横向 16 像素、纵向 15 行）|
| `EDGE_MASK_X/Y` | 32 / 18 | **只屏蔽四角**（`!(in_h && in_v)`），四条边的中点仍参与检测 |

**为什么用连通域而不是直接阈值框**：
- 阈值框会把一片噪点、一条高光带都当成目标
- 同一个物体还会被拆成好几个框
- 连通域按**连通性**归并，从原理上解决这两个问题

**每色输出 64 位**：`[9:0]` 下边界、`[19:10]` 上边界、`[30:20]` 右边界、`[41:31]` 左边界、`[42]` 有效位、`[53:43]` 质心 x、`[63:54]` 质心 y。三色共 192 位，每色 4 个 rank。

---

## 5. 跨时钟与存储

**两个时钟域（不同源、不同频）**：

| 时钟 | 频率 | 来源 |
|---|---|---|
| MIPI 接收 / ISP | 59.995 MHz | 摄像头 |
| HDMI 像素 | 75.002 MHz | 显示 |

| 模块 | 职责 |
|---|---|
| `video_in` | **写 DDR**：按行突发 240 个字（1280×24bit ÷ 128 = 240），4 个帧缓冲轮转，写指针每帧 +1 |
| `video_out` | **读 DDR**：同样 240 字突发，读指针 = 写指针 + 2 帧，保证读的是**已写完的完整帧** |
| `mc_to_user_interface` | DDR 用户接口的 FIFO 包装，屏蔽控制器时序细节 |
| `w128_d512_fifo` / `w155_d512_fifo` / `w40_d512_fifo` | TD 生成的 512 深异步 FIFO（128/155/40 位宽）。**w40 未例化** |
| `uivtc` | **视频时序发生器**：产生 720p60 的 hsync/vsync/DE |
| `pll` | 系统 PLL：50 MHz 输入 → 多路时钟（图像域、HDMI 域、DDR 域等）|
| `pll_hdmi` | HDMI 专用 PLL（**当前未例化**，时钟已并入主 PLL）|

**讲点（为什么必须有 DDR）**：输入 59.995 MHz、输出 75.002 MHz，**没有帧缓存就必然撕裂**。4 缓冲 + 读落后 2 帧，保证任何时刻读的都是完整帧。

---

## 6. 显示链路

| 模块 | 行数 | 类型 | 职责 |
|---|---|---|---|
| `hdmi_mixer` | 2066 | 自研 | **显示合成**：画面 + Logo + OSD 文字/数字叠加，输出到 HDMI |
| `hdmi_tx` | 250 | 改造 | HDMI 发送：并串转换、控制包、音频包封装 |
| `hdmi_1_4b_transmitter_core_wrapper` | 5041 | 厂商 | 加密的 HDMI 发送核 |
| `hdmi_phy_wrapper` | 124 | 厂商 | HDMI PHY 顶层封装 |
| `lane_lvds_10_1` | 157 | 厂商 | 10:1 并串转换（TMDS 输出）|
| `osd_char_lib` | 877 | 自研 | **字模库**：ASCII 字符 + 数字的 1:1 点阵 |
| `anlogic_logo_rom` | 7084 | 自研 | **Logo ROM**：1024×25 调色板 + 8 个索引 bank，显示开机 Logo |
| `I2S_receiver` / `audio_arc_calculate` | 150 / 70 | 厂商 | HDMI 音频包格式填充（当前只送静音包，保证 HDMI 合规）|

**讲点**：`hdmi_mixer` 里 OSD 显示的是**实时闭环数值**（曝光值、增益、模式名、跟踪标签），不是静态图片。

---

## 7. 以太网（上位机通信）

| 模块 | 职责 |
|---|---|
| `eth_host` | **以太网业务层**：UDP 收上位机命令（切模式、调参），周期性上报状态（模式/帧率/链路）|
| `uiudp_stack` | UDP 协议栈顶层，串起 MAC/IP/UDP 三层 |
| `rgmii_interface` | RGMII 物理接口（DDR 采样，IDDR/ODDR）|
| `uimac_layer` / `uimac_rx` / `uimac_tx` | MAC 层：帧收发、CRC、前导码 |
| `uimac_tx_frame_ctrl` / `uimac_tx_pause_ctrl` | 发送帧节奏控制 / PAUSE 流控帧 |
| `uiip_layer` / `uiip_rx` / `uiip_tx` | IP 层：校验和、路由判断 |
| `uiip_arp_rx` / `uiip_arp_tx` / `uiip_header_checksum` | ARP 请求应答、IP 头校验和 |
| `uiarp_layer` / `uiarp_rx` / `uiarp_tx` | ARP 层封装 |
| `uiudp_layer` / `uiudp_rx` / `uiudp_tx` | UDP 层：端口过滤、长度字段 |
| `uiicmp_pkg_ctrl` / `uiicmp_pkg_tx` | ICMP（ping 应答，方便现场调试连通性）|
| `crc32_gen` / `crc32_check` | MAC 帧 CRC32 生成 / 校验 |
| `mac_cache` | MAC 地址缓存（避免重复 ARP）|
| `udp_pkg_buf` + `fifo_cross_domain_addr_process_*` / `ram_infer_*` | UDP 收发缓冲（跨时钟域）|
| `uiphyrst` | PHY 复位时序 |
| `mdio_ctrl` / `uirgmii_rx` / `uirgmii_tx` | MDIO 管理与 RGMII 收发（**当前未例化**，用 `rgmii_interface` 替代）|

**讲点**：全部走 UDP（不做 TCP，避免重传带来不确定延迟），FPGA 固定 IP `192.168.137.2`，端口 6001/6002。

---

## 8. 人机接口

| 模块 | 行数 | 自研 | 职责 |
|---|---|---|---|
| `key_remove_shakes` | 85 | 是 | **按键消抖**：下降沿 + 约 10 万拍计数，输出单拍脉冲 |
| `status_seg8` | 127 | 是 | **数码管状态显示**：显示当前模式 / 跟踪状态 |
| `color_buzzer_alert` | 121 | 是 | **蜂鸣器告警**：颜色在连续 6 帧保持唯一才确认稳定，颜色变化时响一声 |
| `uart_pkt_tx` | 64 | 是 | **UART 打包发送**：把三色偏差/宽度组成 8 字节帧发给底盘单片机 |

**讲点（通信协议）**：FPGA → 单片机，UART 115200 8N1，8 字节一帧：
`AA | 模式/动作 | 红偏差/宽度 | 绿偏差/宽度 | 蓝偏差/宽度`
单片机侧由 `ColorTrack.c` 解析，`on_frame()` 收满 8 字节后更新三色候选。

---

## 9. DDR 控制器（厂商 IP，安路）

`ph1p35_ddr_wrapper` 是安路的 DDR2 控制器 IP，内部 18 个模块：

| 层次 | 模块 | 作用 |
|---|---|---|
| 顶层 | `ph1p35_324_ddr_wrapper` / `ddr2` / `ph1p_ddrmc_top` | 对外接口、时钟复位 |
| PHY | `ph1p_ddrphy_top` / `ph1p_ddrphy` / `ph1p_ddrphy_byte_wrapper` | 物理层收发 |
| 训练 | `ph1p_ddrphy_dcu` / `ph1p_ddrphy_mdl_cal` / `ph1p_ddrphy_rphase_ctl` / `ph1p_ddrphy_wphase_ctl` | **读写相位校准**（DDR 能否工作的关键）|
| 初始化 | `ph1p_ddrphy_init` / `ph1p_ddrphy_fast_init` / `ph1p_ddrphy_dram_init` | 上电时序、模式寄存器 |
| 时钟 | `ph1p_ddrphy_clk_top` / `ph1p_ddrphy_pll0` / `ph1p_ddrphy_pll1` | DDR 专用 PLL |
| 其它 | `ph1p_ddr_fifo_dram_sync` / `ph1p_ddrphy_sync_rst_gen` / `alc_mc_top` / `alc_phy2mc_fifo_ctrl` / `ph1p_ddrphy_cmd_decode` / `ph1p_ddrphy_cmd_execution` / `ph1p_ddrphy_cmd_wrapper` / `ph1p_ddrphy_dcu_wrapper` / `ph1p_ddrphy_fast_init_wrapper` / `ph1p_ddrphy_mdl_cal_wrapper` | 命令译码、跨时钟、复位同步 |

**讲点**：这一整块是**厂商 IP，我们没有修改**，只做接口对接。DDR 的读写相位校准由 IP 自动完成。

---

## 10. 未参与综合的 26 个模块（评委可能会问）

| 模块 | 为什么没用 |
|---|---|
| `csi_unpacket` / `raw10_unpacket` | 单 lane 版本，本项目用 2-lane 版本 |
| `uicfgcs500` / `uics500reg` | 早期通用配置版本，被 720p60 专用版取代 |
| `color_box_96` | 早期的分块引导跟踪器，被连通域版取代 |
| `classify_overlay_96` | 判色染色调试视图，**已按需求从综合中移除** |
| `BLC` | 黑电平校正，黑阶已在 Gamma 段内扣除 |
| `divider` | TD 生成的除法器 IP，AWB 用自己的时序除法器更省面积 |
| `data96_128` | 位宽转换的另一种实现，实际用 `data_128_96` + `data_96bit_to_128bit` |
| `pll_hdmi` | HDMI 时钟已并入主 PLL |
| `ps_wrapper` / `MCU` / `MCU_*` | 参考设计的软核 / 外设示例 |
| `raw8_to_rgb888` / `auto_white_balance` / `image_correction` / `video_cutting` | 参考设计附带的图像处理模块，本设计未采用 |
| `mipi_rx_error_detect` | MIPI 错误统计，当前 `I_mipi_rx_error` 接常 0 |
| `mdio_ctrl` / `uirgmii_rx` / `uirgmii_tx` | 被 `rgmii_interface` + `eth_host` 替代 |
| `w40_d512_fifo` / `ram_infer_2758...` / `soft_fifo_al_2758...` | 40 位宽 FIFO 未被使用 |
| `ph1p_ddrphy_apb_bridge` / `ph1p_ddrphy_bankref_cfg` | DDR IP 的可选配置模块，本配置未启用 |

**主动讲**：这 26 个**不参与综合，不占资源**，是备选实现和参考设计遗留，保留是为了可复现性。

---

## 11. 一页纸速记（现场背这个）

```
采集    MIPI 2-lane → CSI 解包 → RAW10 拼 40bit → AXI4-Stream
传感器  I²C 写 116 项寄存器 + AE 闭环（统计→判断→改寄存器）

ISP     去马赛克(4×2双线性) → 96bit/4像素 → 色阴影校正(椭圆8档)
        → AWB(灰度世界/共用除法器) → Gamma(四段) → 饱和度(双向钳位)

算法    边缘(Sobel) / 卡通化(量化) / 颜色(判色+连通域+跟踪) / 运动(帧差)
        四种同时跑，模式选一路显示

跨域    59.995MHz ⇄ 75.002MHz，DDR 4 缓冲轮转，读落后写 2 帧

显示    OSD 叠加 → HDMI 720p60

通信    UART 115200 → 底盘；以太网 UDP → 上位机（含 16 位调参字）

资源    Slice 19070/21216 = 89.88%，DSP 39/40，ERAM 80/108
        Setup WNS +0.136ns，Hold WNS +0.020ns（布局布线后，0 违例）
```
