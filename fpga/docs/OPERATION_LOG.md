# AE/AWB/Gamma 演示版操作记录

## 2026-10-30

- 从 `D:\FPGA\last\submission\AE60_no_buzzer_submission_20261026_2315\PH1P35_AE60_no_buzzer` 复制出独立工作副本 `D:\FPGA\last\integration_ae_isp_demo_60fps\Final`；原提交工程和 bit 不修改。
- 核对 `isp_top.v`、`awb.v` 的 SHA-256 与提交版一致；构建前工作副本为原始提交版。
- 方案：原有 0–4 模式不变；新增 AWB 左关右开、Gamma 左关右开、AE 实时数值页。单传感器不能同一时刻获取两种真实曝光，因此 AE 页显示实时闭环画面与曝光/增益，不伪称实时 AE 开关分屏。
- 当前阶段：核对流水时序、RTL 修改准备中。未生成新的 bit；工作副本中如有旧 bit，不视为本次交付。
- 已在工作副本修改 `awb.v`、`isp_top.v`、`design_top_wrapper.v`、`hdmi_mixer.v`：新增模式 5 AWB 左关右开、模式 6 Gamma 左关右开、模式 7 AE 实时数值；模式 0–4 的算法参数和视频时钟未改。两路对照均使用同一帧的实时像素，未复制整套 AWB/Gamma，也未新增帧缓存。
- AE 数值显示复用 HDMI 既有逐帧 Double Dabble 转换器，显示十进制曝光与增益。演示用原始/处理像素仅在显示路径切换，未降低 Sobel、跟踪等现有算法精度。
- 待完成：静态/TD 综合检查、资源与时序核对、布局布线、独立新 bit 交付；验证前不得把旧 bit 标记为新版本。
- 11:24 在工作副本 `syn_1` 启动 TD 6.2.168116 综合，`TD_STRAT=2`；`read_design` / elaboration 已通过，当前进入 RTL 优化。未并行启动另一 TD 任务。
- 约 11:31 综合成功（`read_design`→`opt_gate`）。综合报告：19044 寄存器、20451 LUT、80 RAM、39 DSP；综合估计 Setup WNS -0.540 ns，不能替代最终布线时序。现准备在同一独立副本启动 `opt_place`→`bitgen`。
- 11:31 在独立 `phy_1` 启动布局布线与 bitgen，策略 `TD_STRAT=2`；已确认导入的是本次生成的 `../syn_1/camera_to_dsi_display_gate.db`。当前正在全局布局。
- 放置完成，正式面积报告为 19031/21216 Slice（89.70%），80/108 RAM、39/40 DSP；较原提交版 19158 Slice（90.30%）少 127 Slice。已进入详细布线；这是中间资源报告，最终时序仍待核对。
- 第一轮完整布局布线和 bitgen 结束，但 Setup WNS = -0.231 ns、Hold WNS = +0.020 ns；此 bit **暂不可作为合格交付版**。逐项检查时序报告：15 个违例端点全部是新加的 AE 曝光/增益 24 MHz→HDMI 双级同步器**首级**；MIPI 图像主通路最差 Setup WNS +0.179 ns。准备仅对同步器首级加 CDC 时序例外后重跑，绝不放松视频主通路时序。
- 用第一轮已布线数据库做非持久化约束验证：单条 `get_regs {S_a?_hdmi_meta*}` 仅命中 AE 曝光/增益首级同步器；试验后 Setup WNS +0.009 ns、Hold WNS +0.020 ns。已将此定向例外写进工作副本 SDC；现在完整重跑综合和布线，第一轮 bit 仍不视作最终交付。
- 11:50 第二轮综合启动并完成；新 SDC 已读入。综合后 5 个估算 Setup 违例均为原有 RGMII 输出端点，AE 同步器跨域路径不再列为违例。资源保持 19044 寄存器、20451 LUT、80 RAM、39 DSP。准备第二轮布局布线。
- 11:57 启动第二轮 `opt_place`→`bitgen`；12:18 完成。最终正式时序：Setup WNS +0.136 ns、TNS 0；Hold WNS +0.020 ns、TNS 0。资源：19070/21216 Slice（89.88%），80/108 RAM，39/40 DSP。60/75 MHz 视频时钟设置未改。
- 将新 bit 从本次 `phy_1` 构建输出另存为 `AE_AWB_Gamma_live_split_60fps_20261030.bit`，没有覆盖旧版。源/交付 SHA-256 均为 `BB5D0FE2D9705D4E78E4DD40430BB4093B9769DBF77271E4F4BADAF895C7D83C`。原提交 bit 仍位于冻结提交目录，SHA-256 为 `F1A740D4D179A37D3F134E331EA1E766C444E1ECE2C89727053D8EF6F89A3EE2`。
- 已写 `DEMO_GUIDE.md` 与 `DELIVERY_MANIFEST.md`。尚未上板做实物画质/串口验证；上板前不声称实测效果已确认。
- 11:57 第二轮布局布线启动（读入含 AE 同步器例外的 SDC）；12:17:58 布线结束，12:18:23 bitgen 完成。**最终 Setup WNS +0.136 ns、Hold WNS +0.020 ns，全部 10 个时钟组 0 违例端点**；MIPI 图像主通路 +0.147 ns（Fmax 60.53 MHz），HDMI +1.150 ns，以太网 +0.136 ns。资源 19070/21216 Slice（89.88%），ERAM 80/108、DSP 39/40，较提交版少 88 Slice。
- 12:23 交付：`D:\FPGA\last\deliverables\isp_demo_60fps_20261030_1218\`，内含 `camera_to_dsi_display_AE_ISP_demo.bit`（SHA-256 bb5d0fe2…c7d83c）、压缩版 bit、最终时序/资源报告、`WORK_LOG.md`。第一轮 11:40 的未过时序 bit 不作为交付物。
- 未验证项：未上板，实际画面、按键、屏显位置待硬件确认。
