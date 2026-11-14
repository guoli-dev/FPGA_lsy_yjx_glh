#include "mcar_comm.h"

mcar_comm_target_t mcar_comm_target = {0};

static uint8 mcar_comm_rx_frame[MCAR_COMM_FRAME_SIZE];
static uint8 mcar_comm_rx_count;

// CRC8校验算法,必须和飞控端完全一致(同样的多项式0x07)
static uint8 mcar_comm_crc8(const uint8 *data, uint8 length)
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

void mcar_comm_init(void)
{
    memset(&mcar_comm_target, 0, sizeof(mcar_comm_target));
    mcar_comm_rx_count = 0u;
    uart_init(MCAR_COMM_UART, MCAR_COMM_BAUDRATE,
              MCAR_COMM_TX_PIN, MCAR_COMM_RX_PIN);
}

// 解析飞控发来的TARGET帧
// A5 CMD SEQ FLAGS FWD_L FWD_H RIGHT_L RIGHT_H YAW_L YAW_H CRC8 5A
void mcar_comm_poll(void)
{
    uint8 data;
    while(uart_query_byte(MCAR_COMM_UART, &data))
    {
        if(mcar_comm_rx_count == 0u)
        {
            if(data != MCAR_COMM_FRAME_HEAD) continue;
        }
        mcar_comm_rx_frame[mcar_comm_rx_count++] = data;

        if(mcar_comm_rx_count < MCAR_COMM_FRAME_SIZE) continue;

        // 帧收满12字节,校验
        if(mcar_comm_rx_frame[1] == MCAR_COMM_CMD_TARGET &&
           mcar_comm_rx_frame[11] == MCAR_COMM_FRAME_TAIL &&
           mcar_comm_rx_frame[10] == mcar_comm_crc8(mcar_comm_rx_frame, 10u))
        {
            mcar_comm_target.target_seq = mcar_comm_rx_frame[2];
            mcar_comm_target.flags      = mcar_comm_rx_frame[3];

            mcar_comm_target.err_forward_px = (int16)(
                (uint16)mcar_comm_rx_frame[4] |
                ((uint16)mcar_comm_rx_frame[5] << 8u));

            mcar_comm_target.err_right_px = (int16)(
                (uint16)mcar_comm_rx_frame[6] |
                ((uint16)mcar_comm_rx_frame[7] << 8u));

            mcar_comm_target.yaw_earth_cdeg = (int16)(
                (uint16)mcar_comm_rx_frame[8] |
                ((uint16)mcar_comm_rx_frame[9] << 8u));

            mcar_comm_target.timestamp_us = system_time_us();
            mcar_comm_target.valid = 1u;
        }
        // 校验失败的帧直接丢弃,不更新target,不影响上一次有效值

        mcar_comm_rx_count = 0u;
    }
}

// 车→飞控 回传FEEDBACK帧
// A5 81 TARGET_SEQ STATUS FWD_L FWD_H RIGHT_L RIGHT_H CRC8 5A
void mcar_comm_send_feedback(uint8 target_seq, uint8 status,
                              int16 err_forward_px, int16 err_right_px)
{
    uint8 frame[MCAR_COMM_FEEDBACK_SIZE];

    frame[0] = MCAR_COMM_FRAME_HEAD;
    frame[1] = MCAR_COMM_CMD_FEEDBACK;
    frame[2] = target_seq;
    frame[3] = status;
    frame[4] = (uint8)((uint16)err_forward_px & 0x00FFu);
    frame[5] = (uint8)(((uint16)err_forward_px >> 8u) & 0x00FFu);
    frame[6] = (uint8)((uint16)err_right_px & 0x00FFu);
    frame[7] = (uint8)(((uint16)err_right_px >> 8u) & 0x00FFu);
    frame[8] = mcar_comm_crc8(frame, 8u);
    frame[9] = MCAR_COMM_FRAME_TAIL;

    uart_write_buffer(MCAR_COMM_UART, frame, MCAR_COMM_FEEDBACK_SIZE);
}