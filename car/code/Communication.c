#include "Communication.h"

volatile device_value_struct car_value;

extern uint32 system_time;             // 来自 Control.c 的 1ms 计数器

static uint8 rx_frame[COMM_FRAME_SIZE];     // 接收缓冲区
static uint8 rx_count;                       // 接收计数

static void comm_resync_after_bad_frame(void)
{
    uint8 i;

    for(i = 1u; i < COMM_FRAME_SIZE; i++)
    {
        if(rx_frame[i] == COMM_FRAME_HEAD)
        {
            uint8 remain = (uint8)(COMM_FRAME_SIZE - i);
            uint8 j;
            for(j = 0u; j < remain; j++)
            {
                rx_frame[j] = rx_frame[i + j];
            }
            rx_count = remain;
            return;
        }
    }

    rx_count = 0u;
}

// CRC8 校验算法,跟飞控侧完全一致(同样的多项式0x07)
static uint8 comm_crc8(const uint8 *data, uint8 length)
{
    uint8 crc = 0x00u;
    for(uint8 i = 0u; i < length; i++)
    {
        crc ^= data[i];
        for(uint8 bit = 0u; bit < 8u; bit++)
        {
            crc = (crc & 0x80u) ? (uint8)((crc << 1u) ^ 0x07u)
                                : (uint8)(crc << 1u);
        }
    }
    return crc;
}

// 状态机解析单字节
// 偏移:  0      1      2      3      4-5    6-7    8-9    10     11
//        A5     01     SEQ    FLAGS  FWD    RIGHT  YAW    CRC8   5A
//        帧头   命令   序号   标志   前后    左右   航向   校验   帧尾
void uart_parse_byte(uint8 receive_data)
{
    if(rx_count == 0u)
    {
        if(receive_data != COMM_FRAME_HEAD) return;  // 等待帧头
    }
    rx_frame[rx_count++] = receive_data;

    if(rx_count < COMM_FRAME_SIZE) return;           // 未收满12字节

    // 完整帧到达，校验：CMD=0x01、帧尾=0x5A、CRC8匹配
    if(rx_frame[1] == COMM_CMD_TARGET &&
       rx_frame[11] == COMM_FRAME_TAIL &&
       rx_frame[10] == comm_crc8(rx_frame, 10u))
    {
        car_value.target_seq    = rx_frame[2];       // 目标序号
        car_value.flags         = rx_frame[3];       // 标志位

        car_value.receive_fwd   = (int16)(           // 前后偏差（像素）
            (uint16)rx_frame[4] | ((uint16)rx_frame[5] << 8u));

        car_value.receive_right = (int16)(           // 左右偏差（像素）
            (uint16)rx_frame[6] | ((uint16)rx_frame[7] << 8u));

        car_value.receive_yaw   = (int16)(           // 地球系绝对航向（0.01°）
            (uint16)rx_frame[8] | ((uint16)rx_frame[9] << 8u));

        car_value.new_data_flag = 1;                 // 通知主循环
        car_value.receive_timestamp = system_time;
        car_value.frame_count++;
        rx_count = 0u;
    }
    else
    {
        /* A bad byte must not make every following frame lose alignment. */
        comm_resync_after_bad_frame();
    }
}

// 初始化通信相关变量
void car_value_init(void)
{
    rx_count = 0u;
    car_value.new_data_flag = 0;
    car_value.target_seq = 0;
    car_value.flags = 0;
    car_value.receive_fwd = 0;
    car_value.receive_right = 0;
    car_value.receive_yaw = 0;
    car_value.frame_count = 0;
    car_value.feedback_tx_count = 0;
}

// 初始化 UART1（与飞控通信），波特率 57600，使能接收中断
void Communication_Init(void)
{
    uart_init(CAR_RECEIVE_UART, CAR_RECEIVE_BAUDRATE,
              CAR_RECEIVE_TX, CAR_RECEIVE_RX);        // 串口初始化

    uart_rx_trigger_interrupt(CAR_RECEIVE_UART, 1);

    uart_rx_interrupt(CAR_RECEIVE_UART, 1);           // 使能串口接收中断

    car_value_init();
}

// 发送回传帧给飞控
// 帧格式: A5 81 SEQ STATUS SPEED_FWD_L/H SPEED_RIGHT_L/H CRC8 5A
void car_send_feedback(uint8 target_seq, uint8 status,
                       int16 speed_forward_cm_s, int16 speed_right_cm_s)
{
    uint8 frame[COMM_FEEDBACK_SIZE];

    frame[0] = COMM_FRAME_HEAD;
    frame[1] = COMM_CMD_FEEDBACK;
    frame[2] = target_seq;
    frame[3] = status;
    frame[4] = (uint8)((uint16)speed_forward_cm_s & 0x00FFu);
    frame[5] = (uint8)(((uint16)speed_forward_cm_s >> 8u) & 0x00FFu);
    frame[6] = (uint8)((uint16)speed_right_cm_s & 0x00FFu);
    frame[7] = (uint8)(((uint16)speed_right_cm_s >> 8u) & 0x00FFu);
    frame[8] = comm_crc8(frame, 8u);
    frame[9] = COMM_FRAME_TAIL;

    uart_write_buffer(CAR_RECEIVE_UART, frame, COMM_FEEDBACK_SIZE);
    car_value.feedback_tx_count++;
}
