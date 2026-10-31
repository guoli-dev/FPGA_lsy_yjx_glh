#include "ColorTrack.h"

/*
 * ColorTrack.c  --  色块追踪: FPGA -> 小车 UART_1
 *
 * 数据流: uart1_isr 收到字节 -> ColorTrack_UartRxByte() -> 收满 7 字节 -> on_frame()
 *         解析出 (dev, wid) -> 20ms控制周期生成横移/前进指令
 */

extern uint32 system_time;                 // 来自 Control.c 的 1ms 计数器

// ======================= 串口(FPGA 色块帧) =======================
// 接收口由 ColorTrack.h 的 COLOR_TRACK_RX_PORT 选择(1=UART_1 2=UART_2)
#define CT_UART     COLOR_TRACK_RX_UART
#define CT_BAUD     115200u                // 8N1
#define CT_TX_PIN   COLOR_TRACK_RX_TX_PIN
#define CT_RX_PIN   COLOR_TRACK_RX_RX_PIN

#define CT_FRAME_HEAD   (0xAAu)            // 帧头, 数据字节里不会出现
#define CT_DATA_LEN     (6u)               // 6 个数据字节

#define COLOR_TRACK_TIMEOUT_MS  200u       // 超过这么久没收到帧就停车(丢链保护)

// ======================= 状态 =======================
volatile uint8  color_track_enable = 0;
volatile int8   color_track_dev    = (int8)0x80;
volatile uint8  color_track_wid    = 0;
volatile uint8  color_track_found  = 0;
volatile uint8  color_track_locked = 0;
volatile uint8  color_track_mode   = 0;   // 0自动(就近) 1红 2绿 3蓝
volatile float  color_track_yaw_cmd = 0.0f;
volatile uint8  color_track_arrived = 0u;
volatile uint32 color_track_frames = 0;
volatile uint32 color_track_rx_bytes = 0;
volatile int8  color_track_dev_r = (int8)0x80;
volatile int8  color_track_dev_g = (int8)0x80;
volatile int8  color_track_dev_b = (int8)0x80;
volatile uint8 color_track_wid_r = 0;
volatile uint8 color_track_wid_g = 0;
volatile uint8 color_track_wid_b = 0;

static uint8  ct_buf[CT_DATA_LEN];
static uint8  ct_idx     = 0;
static uint8  ct_in_frame = 0;
static volatile uint32 ct_last_rx_ms = 0;

// ======================= 解析 =======================
// 每收齐一帧调一次 (在串口中断上下文里)
// 多色策略: 就近优先(取宽度最大者) + 锁定滞回(避免两个色块宽度接近时目标来回跳)
static uint8 ct_miss = 0;      // 锁定色连续丢失帧数

static void color_track_on_frame(uint8 *d)
{
    int8  cand_dev[3];
    uint8 cand_wid[3];
    uint8 cand_ok[3];
    uint8 i, best = 0u, best_wid = 0u;
    int8  dev;
    uint8 wid;

    cand_dev[0] = (int8)d[0]; cand_wid[0] = d[1];   // 红
    cand_dev[1] = (int8)d[2]; cand_wid[1] = d[3];   // 绿
    cand_dev[2] = (int8)d[4]; cand_wid[2] = d[5];   // 蓝

    color_track_dev_r = cand_dev[0]; color_track_wid_r = cand_wid[0];
    color_track_dev_g = cand_dev[1]; color_track_wid_g = cand_wid[1];
    color_track_dev_b = cand_dev[2]; color_track_wid_b = cand_wid[2];

    // 逐色判断是否有效, 同时找宽度最大的
    for(i = 0u; i < 3u; i++)
    {
        uint8 allowed = (COLOR_TRACK_USE_MASK >> i) & 1u;

        // 按键选了固定颜色时, 其它颜色不参与
        if((color_track_mode != 0u) && ((uint8)(i + 1u) != color_track_mode))
        {
            allowed = 0u;
        }

        cand_ok[i] = (allowed &&
                      (cand_dev[i] != (int8)0x80) &&
                      (cand_wid[i] > 0u)) ? 1u : 0u;

        if(cand_ok[i] && (cand_wid[i] > best_wid))
        {
            best_wid = cand_wid[i];
            best = (uint8)(i + 1u);                 // 1红 2绿 3蓝
        }
    }

    if(color_track_locked == 0u)                    // 还没锁 -> 锁当前最大
    {
        color_track_locked = best;
        ct_miss = 0u;
    }
    else
    {
        uint8 li = (uint8)(color_track_locked - 1u);

        if(cand_ok[li])                             // 锁定的颜色还在
        {
            ct_miss = 0u;
            // 只有别的颜色比它明显更大(超过 margin)才换, 否则保持, 防止来回跳
            if((best != 0u) && (best != color_track_locked) &&
               ((uint16)cand_wid[best - 1u] >
                (uint16)cand_wid[li] + COLOR_TRACK_SWITCH_MARGIN))
            {
                color_track_locked = best;
            }
        }
        else                                        // 锁定的颜色这一帧没看到
        {
            if(ct_miss < 255u) ct_miss++;
            if(ct_miss >= COLOR_TRACK_LOCK_LOST_FRAMES)
            {
                color_track_locked = best;          // 丢太久 -> 换/清空(可能为0)
                ct_miss = 0u;
            }
            else
            {
                // 短暂丢失: 保持上一帧目标, 不更新 dev/宽, 避免一帧闪断就抖
                color_track_frames++;
                ct_last_rx_ms = system_time;
                return;
            }
        }
    }

    // 输出当前锁定颜色的 dev/宽
    if(color_track_locked != 0u)
    {
        dev = cand_dev[color_track_locked - 1u];
        wid = cand_wid[color_track_locked - 1u];
    }
    else
    {
        dev = (int8)0x80;
        wid = 0u;
    }

    // 摄像头画面左右镜像时, 把控制用的 dev 符号翻过来(0x80=无目标不参与)
#if COLOR_TRACK_DEV_INVERT
    if(dev != (int8)0x80) dev = (int8)(-dev);
#endif

    color_track_dev   = dev;
    color_track_wid   = wid;
    color_track_found = ((dev != (int8)0x80) && (wid > 0u)) ? 1u : 0u;
    color_track_frames++;
    ct_last_rx_ms = system_time;
}

// ======================= 视觉伺服 =======================
// 看见目标: 只平移; 看不见: 按最后看到的一侧旋转搜索; 转满一圈停下
static float ct_dev_f = 0.0f;      // 低通后的偏差
static float ct_wid_f = 0.0f;      // 低通后的宽度
static float ct_cmd_x = 0.0f;      // 当前输出(横移)
static float ct_cmd_y = 0.0f;      // 当前输出(前后)
static float ct_cmd_z = 0.0f;      // 当前输出(转向)

static uint8  ct_ever_found    = 0u;     // 上电后是否看见过目标
static uint8  ct_searching     = 0u;     // 正在旋转搜索
static uint8  ct_gaveup        = 0u;     // 转满一圈没找到, 原地停
static int8   ct_search_dir    = 1;      // 搜索方向: +1=右转(+Z), -1=左转(-Z)
static float  ct_last_dev      = 0.0f;   // 最后一次看见时的水平偏差
static float  ct_last_wid      = 0.0f;   // 最后一次看见时的宽度
static uint8  ct_arrived       = 0u;     // 已追到(锁存)
static float  ct_search_accum  = 0.0f;   // 搜索已转过的角度(度)
static float  ct_angle_prev    = 0.0f;   // 上一周期的航向角
static uint32 ct_last_found_ms = 0u;     // 最后一次看见目标的时间

static float ct_slew(float cur, float target, float step)
{
    if(target > (cur + step)) return (cur + step);
    if(target < (cur - step)) return (cur - step);
    return target;
}

// 麦轮视觉伺服: 看见目标只平移; 丢失后按最后位置方向旋转搜索; 转满一圈放弃
void ColorTrack_UpdateCommand(void)
{
    float target_x = 0.0f;
    float target_y = 0.0f;
    float target_z = 0.0f;
    uint8 visible;

    if(!color_track_enable)
    {
        ct_cmd_x = ct_slew(ct_cmd_x, 0.0f, COLOR_TRACK_ACCEL_STEP);
        ct_cmd_y = ct_slew(ct_cmd_y, 0.0f, COLOR_TRACK_ACCEL_STEP);
        ct_cmd_z = ct_slew(ct_cmd_z, 0.0f, COLOR_TRACK_Z_STEP);
        Car_Speed_X = ct_cmd_x;
        Car_Speed_Y = ct_cmd_y;
        color_track_yaw_cmd = ct_cmd_z;
        return;
    }

    visible = ((color_track_found != 0u) &&
               ((uint32)(system_time - ct_last_rx_ms) <= COLOR_TRACK_TIMEOUT_MS)) ? 1u : 0u;

    if(visible)
    {
        float err_w;
        uint8 do_translate = 1u;

        // 看见目标: 记录状态, 退出搜索
        ct_ever_found    = 1u;
        ct_last_found_ms = system_time;
        ct_searching     = 0u;
        ct_gaveup        = 0u;
        ct_search_accum  = 0.0f;

        // dev / 宽度 一阶低通
        ct_dev_f += COLOR_TRACK_DEV_ALPHA * ((float)color_track_dev - ct_dev_f);
        ct_wid_f += COLOR_TRACK_WID_ALPHA * ((float)color_track_wid - ct_wid_f);
        ct_last_dev = ct_dev_f;
        ct_last_wid = ct_wid_f;

        // 追到判定: 宽度足够大 -> 到达并锁存; 回落到 到达值-回差 以下才解除
        if(ct_wid_f >= COLOR_TRACK_ARRIVE_W) ct_arrived = 1u;
        else if(ct_wid_f < (COLOR_TRACK_ARRIVE_W - COLOR_TRACK_ARRIVE_HYST)) ct_arrived = 0u;
        color_track_arrived = ct_arrived;

        if(ct_arrived)
        {
            // 已追到: 全部停住
            do_translate = 0u;
            target_z = 0.0f;
        }

        if(do_translate)
        {
            float fwd_gate = 1.0f;
            float adev = fabsf(ct_dev_f);

#if COLOR_TRACK_LATERAL_ON
            // 横移: 减掉死区再乘增益, 死区边界处连续
            if(ct_dev_f > (float)COLOR_TRACK_DEADBAND)
            {
                target_x = (ct_dev_f - (float)COLOR_TRACK_DEADBAND) * COLOR_TRACK_LATERAL_KP;
            }
            else if(ct_dev_f < -(float)COLOR_TRACK_DEADBAND)
            {
                target_x = (ct_dev_f + (float)COLOR_TRACK_DEADBAND) * COLOR_TRACK_LATERAL_KP;
            }
            if(target_x >  COLOR_TRACK_MAX_LATERAL_SPEED) target_x =  COLOR_TRACK_MAX_LATERAL_SPEED;
            if(target_x < -COLOR_TRACK_MAX_LATERAL_SPEED) target_x = -COLOR_TRACK_MAX_LATERAL_SPEED;
#endif

            // 前后: 近处线性收敛(保精度), 远处额外加速(提速度)
            err_w = COLOR_TRACK_DIST_W - ct_wid_f;
            if(err_w > COLOR_TRACK_DIST_DEADBAND_W)
            {
                float e = err_w - COLOR_TRACK_DIST_DEADBAND_W;
                target_y = e * COLOR_TRACK_DIST_KP;
                if(e > COLOR_TRACK_FAR_BOOST_START)
                {
                    target_y += (e - COLOR_TRACK_FAR_BOOST_START) * COLOR_TRACK_FAR_BOOST_KP;
                }
            }
            else if(err_w < -COLOR_TRACK_DIST_DEADBAND_W)
            {
                target_y = (err_w + COLOR_TRACK_DIST_DEADBAND_W) * COLOR_TRACK_DIST_KP;
            }
            // 偏离中心越大, 前进越少; 偏太多就只横移居中, 不斜着冲出视野
            if(adev >= COLOR_TRACK_FWD_GATE_END)
            {
                fwd_gate = 0.0f;
            }
            else if(adev > COLOR_TRACK_FWD_GATE_START)
            {
                fwd_gate = (COLOR_TRACK_FWD_GATE_END - adev) /
                           (COLOR_TRACK_FWD_GATE_END - COLOR_TRACK_FWD_GATE_START);
            }
            target_y *= fwd_gate;

            if(target_y >  COLOR_TRACK_MAX_FWD)  target_y =  COLOR_TRACK_MAX_FWD;
            if(target_y < -COLOR_TRACK_MAX_BACK) target_y = -COLOR_TRACK_MAX_BACK;

            target_z = 0.0f;                       // 看得见 -> 只平移, 不转
        }
    }
    else if(ct_ever_found && !ct_gaveup &&
            ((uint32)(system_time - ct_last_rx_ms) <= COLOR_TRACK_TIMEOUT_MS))
    {
        // 串口还在来帧, 只是当前帧没看到目标

        // 消失时已经很近(宽度接近到达值) -> 视为已追到, 停车不再搜索
        if(!ct_arrived &&
           (ct_last_wid >= (COLOR_TRACK_ARRIVE_W - COLOR_TRACK_ARRIVE_HYST)))
        {
            ct_arrived = 1u;
            color_track_arrived = 1u;
        }

        if(ct_arrived)
        {
            // 已追到: 保持停止, 不做任何动作
        }
        else if((uint32)(system_time - ct_last_found_ms) < COLOR_TRACK_LOST_MS)
        {
            // 短暂丢帧: 保持上一周期命令, 避免抖一下
            target_x = ct_cmd_x;
            target_y = ct_cmd_y;
        }
        else
        {
#if COLOR_TRACK_SEARCH_ENABLE
            if(!ct_searching)
            {
                // 进入搜索: 按最后看到的一侧决定转向方向
                ct_searching    = 1u;
                ct_search_accum = 0.0f;
                ct_angle_prev   = (float)imu.gyro.angle[Z];

                if(ct_last_dev > (float)COLOR_TRACK_DEADBAND)
                {
                    ct_search_dir = 1;          // 最后在右侧 -> 向右(顺时针)找
                }
                else if(ct_last_dev < -(float)COLOR_TRACK_DEADBAND)
                {
                    ct_search_dir = -1;         // 最后在左侧 -> 向左找
                }
                // 居中丢失时沿用上一次的搜索方向
            }

            // 用陀螺积分角累计实际转过的角度
            {
                float a = (float)imu.gyro.angle[Z];
                float d = a - ct_angle_prev;
                while(d >  180.0f) d -= 360.0f;
                while(d < -180.0f) d += 360.0f;
                ct_angle_prev = a;
                ct_search_accum += fabsf(d);
            }

            if(ct_search_accum >= COLOR_TRACK_SEARCH_MAX_DEG)
            {
                ct_searching = 0u;
                ct_gaveup    = 1u;              // 转满一圈没找到 -> 原地停
            }
            else
            {
                target_z = (float)ct_search_dir * COLOR_TRACK_SEARCH_SPIN * (float)COLOR_TRACK_SEARCH_SIGN;
            }
#endif
        }
    }
    // 转满一圈仍未找到: target 全 0, 原地不动; 再次看见目标会自动恢复

    ct_cmd_x = ct_slew(ct_cmd_x, target_x, COLOR_TRACK_ACCEL_STEP);
    ct_cmd_y = ct_slew(ct_cmd_y, target_y, COLOR_TRACK_ACCEL_STEP);
    ct_cmd_z = ct_slew(ct_cmd_z, target_z, COLOR_TRACK_Z_STEP);

    Car_Speed_X = ct_cmd_x;
    Car_Speed_Y = ct_cmd_y;
    color_track_yaw_cmd = ct_cmd_z;
}

// ======================= 串口字节状态机 =======================
void ColorTrack_UartRxByte(uint8 b)
{
    color_track_rx_bytes++;                 // 先数字节: 判断串口到底有没有数据进来
    if(!ct_in_frame)
    {
        if(b == CT_FRAME_HEAD)
        {
            ct_in_frame = 1;
            ct_idx = 0;
        }
    }
    else
    {
        ct_buf[ct_idx++] = b;
        if(ct_idx == CT_DATA_LEN)
        {
            ct_in_frame = 0;
            color_track_on_frame(ct_buf);
        }
    }
}

// 主循环里周期调用: 丢链保护
void ColorTrack_Poll(void)
{
    if(!color_track_enable) return;
    if((uint32)(system_time - ct_last_rx_ms) > COLOR_TRACK_TIMEOUT_MS)
    {
        color_track_found = 0u;          // 控制周期看到丢链后把平移速度清零
    }
}

// ======================= 按键选色 =======================
// 周期调用(建议 10ms): 板载按键, 每按一次循环切换 自动->红->绿->蓝->自动
void ColorTrack_KeyTask(void)
{
#if COLOR_TRACK_USE_KEY
    key_scanner();

    if(key_get_state(COLOR_TRACK_KEY) == KEY_SHORT_PRESS)
    {
        key_clear_state(COLOR_TRACK_KEY);

        color_track_mode++;
        if(color_track_mode > 3u) color_track_mode = 0u;

        // 换目标后清掉锁定, 下一帧立刻锁到新颜色
        color_track_locked = 0u;
        ct_miss = 0u;
        ct_arrived = 0u;
        color_track_arrived = 0u;
    }
#endif
}

// ======================= 初始化 =======================
void ColorTrack_Init(void)
{
    uart_init(CT_UART, CT_BAUD, CT_TX_PIN, CT_RX_PIN);   // 115200 8N1
    uart_rx_trigger_interrupt(CT_UART, 1);               // 触发深度: 每收 1 字节进中断
    uart_rx_interrupt(CT_UART, 1);                       // 使能接收中断
#if COLOR_TRACK_USE_KEY
    key_init(COLOR_TRACK_KEY_SCAN_MS);                   // 板载按键: 选择要追的颜色
#endif

    ct_idx = 0;
    ct_in_frame = 0;
    ct_dev_f = 0.0f;
    ct_wid_f = 0.0f;
    ct_cmd_x = 0.0f;
    ct_cmd_y = 0.0f;
    ct_cmd_z = 0.0f;
    color_track_yaw_cmd = 0.0f;
    ct_ever_found    = 0u;
    ct_searching     = 0u;
    ct_gaveup        = 0u;
    ct_search_dir    = 1;
    ct_last_dev      = 0.0f;
    ct_search_accum  = 0.0f;
    ct_angle_prev    = 0.0f;
    ct_last_found_ms = system_time;
    ct_last_wid      = 0.0f;
    ct_arrived       = 0u;
    color_track_arrived = 0u;
    ct_last_rx_ms = system_time;
    color_track_dev   = (int8)0x80;
    color_track_wid   = 0;
    color_track_found = 0;
    color_track_locked = 0;
    color_track_mode   = 0u;
    ct_miss = 0u;
    color_track_frames = 0;
    color_track_dev_r = (int8)0x80; color_track_wid_r = 0;
    color_track_dev_g = (int8)0x80; color_track_wid_g = 0;
    color_track_dev_b = (int8)0x80; color_track_wid_b = 0;

    color_track_enable = COLOR_TRACK_ENABLE;             // 上电是否直接追踪
}
