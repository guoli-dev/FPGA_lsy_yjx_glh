/*#ifndef CODE_COMMUNICATION_H_
#define CODE_COMMUNICATION_H_

#define CAR_RECEIVE_UART      UART_1
#define CAR_RECEIVE_BAUDRATE  57600
#define CAR_RECEIVE_TX        UART1_TX_P04_1
#define CAR_RECEIVE_RX        UART1_RX_P04_0

typedef struct
{
    volatile uint8 receive_data_buffer[6];               // 接收缓冲区

    volatile uint8 send_data_buffer[6];               // 发送缓冲区

    volatile uint8 receive_data_count;                   // 接收计数

    volatile uint8 sum_check_data;                       // 校验位

    volatile int8 receive_x_data;              // 接收到的x数据

    volatile int8 receive_y_data;             // 接收到的y数据

    volatile uint8 new_data_flag;

}device_value_struct;

extern volatile device_value_struct car_value;

void uart_control_callback(void);
void Communication_Init(void);
void uart_parse_byte(uint8 receive_data);

#endif*/

#ifndef CODE_COMMUNICATION_H_
#define CODE_COMMUNICATION_H_

#include "zf_common_headfile.h"

/*
 * 飞控 → 小车（12字节）:
 *   A5  01  SEQ  FLAGS  FWD_L FWD_H  RIGHT_L RIGHT_H  YAW_L YAW_H  CRC8  5A
 *
 * 小车 → 飞控（10字节）:
 *   A5  81  SEQ  STATUS  FWD_L FWD_H  RIGHT_L RIGHT_H  CRC8  5A
 *
 * 多字节为小端序（低字节在前），CRC8 多项式 0x07
 */

#define CAR_RECEIVE_UART      UART_1
#define CAR_RECEIVE_BAUDRATE  115200
#define CAR_RECEIVE_TX        UART1_TX_P04_1
#define CAR_RECEIVE_RX        UART1_RX_P04_0

#define COMM_FRAME_HEAD           (0xA5u)
#define COMM_FRAME_TAIL           (0x5Au)
#define COMM_CMD_TARGET           (0x01u)     // 飞控→小车 目标帧
#define COMM_CMD_FEEDBACK         (0x81u)     // 小车→飞控 回传帧
#define COMM_FRAME_SIZE           (12u)       // 目标帧总长度
#define COMM_FEEDBACK_SIZE        (10u)       // 回传帧总长度

// FLAGS 位定义（飞控发来的状态标志）
#define COMM_FLAG_BEACON_VALID    (1u << 0)   // bit0: 信标有效
#define COMM_FLAG_MCAR_VALID      (1u << 1)   // bit1: 小车识别有效
#define COMM_FLAG_YAW_VALID       (1u << 2)   // bit2: Yaw 有效
#define COMM_FLAG_OBS_HELD        (1u << 3)   // bit3: 使用保持的旧观测
#define COMM_FLAG_TARGET_ACTIVE   (1u << 4)   // bit4: 目标任务激活
#define COMM_FLAG_RECOVERY_SLOW   (1u << 5)   // bit5: 飞机高度恢复，请求限速
#define COMM_FLAG_STOP            (1u << 7)   // bit7: 停车

// STATUS 位定义（小车回传的执行状态）
#define COMM_STATUS_TRACKING      (1u << 0)   // bit0: 正在跟踪
#define COMM_STATUS_ARRIVED       (1u << 1)   // bit1: 已经到达
#define COMM_STATUS_FAILED        (1u << 2)   // bit2: 执行失败
#define COMM_STATUS_STOPPING      (1u << 3)   // bit3: 已收到停车请求，仍在减速
#define COMM_STATUS_STOPPED       (1u << 4)   // bit4: 编码器确认已停止
#define COMM_STATUS_COMM_LOST     (1u << 5)   // bit5: 命令超时
#define COMM_STATUS_SPEED_VALID   (1u << 6)   // bit6: 回传字段为实测前/右速度(cm/s)

// 到达判定阈值（像素单位）
#define COMM_ARRIVE_THRESHOLD_FWD    (5)
#define COMM_ARRIVE_THRESHOLD_RIGHT  (5)

// 从飞控收到的解析结果
typedef struct
{
    volatile uint8  new_data_flag;      // 新帧到达标志
    volatile uint8  target_seq;         // 当前目标序号
    volatile uint8  flags;              // FLAGS 标志位
    volatile int16  receive_fwd;        // 信标前后偏差（像素，>0 在前方）
    volatile int16  receive_right;      // 信标左右偏差（像素，>0 在右侧）
    volatile int16  receive_yaw;        // 地球系绝对航向（0.01°）
    volatile uint32 receive_timestamp;   // 接收时间戳(ms),uart_parse_byte中设置
    volatile uint32 frame_count;         // 接收帧计数器，每收到一帧+1
    volatile uint32 feedback_tx_count;   // 已完成发送的10字节回包数
} device_value_struct;

extern volatile device_value_struct car_value;

void Communication_Init(void);
void uart_parse_byte(uint8 receive_data);
void car_send_feedback(uint8 target_seq, uint8 status,
                       int16 speed_forward_cm_s, int16 speed_right_cm_s);

#endif
