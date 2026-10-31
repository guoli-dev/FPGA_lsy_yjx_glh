#include "zf_common_headfile.h"

// 车端遥测: UART_1 只发不收, 20ms 一帧, 供 PC 端无线监控
// 帧格式见 Telemetry.h

#define TELEMETRY_UART          UART_1
#define TELEMETRY_BAUD          115200u
#define TELEMETRY_TX_PIN        UART1_TX_P04_1
#define TELEMETRY_RX_PIN        UART1_RX_P04_0
#define TELEMETRY_PERIOD_MS     20u
#define TELEMETRY_FRAME_LEN     42u

#define TL_FRAME_HEAD           0xC5u
#define TL_FRAME_TYPE           0x01u
#define TL_FRAME_TAIL           0x5Cu

#define TL_FLAG_IMU_READY       0x01u
#define TL_FLAG_ZERO_DONE       0x02u
#define TL_FLAG_TRACK_ENABLE    0x04u
#define TL_FLAG_ARRIVED         0x08u
#define TL_FLAG_TARGET_SEEN     0x10u
#define TL_FLAG_LOCKED          0x20u
#define TL_FLAG_STOP_REQUEST    0x40u

extern uint32 system_time;              // Control.c 的 1ms 计数器
extern volatile uint8 imu_ready;        // main_cm7_0.c

static uint8 telemetry_seq = 0u;

static uint8 telemetry_crc8(const uint8 *data, uint8 length)
{
    uint8 crc = 0x00u;
    uint8 i, bit;

    for(i = 0u; i < length; i++)
    {
        crc ^= data[i];
        for(bit = 0u; bit < 8u; bit++)
        {
            crc = (crc & 0x80u) ? (uint8)((crc << 1u) ^ 0x07u)
                                : (uint8)(crc << 1u);
        }
    }
    return crc;
}

static void put_u16(uint8 *p, uint16 v)
{
    p[0] = (uint8)(v & 0xFFu);
    p[1] = (uint8)((v >> 8u) & 0xFFu);
}

static int8 clamp_i8(float v)
{
    if(v >  127.0f) return  127;
    if(v < -128.0f) return -128;
    return (int8)v;
}

static int16 clamp_i16(float v)
{
    if(v >  32767.0f) return  32767;
    if(v < -32768.0f) return -32768;
    return (int16)v;
}

void Telemetry_Init(void)
{
    // 只用来发送, 不使能接收中断, 避免 uart1_isr 把回传数据喂进色块解析
    uart_init(TELEMETRY_UART, TELEMETRY_BAUD, TELEMETRY_TX_PIN, TELEMETRY_RX_PIN);
    telemetry_seq = 0u;
}

void Telemetry_Task(void)
{
    static uint32 last_ms = 0;
    uint8 f[TELEMETRY_FRAME_LEN];
    uint8 flags = 0u;

    if((uint32)(system_time - last_ms) < TELEMETRY_PERIOD_MS)
    {
        return;
    }
    last_ms = system_time;

    if(imu_ready)                        flags |= TL_FLAG_IMU_READY;
    if(!imu.gyro.zero_calc_flag)         flags |= TL_FLAG_ZERO_DONE;
    if(color_track_enable)               flags |= TL_FLAG_TRACK_ENABLE;
    if(color_track_arrived)              flags |= TL_FLAG_ARRIVED;
    if(color_track_found)                flags |= TL_FLAG_TARGET_SEEN;
    if(color_track_locked)               flags |= TL_FLAG_LOCKED;
    if(car_stop_requested)               flags |= TL_FLAG_STOP_REQUEST;

    f[0]  = TL_FRAME_HEAD;
    f[1]  = TL_FRAME_TYPE;
    f[2]  = telemetry_seq++;
    f[3]  = (uint8)TELEMETRY_FRAME_LEN;
    f[4]  = flags;
    f[5]  = color_track_mode;
    f[6]  = color_track_locked;
    f[7]  = (uint8)color_track_dev;
    f[8]  = color_track_wid;

    f[9]  = (uint8)color_track_dev_r;
    f[10] = color_track_wid_r;
    f[11] = (uint8)color_track_dev_g;
    f[12] = color_track_wid_g;
    f[13] = (uint8)color_track_dev_b;
    f[14] = color_track_wid_b;

    f[15] = (uint8)clamp_i8(Car_Speed_X);
    f[16] = (uint8)clamp_i8(Car_Speed_Y);
    f[17] = (uint8)clamp_i8(Car_Speed_Z);

    put_u16(&f[18], (uint16)LF_encoder_data);
    put_u16(&f[20], (uint16)RF_encoder_data);
    put_u16(&f[22], (uint16)LB_encoder_data);
    put_u16(&f[24], (uint16)RB_encoder_data);

    put_u16(&f[26], (uint16)clamp_i16(car_actual_vx));
    put_u16(&f[28], (uint16)clamp_i16(car_actual_vy));

    put_u16(&f[30], (uint16)clamp_i16((float)imu.gyro.angle[Z] * 10.0f));
    put_u16(&f[32], (uint16)clamp_i16(Target_Angle * 10.0f));
    put_u16(&f[34], (uint16)clamp_i16((float)GYRO_DATA_Z / GYRO_SPL * 10.0f));

    put_u16(&f[36], (uint16)clamp_i16(valtage * 10.0f));
    put_u16(&f[38], (uint16)(system_time & 0xFFFFu));

    f[40] = telemetry_crc8(f, 40u);
    f[41] = TL_FRAME_TAIL;

    uart_write_buffer(TELEMETRY_UART, f, TELEMETRY_FRAME_LEN);
}
