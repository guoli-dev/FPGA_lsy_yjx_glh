# PH1P35 实时数字图像处理系统｜FPGA 工程

本目录是安路 PH1P35 的完整 TD 工程、已构建 bit、最终时序/资源报告与工作记录。
它是仓库 `ph1p35-vision-system` 的 FPGA 部分，上位机见 [../host](../host)，底盘代码见 [../car](../car)。

## 下载与打开

- **正式 bit**：`bit/camera_to_dsi_display_AE_ISP_demo.bit`，
  SHA‑256 为 `BB5D0FE2D9705D4E78E4DD40430BB4093B9769DBF77271E4F4BADAF895C7D83C`。
- `bit/camera_to_dsi_display_AE_ISP_demo_compress.bit` 是同次构建的压缩版，作备用；优先用非压缩正式 bit。
- Tang Dynasty 6.2.168116 工程入口：`project/td_project/camera_to_dsi_display.al`。
  器件为 PH1P35MDG324、Speed Grade ‑3。`project/user_source` 包含该工程引用的 RTL、IP、约束及随源资源；
  `project/td_project/camera_to_dsi_display.sdc` 为最终约束。
- 工程只带源文件，不带 `*_Runs/` 构建输出。首次构建时 TD 会自行创建运行目录。
- 工程内的源文件引用是相对 `td_project/` 的 85 条相对路径，**不要拆散 `project/` 的目录结构**。
- `.al` 第 2 行的 `Project Path` 是打包机器的绝对路径，属于元数据。TD 打开时会按实际位置重新解析；
  若提示工程路径不存在，把该属性改成你本机的 `td_project` 目录即可，源文件不会丢。

## 文件结构

```text
bit/       正式 bit 与备用压缩 bit
project/   可打开的 TD 工程、完整 user_source、最终 SDC 和流程 Tcl
reports/   最终布局布线后的时序、资源和 route QoR 报告
docs/      原工作记录、演示说明、操作记录和视频脚本
```

## 本版功能与构建结果

- 模式 0–4 保留原图、边缘、卡通、颜色跟踪和运动检测；模式 5 为 AWB 左关右开，
  模式 6 为 Gamma 左关右开，模式 7 为 AE 实时画面与曝光/增益数值。
  按键循环 0→7→0；`I_button[1]` 控制 Logo/OSD。
- 模式 5/6 的左右对照使用同一实时帧的不同空间区域。单摄像头不能同时产生两种真实 AE 曝光，
  AE 模式以固定机位的前后光照变化演示。
- 以太网 `0x01` 模式命令只接受 0–4；5/6/7 只能在板上按键切换。
- 最终布线 Setup WNS +0.136 ns、Hold WNS +0.020 ns，均无违例；
  Slice 19070/21216、ERAM 80/108、DSP 39/40。视频时钟及传感器 60 fps 配置未变。
- 以上为源码、构建和静态时序核验结果，**不等于已经完成实物上板验收**。
  提交或拍视频前须实测画面、模式切换、Logo/OSD、帧率及外部通信。不要把配置值当成实测帧率。

## 开源仓库编辑说明

为了让中文注释在 GitHub 上正常显示，发布时把 60 个 GBK 编码的源文件转成了 UTF‑8
（只动注释，仓库内没有任何字符串字面量含中文，已逐文件核对）。

改动的文件都在厂商/参考设计部分：`eth/uiudp_stack/`、`isp/demosaic_4x_2_0/`、
`isp/BLC/`、`uics500_cfg/`、`vtc/`、`csi_unpacket_2lane.v`、`raw10_unpacket_2lane.v`
以及 `car/` 下的驱动代码。**本目录的关键文件没有被改动**：
bit、`.al`、`.sdc`、`awb.v`、`isp_top.v`、`design_top_wrapper.v`、`hdmi_mixer.v` 与 `reports/`
的哈希和 2026‑10‑30 提交包完全一致（见 `SHA256SUMS.txt`）。

`.bak_before_*`、`.clean_*` 等本地备份文件没有收入仓库；它们本来也不被 `.al` 引用。

## 版本边界

本目录只包含与上述 bit 对应的 FPGA 工程。上位机与小车工程在仓库的 `host/`、`car/` 目录，
它们与该 bit 的联动状态见各目录的 README，不要把未核验的附属工程标成同次构建产物。

关键文件摘要见 [SHA256SUMS.txt](SHA256SUMS.txt)；原整理过程见 [PACKAGING_RECORD.md](PACKAGING_RECORD.md)。
