#ifndef CODE_TELEMETRY_H_
#define CODE_TELEMETRY_H_

#include "zf_common_headfile.h"

/*
 * 车端遥测(只发不收): UART_1, 115200 8N1
 *   模块 TX -> P04_0(MCU RX, 本工程不用)
 *   模块 RX <- P04_1(MCU TX)
 *
 * 帧长 42 字节, 主循环 20ms 限速发送, 多字节均为小端:
 *   0     C5        帧头
 *   1     01        类型: 车端遥测
 *   2     seq       帧序号
 *   3     2A        帧长(42)
 *   4     flags     bit0 IMU就绪 bit1 零漂完成 bit2 追踪使能 bit3 已到达
 *                   bit4 当前见目标 bit5 已锁定颜色 bit6 停车请求
 *   5     mode      目标色选择 0自动 1红 2绿 3蓝
 *   6     locked    当前锁定色 0无 1红 2绿 3蓝
 *   7     dev       目标横向偏差(int8, 0x80=无目标)
 *   8     wid       目标宽度
 *   9-14  三色 dev/wid(红 绿 蓝)
 *   15-17 cmdX cmdY cmdZ      下发的麦轮速度指令(int8)
 *   18-25 LF RF LB RB          四轮实测速度(int16)
 *   26-29 vx vy                编码器解算车体速度(int16, cm/s)
 *   30-31 heading              当前航向(int16, 0.1度)
 *   32-33 target_angle         航向目标(int16, 0.1度)
 *   34-35 gyro_z               陀螺 Z 角速度(int16, 0.1度/秒)
 *   36-37 batt                 电池电压(int16, 0.1V, 未初始化时为 0)
 *   38-39 uptime               系统时间低 16 位(ms)
 *   40    crc8                 CRC8 多项式 0x07, 覆盖 0~39
 *   41    5C                   帧尾
 */
void Telemetry_Init(void);
void Telemetry_Task(void);      // 主循环里调用, 内部按 20ms 限速

#endif /* CODE_TELEMETRY_H_ */
