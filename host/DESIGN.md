# FPGA Vision Console — Apple-inspired UI rules

本文件是桌面端的视觉约束，来源于 VoltAgent `awesome-design-md` 的 Apple
`DESIGN.md`，并针对 Windows Tkinter、中文界面和实时工业遥测进行了适配。

## Design intent

- 让设备状态和识别数据成为视觉主体，界面装饰主动退后。
- 大面积留白、低密度信息分组、无渐变、无卡片阴影。
- 蓝色只表达可交互元素；红/绿/蓝只在色块识别数据中作为语义编码。
- 网络状态采用系统语义色，但不能伪装成可点击控件。

## Tokens

| Role | Value |
|---|---|
| Canvas parchment | `#F5F5F7` |
| Canvas | `#FFFFFF` |
| Pearl surface | `#FAFAFC` |
| Primary ink | `#1D1D1F` |
| Secondary ink | `#6E6E73` |
| Hairline | `#E0E0E0` |
| Action blue | `#0066CC` |
| Focus blue | `#0071E3` |
| Link blue on dark | `#2997FF` |
| Online | `#34C759` |
| Waiting | `#FF9F0A` |
| Alarm | `#FF3B30` |

## Typography

- Windows 以 `Segoe UI Variable` 代替 SF Pro；中文由系统字体回退。
- 页面标题、卡片标题和关键指标使用 600 字重，不使用 500 字重。
- 正文使用 400 字重；小字号文本保持足够行距，不堆叠粗体。

## Components

- 顶部使用 44 px 黑色全局栏，其余工作区以浅色为主。
- 主按钮使用 Action Blue；按下状态使用 Focus Blue。
- 信息卡片使用白色表面和 1 px hairline，不使用阴影。
- 模式选择采用单选逻辑；选中项为蓝底白字。
- 输入框使用 Pearl 表面，聚焦时显示蓝色描边。
- 目标跟踪图维持低对比网格，仅色块标记使用红/绿/蓝。

## Product constraints

- 上位机只做监控、模式控制、记录与告警，不参与视觉算法和电机闭环。
- 不传输图像；界面中的坐标图来自 UDP 遥测数据。
- 所有 UI 调整不得改变 UDP 协议、FPGA 阈值和追踪逻辑。

## Upstream

- Skill adapter: <https://github.com/arumwu/design-md-skill>
- Design library: <https://github.com/VoltAgent/awesome-design-md>
- Apple reference: `../awesome-design-md/design-md/apple/DESIGN.md`
