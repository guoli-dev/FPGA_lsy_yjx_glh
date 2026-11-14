# 更改记录 (CHANGELOG)

本文件记录 PH1P35 实时视觉感知与智能小车系统 FPGA 端的功能改动。
（FPGA 端代码位于 `fpga/project/user_source/`）

---

## 2026-11-14 — 决赛交互增强方案（FPGA 端）

实现“决赛交互增强方案”的 FPGA 侧改动（优先级 1–5），并采纳用户对蜂鸣器 / 数码管的补充要求。

### 新增 / 修改文件

| 文件 | 改动 |
|---|---|
| `hdl_source/status_seg8.v` | **新增**：8 位数码管显示，前 4 位显示模式（`FOLL` / `CArd`），后 4 位显示颜色（`rEd` / `Grn` / `bLu` / `ALL` / `----`）。 |
| `hdl_source/color_buzzer_alert.v` | **替换**：单色稳定判定 + 一次性蜂鸣。仅色卡模式发声、仅单一颜色、连续 6 帧稳定后、仅在颜色变化时响一次；多种颜色 / 跟随模式 / 模式切换 / 运动报警均不响。输出低有效（`O_buzzer = ~R_buzzer`）。 |
| `hdl_source/design_top_wrapper.v` | 见下方“顶层改动”。 |
| `constraints_source/pin.adc` | 新增 `I_car_mode_sw`(A4) 拨码开关引脚，`O_seg_dig[7:0]`、`O_seg_sel[7:0]` 数码管引脚。 |
| `td_project/camera_to_dsi_display.al` | 工程源文件清单加入 `color_buzzer_alert.v`、`status_seg8.v`。 |

### 顶层 `design_top_wrapper.v` 改动

1. 新增输入端口 `I_car_mode_sw`（拨码开关 SW1），新增输出端口 `O_seg_sel[7:0]`、`O_seg_dig[7:0]`。
2. 拨码开关两级同步到 100 MHz 时钟域：SW1 拨下 = 色块跟随模式（`S_card_mode=0`），拨上 = 色卡指令模式（`S_card_mode=1`）。
3. 实例化 `color_buzzer_alert`（蜂鸣器，低有效输出）与 `status_seg8`（数码管）。
4. UART 数据包由 7 字节扩展为 8 字节：

   `AA | 模式动作 | 红偏差 | 红宽度 | 绿偏差 | 绿宽度 | 蓝偏差 | 蓝宽度`

### UART “模式动作”字节（第 2 字节）编码

按方案约定：`bit0`=模式，`bit2:1`=动作，其余位保留（0）。

- `bit0`：`0`=色块跟随模式，`1`=色卡指令模式。
- `bit2:1`：`00`=停车，`01`=前进，`10`=返回。

色卡模式下由稳定颜色映射动作：

| 稳定颜色 | 动作 | 字节值 |
|---|---|---|
| 无 / 无效 | 停车 | `0x01` |
| 红 | 停车 | `0x01` |
| 绿 | 前进 | `0x03` |
| 蓝 | 返回 | `0x05` |

跟随模式恒发 `0x00`（小车按偏差 / 宽度跟随）。

> 注：参考目录 `D:\FPGA\FPGAlast\全部代码\...\design_top_wrapper.v` 中有一版实现采用
> `bit7`=模式、`bit1:0`=颜色（不译成动作）。本工程按方案文档的 `bit0`=模式 / `bit2:1`=动作
> 落地；小车 MCU 适配新协议时须以本表为准。

### 蜂鸣器最终规则（本版）

- 仅在**色卡指令模式**下有效，色块跟随模式不响。
- 仅当**恰好识别到一种颜色**时才有资格发声；多种颜色同时出现不响。
- 连续 N 帧（默认 6）稳定判定为同一颜色后才确认。
- **仅在颜色发生变化时响一次**，不连续、不重复。
- 模式切换、运动报警均不响。

---

## 构建结果（2026-11-14）

- 工具链：Tang Dynasty v6.2.168116（`D:\FPGA\bin\td_commands_prompt.exe`），全流程 `read_design → bitgen`，耗时约 26 分钟。
- 时序：Setup WNS **+125 ps**（TNS 0，0 违例端点）；Hold WNS **+20 ps**（TNS 0）。
- BIT 产物：`D:\FPGA\FPGAlast\bit\camera_to_dsi_display.bit`（1,789,539 字节）。
- SHA-256：`54611348433be851ff2f21ebef2a2cf61054f3e77a05052eb2aac5b61bd45e82`

---

## 待办 / 后续

- 小车 MCU（`car/`）适配 8 字节 UART 新协议（优先级 3，尚未做）。
- 上位机红/绿/蓝亮度阈值调节（优先级 6，本次未做）。
- 小车状态回传（优先级 7，未做）。
