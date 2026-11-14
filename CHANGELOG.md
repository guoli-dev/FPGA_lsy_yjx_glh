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

### UART “模式颜色”字节（第 2 字节）编码

`bit0`=模式，`bit2:1`=稳定颜色，其余位保留（0）。

- `bit0`：`0`=色块跟随模式，`1`=色卡指令模式。
- `bit2:1`：`00`=无/多色，`01`=红，`10`=绿，`11`=蓝。

色卡模式下直接发稳定颜色，由小车端解码成动作：

| 稳定颜色 | 字节值 |
|---|---|
| 无 / 多色 | `0x01` |
| 红 | `0x03` |
| 绿 | `0x05` |
| 蓝 | `0x07` |

跟随模式恒发 `0x00`（小车按偏差 / 宽度跟随）。

> 说明：最初按方案写成 `bit2:1`=动作（红=停/绿=进/蓝=返），但这样会把“红”和“无颜色”
> 都编码成“停”，小车无法区分。为支持“红=前进 / 无=停”，改为直接发稳定颜色，
> 动作由小车端按色卡映射。

### 蜂鸣器最终规则（本版）

- 仅在**色卡指令模式**下有效，色块跟随模式不响。
- 仅当**恰好识别到一种颜色**时才有资格发声；多种颜色同时出现不响。
- 连续 N 帧（默认 6）稳定判定为同一颜色后才确认。
- **仅在颜色发生变化时响一次**，不连续、不重复。
- 模式切换、运动报警均不响。

---

## 2026-11-15 — 小车端色卡指令模式

对应修改小车 MCU（`car/`）：色块跟随模式运动不变，新增色卡指令模式。

### 改动文件

| 文件 | 改动 |
|---|---|
| `code/ColorTrack.h` | 协议注释改为 8 字节；新增色卡指令参数；导出 `color_track_card_mode` / `color_track_card_color`。 |
| `code/ColorTrack.c` | 帧数据长度 6→7（共 8 字节）；解析第 2 字节模式/颜色；新增 `CardCommand_Update()` 色卡状态机。 |
| `fpga/.../design_top_wrapper.v` | 第 2 字节由“动作”改为“稳定颜色”（`bit2:1`=颜色），见上文编码表。 |

### 色卡指令动作

| 稳定颜色 | 动作 |
|---|---|
| 红 | 前进 1m（100cm）后停 |
| 绿 | 后退 1m（100cm）后停 |
| 蓝 | 原地旋转 360° 后停 |
| 无 / 多色 | 静止不动 |

- 距离用四轮编码器积分（`ENCODER_COUNT_TO_CM=0.486` cm/count），角度用陀螺积分。
- 换颜色 / 无颜色时清累计重新开始；超时（`COLOR_TRACK_TIMEOUT_MS=200ms`）未收到帧自动停车。
- 可调参数在 `ColorTrack.h`：`CARD_DIST_CM`、`CARD_ROT_DEG`、`CARD_FWD_SPEED`、`CARD_BACK_SPEED`、`CARD_ROT_SPEED`、`CARD_ROT_DIR`。

---

## 构建结果（2026-11-14）

- 工具链：Tang Dynasty v6.2.168116（`D:\FPGA\bin\td_commands_prompt.exe`），全流程 `read_design → bitgen`，耗时约 26 分钟。
- 时序：Setup WNS **+125 ps**（TNS 0，0 违例端点）；Hold WNS **+20 ps**（TNS 0）。
- BIT 产物：`D:\FPGA\FPGAlast\bit\camera_to_dsi_display.bit`（1,789,539 字节）。
- SHA-256：`54611348433be851ff2f21ebef2a2cf61054f3e77a05052eb2aac5b61bd45e82`

---

## 待办 / 后续

- ~~小车 MCU（`car/`）适配 8 字节 UART 新协议~~（已完成，见 2026-11-15）。
- FPGA 需重新综合生成 BIT（第 2 字节编码由“动作”改为“颜色”）。
- 上位机红/绿/蓝亮度阈值调节（优先级 6，未做）。
- 小车状态回传（优先级 7，未做）。
