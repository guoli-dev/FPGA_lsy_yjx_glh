# 第三方与厂商 IP 声明

本仓库以 MIT 许可发布本团队的原创代码。下列文件带有各自的版权头，**不在 MIT 授权范围内**，
它们保留原作者权利，在此仅为使工程可复现而随仓库分发。若需单独复用这些文件，请向原权利人获取授权。

## 许可范围

[LICENSE](LICENSE) 中的 MIT 许可覆盖本团队的原创部分：

- `host/` 下的上位机软件（Python / HTML / JS）
- `car/` 下的底盘应用代码
- FPGA 侧的顶层集成、模式控制与约束文件
- 仓库内的文档

带有各自版权头的文件（MiLianKe、Anlogic Inc.、SeekFree / 成都逐飞科技，以及
XiaoQingquan 参考模块）**不被本仓库的 MIT 许可重新授权**，它们保留原作者条款，
在此仅随工程分发以便重新构建与评审。

## 1. 安路科技（Anlogic Inc.）

- `fpga/project/user_source/ip_source/` —— TD IP 工具生成的 PLL、FIFO、Block Memory、除法器、
  以太网时钟等配置与网表
- `fpga/project/user_source/hdl_source/pll_hdmi.v`
- `fpga/project/user_source/hdl_source/ph1p35_ddr/ddr2/ddr2.v`
- `fpga/project/user_source/hdl_source/isp/**/blk_mem_gen_*.v`
- `fpga/project/user_source/hdl_source/hdmi_1_4b_transmitter_core_wrapper.enc.v` —— 加密的 HDMI 发送核，
  只能由安路 TD 工具链使用

版权归安路科技所有，随安路开发套件发布。

## 2. 米联客（MiLianKe）

以下文件头部带有 `Copyright (c) MiLianKe`：

- `fpga/project/user_source/hdl_source/csi_unpacket.v`
- `fpga/project/user_source/hdl_source/isp/csi_unpacket_2lane.v`
- `fpga/project/user_source/hdl_source/isp/raw10_unpacket_2lane.v`
- `fpga/project/user_source/hdl_source/uiisp_beta/`（同名参考实现）
- `fpga/project/user_source/hdl_source/vtc/uivtc.v`
- `fpga/project/user_source/hdl_source/eth/uiudp_stack/`（UDP/IP 协议栈）
- `fpga/project/user_source/hdl_source/eth/uiphyrst.v`

## 3. 参考设计模块（`@Author XiaoQingquan`）

ISP 主体模块头部标注该作者，包括 `isp/demosaic_4x_2_0/`、`isp/BLC/`、`isp/data128_96/`、
`isp/awb/`、`signal_delay.v`、`isp_top.v` 中的若干子模块。本团队在其基础上完成了集成、
模式扩展与调参，但这些模块的原始著作权仍属原作者。

## 4. 成都逐飞科技（SEEKFREE）

- `car/user/main_cm7_0.c`、`car/user/main_cm7_1.c`、`car/user/cm7_*_isr.c` 的模板部分
- 工程文件引用但**未随本仓库分发**的 `libraries/` 驱动库（逐飞 CYT4BB 开源库）

按逐飞科技开源库声明，使用与修改需保留其版权声明。

## 5. 其他

- `host/vendor/serial/` —— pyserial，BSD‑3‑Clause，许可证原文见
  `host/vendor/serial/LICENSE.txt`
- `host/DESIGN.md` 中的界面视觉规范参考了 VoltAgent `awesome-design-md` 的 Apple 风格示例

## 关于加密文件

`hdmi_1_4b_transmitter_core_wrapper.enc.v` 是加密后的网表级 IP，源码不可读，
只能由安路 TD 6.2 解密后参与综合。它不包含本团队的实现。
