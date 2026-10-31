# 最终提交包整理记录

日期：2026-10-30。

1. 核对 `D:\FPGA\last\deliverables\isp_demo_60fps_20261030_1218\WORK_LOG.md`：最终 bitgen 完成于 2026-10-30 12:18:23；第一轮时序不合格的 bit 不使用。
2. 比对交付目录正式 bit 与 `integration_ae_isp_demo_60fps/Final/td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit`，两者 SHA-256 均为 `BB5D0FE2D9705D4E78E4DD40430BB4093B9769DBF77271E4F4BADAF895C7D83C`。
3. 检查 bitgen 后的源工程：非备份、非构建输出目录内无晚于 bitgen 的源码/约束修改。复制该工程的完整 `user_source`、`.al`、`.sdc` 与流程 Tcl；未复制顶层历史备份目录、诊断目录和多轮旧 bit。`user_source` 内随源码保留的旧备份文件不被 `.al` 引用。
4. 将正式 bit、备用压缩 bit、最终时序/资源/route 报告、工作记录及演示资料复制到新的独立提交目录。旧工程、旧提交包与交付目录没有被移动或覆盖。
5. 仅把提交包内 `.al` 的 `Project Path` 元数据改为新目录，保留所有 85 条相对源文件引用；RTL、IP、SDC 和 bit 内容未修改。
6. 验证 85 条 `.al` 文件引用全部存在；正式 bit 的 SHA-256 与原交付 bit 相同；关键文件摘要记录在 `SHA256SUMS.txt`。
7. 完成后再次逐项核对 `SHA256SUMS.txt` 的 11 个条目，缺失/哈希不符均为 0；提交包共 266 个文件，约 14.8 MiB。

未执行新的综合、布局布线或上板测试。原工作记录见 `docs/WORK_LOG.md`，正式时序/资源报告见 `reports/`。
