#ifndef MCAR_COMM_H_
#define MCAR_COMM_H_
#include "zf_common_headfile.h"

#define MCAR_COMM_UART                 (UART_5)
#define MCAR_COMM_BAUDRATE             (115200u)
#define MCAR_COMM_TX_PIN               (UART5_TX_P02_1)
#define MCAR_COMM_RX_PIN               (UART5_RX_P02_0)

#define MCAR_COMM_FRAME_HEAD           (0xA5u)
#define MCAR_COMM_FRAME_TAIL           (0x5Au)
#define MCAR_COMM_CMD_TARGET           (0x01u)
#define MCAR_COMM_CMD_FEEDBACK         (0x81u)
#define MCAR_COMM_FRAME_SIZE           (12u)   // TARGET帧(飞控→车)
#define MCAR_COMM_FEEDBACK_SIZE        (10u)   // FEEDBACK帧(车→飞控)

#define MCAR_COMM_FLAG_BEACON_VALID    (1u << 0)
#define MCAR_COMM_FLAG_MCAR_VALID      (1u << 1)
#define MCAR_COMM_FLAG_YAW_VALID       (1u << 2)
#define MCAR_COMM_FLAG_OBS_HELD        (1u << 3)
#define MCAR_COMM_FLAG_TARGET_ACTIVE   (1u << 4)
#define MCAR_COMM_FLAG_STOP            (1u << 7)

#define MCAR_COMM_STATUS_TRACKING      (1u << 0)
#define MCAR_COMM_STATUS_ARRIVED       (1u << 1)
#define MCAR_COMM_STATUS_FAILED        (1u << 2)

// 到位判定阈值(单位:像素,和err_forward_px/err_right_px同单位)
#define MCAR_COMM_ARRIVE_THRESHOLD_FWD    (5)
#define MCAR_COMM_ARRIVE_THRESHOLD_RIGHT  (5)

// 车收到的目标指令(来自飞控TARGET帧解析结果)
typedef struct
{
    uint8  valid;               // 本帧是否有效
    uint8  target_seq;          // 目标序列号
    uint8  flags;               // 标志位(BEACON_VALID/STOP等)
    int16  err_forward_px;      // 前向偏差
    int16  err_right_px;        // 右向偏差
    int16  yaw_earth_cdeg;      // 目标航向(厘度)
    uint32 timestamp_us;        // 收到时刻
} mcar_comm_target_t;

extern mcar_comm_target_t mcar_comm_target;

void mcar_comm_init(void);
void mcar_comm_poll(void);                      // 主循环/中断里调用,解析飞控发来的TARGET帧
void mcar_comm_send_feedback(uint8 target_seq, uint8 status,
                              int16 err_forward_px, int16 err_right_px);

#endif