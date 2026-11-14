/*
 * Control.c
 *
 *  Created on: 2025��12��25��
 *      Author: lenovo
 */

#include "zf_common_headfile.h"

extern volatile uint8 imu_ready;

// ===== DWT 周期计数器（250MHz，1周期=4ns） =====
#define DWT_CYCCNT  (*(volatile uint32_t *)0xE0001004)
#define DWT_CTRL    (*(volatile uint32_t *)0xE0001000)
#define DEMCR       (*(volatile uint32_t *)0xE000EDFC)
#define DEMCR_TRCENA    (1UL << 24)
#define DWT_CTRL_CYCCNTENA  (1UL << 0)

// ===== 性能分析变量 =====
volatile uint32 profile_total_max = 0;   // pit_handler总耗时(us)
volatile uint32 profile_imu_max = 0;     // get_imu_data耗时(us)
volatile uint32 profile_task_max = 0;    // imu_task耗时(us)
volatile uint32 profile_ctrl_max = 0;    // 控制块耗时(us)
volatile uint32 profile_enc_max = 0;     // Encoder_Get_Speed耗时(us)
volatile uint32 profile_pid_max = 0;     // PID+Motor耗时(us)
volatile uint32 profile_poll_max = 0;    // mcar_comm_poll耗时(us)

#define PROFILE_US(var)  ((DWT_CYCCNT - (var)) / 250u)

void profile_dwt_init(void)
{
    DEMCR |= DEMCR_TRCENA;          // 使能 DWT
    DWT_CTRL |= DWT_CTRL_CYCCNTENA; // 使能周期计数器
}

uint32 system_time = 0;

int16 Target_Speed = 0;
float Target_Angle = 0.0f;

int16_t LF_Target_Speed = 0;
int16_t LB_Target_Speed = 0;
int16_t RF_Target_Speed = 0;
int16_t RB_Target_Speed = 0;

float Car_Speed_X = 0.0f;
float Car_Speed_Y = 0.0f;
float Car_Speed_Z = 0.0f;

location_struct location;


// Control.c ��,ȫ�ֱ���
volatile uint8 need_send_arrive_flag = 0;
volatile uint8 pending_arrive_status = 0;
// 反馈缓存：在 pit_handler 中捕获，主循环发送
volatile uint8  fb_seq = 0;
volatile int16  fb_fwd = 0;
volatile int16  fb_right = 0;


volatile uint8 car_stop_requested = 0u;
volatile uint8 car_comm_lost = 0u;
volatile uint8 car_stopped_confirmed = 0u;
volatile uint8 car_stopped_count = 0u;
volatile float car_actual_vx = 0.0f;
volatile float car_actual_vy = 0.0f;


int8 rc_rot_active = 0;    // ң����ת�����־
#define TEST_MODE_DIRECT_DRIVE   0 // 1=����ģʽ,ֱ���ֶ����ٶ�; 0=����ģʽ,���������

void Test_Direct_Drive(void)
{
    // ֻ��X����ƽ��,�ȸ�һ������С��ֵ
    Car_Speed_X = 0.0f;
    Car_Speed_Y = 10.0f;//4.9cm/s
    Car_Speed_Z = 0.0f;
}
void Set_Car_Speed(float Speed_X,float Speed_Y,float Speed_Z)
{
    // 限幅防止溢出
    float lf = Speed_Y + Speed_X + Speed_Z;
    float lb = Speed_Y - Speed_X + Speed_Z;
    float rf = Speed_Y - Speed_X - Speed_Z;
    float rb = Speed_Y + Speed_X - Speed_Z;
    #define SET_SPEED_MAX 5000.0f
    if(lf >  SET_SPEED_MAX) lf =  SET_SPEED_MAX; if(lf < -SET_SPEED_MAX) lf = -SET_SPEED_MAX;
    if(lb >  SET_SPEED_MAX) lb =  SET_SPEED_MAX; if(lb < -SET_SPEED_MAX) lb = -SET_SPEED_MAX;
    if(rf >  SET_SPEED_MAX) rf =  SET_SPEED_MAX; if(rf < -SET_SPEED_MAX) rf = -SET_SPEED_MAX;
    if(rb >  SET_SPEED_MAX) rb =  SET_SPEED_MAX; if(rb < -SET_SPEED_MAX) rb = -SET_SPEED_MAX;
    LF_Target_Speed = (int16_t)lf;
    LB_Target_Speed = (int16_t)lb;
    RF_Target_Speed = (int16_t)rf;
    RB_Target_Speed = (int16_t)rb;
}

void Get_Location(void)
{
    location.self_vx = (LF_encoder_data + RB_encoder_data - LB_encoder_data - RF_encoder_data) / 4;
    location.self_vy = (LF_encoder_data + RB_encoder_data + LB_encoder_data + RF_encoder_data) / 4;
    
    location.vx1 = location.self_vx * sin(imu.gyro.angle[Z] / 180 * M_PI);
    location.vx2 = location.self_vx * cos(imu.gyro.angle[Z] / 180 * M_PI);
    location.vy1 = location.self_vy * cos(imu.gyro.angle[Z] / 180 * M_PI);
    location.vy2 = location.self_vy * sin(imu.gyro.angle[Z] / 180 * M_PI);
    
    location.global_vx = -location.vy2 + location.vx2;
    location.global_vy = location.vy1 + location.vx1;
    
    location.location_x += Location_Control_T * location.global_vx * Encoder_To_Distance_Factor;
    location.location_y += Location_Control_T * location.global_vy * Encoder_To_Distance_Factor;
}

/**
 * @brief ң��������ӳ�䵽�����ٶ�
 * @note  ��ҡ�ˣ����¡�ǰ��(Y)�����ҡ�����(X)
 *        ��ҡ�ˣ����ҡ���ת(Z)
 *        ҡ�˻���/ʧ��ʱ rc_rot_active ���㣬�� pit_handler ���� IMU ����
 */
/*void RC_Control_Update(void)
{
    // ң�������߱�����ǿ��ֹͣƽ�ƣ���ת���� IMU ����
    if (lora3a22_state_flag == 0)
    {
        Car_Speed_X = 0.0f;
        Car_Speed_Y = 0.0f;
        rc_rot_active = 0;
        return;
    }

    // ��ҡ������ (joystick[0])����������(+) �� �������� �� X Ϊ��
    float stick_lr = normalize_stick(lora3a22_uart_transfer.joystick[0]);
    Car_Speed_X = -stick_lr * MAX_LINEAR_SPEED;

    // ��ҡ������ (joystick[1])����������(+) �� ����ǰ�� �� Y Ϊ��
    float stick_fb = normalize_stick(lora3a22_uart_transfer.joystick[1]);
    Car_Speed_Y = stick_fb * MAX_LINEAR_SPEED;

    // ��ҡ������ (joystick[2])����������(+) �� ��ʱ����ת �� Z Ϊ��
    float stick_rot = normalize_stick(lora3a22_uart_transfer.joystick[2]);

    if (fabs(stick_rot) > 0.01f)        // ����ת���룺ֱ������
    {
        Car_Speed_Z   = stick_rot * MAX_Z_SPEED;
        Target_Angle  = -imu.gyro.angle[Z];  // ͬ����ǰ���򣬷�ֹ����ʱ�ǶȻ�ͻ��
        rc_rot_active = 1;
    }
    else                                // ҡ�˻��У����Ϊ����ת����
    {
        rc_rot_active = 0;
    }
}*/

static uint32_t last_cmd_time = 0;
#define POS_TO_SPEED_KP     8.0f

// 航向环平滑参数: 死区挡住微调, 低通压陀螺尖峰, 限幅+斜率限制防止轮子顿挫
#define HEADING_HOLD_DEADBAND_DEG   1.5f
#define HEADING_HOLD_Z_MAX          60.0f
#define HEADING_HOLD_Z_STEP         10.0f
#define HEADING_RATE_ALPHA          0.4f

static float heading_rate_f = 0.0f;   // 低通后的角速度反馈
static float heading_z_last = 0.0f;   // 上一周期输出(斜率限制用)

// 航向闭环: 角度环 -> 角速度环, 返回车头 Z 目标速度
static float Heading_Hold_Z(void)
{
    float err;
    float rate;
    float z;

    err = Target_Angle - imu.gyro.angle[Z];
    while(err > 180.0f) err -= 360.0f;
    while(err < -180.0f) err += 360.0f;
    if(fabsf(err) < HEADING_HOLD_DEADBAND_DEG) err = 0.0f;

    rate = -(GYRO_DATA_Z / GYRO_SPL);
    heading_rate_f += HEADING_RATE_ALPHA * (rate - heading_rate_f);

    pid_control(&angle_cycle, err, 0.0f);
    pid_control(&angular_speed_cycle, angle_cycle.out, heading_rate_f);

    z = angular_speed_cycle.out;
    if(z >  HEADING_HOLD_Z_MAX) z =  HEADING_HOLD_Z_MAX;
    if(z < -HEADING_HOLD_Z_MAX) z = -HEADING_HOLD_Z_MAX;

    if(z > (heading_z_last + HEADING_HOLD_Z_STEP)) z = heading_z_last + HEADING_HOLD_Z_STEP;
    if(z < (heading_z_last - HEADING_HOLD_Z_STEP)) z = heading_z_last - HEADING_HOLD_Z_STEP;

    heading_z_last = z;
    return z;
}

// 航向环切换时清状态, 防止积分/上次误差残留导致输出跳变
static void Heading_Loop_Reset(void)
{
    angle_cycle.i_value      = 0.0f;
    angle_cycle.p_value_last = 0.0f;
    angle_cycle.out          = 0.0f;
    angular_speed_cycle.i_value      = 0.0f;
    angular_speed_cycle.p_value_last = 0.0f;
    angular_speed_cycle.out          = 0.0f;
    heading_rate_f = 0.0f;
    heading_z_last = 0.0f;
}

void pit_handler (void)
{
    uint32 _t_start = DWT_CYCCNT;
    uint32 _e = 0;
    system_time++;

    if((system_time % 5 == 0) && imu_ready)
    {
        get_imu_data();
        imu_data_deal();
        imu_task();
    }

    if(system_time % 20 == 0)
    {
        // IMU校准完成后，统一走麦轮运动学、编码器速度环和航向闭环。
        if(imu_ready && (imu.gyro.zero_calc_flag == 0))
        {
            static uint8 heading_inited = 0;
            if(!heading_inited)
            {
                heading_inited = 1;
                Target_Angle = imu.gyro.angle[Z];
            }
             #if TEST_MODE_DIRECT_DRIVE
             Test_Direct_Drive();
            #else

            if(color_track_enable)
            {
                ColorTrack_UpdateCommand();
            }
            else
            {

            // 航向指令：yaw 从 0 变非 0 时设定新目标
            static int16 yaw_rising_edge = 0;

            if(car_value.new_data_flag)
            {
                car_value.new_data_flag = 0;
                last_cmd_time = system_time;
                car_stop_requested = 0u;
                car_comm_lost = 0u;
                car_stopped_confirmed = 0u;
                car_stopped_count = 0u;

                // 先算出这一帧的平移速度
                float target_vx = (float)car_value.receive_right * POS_TO_SPEED_KP;
                float target_vy = (float)car_value.receive_fwd * POS_TO_SPEED_KP;
                // 偏差非零时保证最低速度，靠近灯也不会蠕动
                #define MIN_SPEED 100.0f
                if(target_vx > 0.0f && target_vx < MIN_SPEED) target_vx = MIN_SPEED;
                if(target_vx < 0.0f && target_vx > -MIN_SPEED) target_vx = -MIN_SPEED;
                if(target_vy > 0.0f && target_vy < MIN_SPEED) target_vy = MIN_SPEED;
                if(target_vy < 0.0f && target_vy > -MIN_SPEED) target_vy = -MIN_SPEED;
                if(target_vx >  MAX_LINEAR_SPEED) target_vx =  MAX_LINEAR_SPEED;
                if(target_vx < -MAX_LINEAR_SPEED) target_vx = -MAX_LINEAR_SPEED;
                if(target_vy >  MAX_LINEAR_SPEED) target_vy =  MAX_LINEAR_SPEED;
                if(target_vy < -MAX_LINEAR_SPEED) target_vy = -MAX_LINEAR_SPEED;

                if(car_value.receive_yaw != 0)
                {
                    if(!yaw_rising_edge)
                    {
                        yaw_rising_edge = 1;
                        Target_Angle = imu.gyro.angle[Z] - (float)car_value.receive_yaw / 100.0f;
                    }
                }
                else
                {
                    yaw_rising_edge = 0;
                }

                // 用角度误差连续混合平移速度，无状态切换
                float yaw_ratio = 1.0f;
                if(yaw_rising_edge)
                {
                    float angle_err = (float)(Target_Angle - imu.gyro.angle[Z]);
                    while(angle_err > 180.0f) angle_err -= 360.0f;
                    while(angle_err < -180.0f) angle_err += 360.0f;
                    yaw_ratio = fabs(angle_err) / 90.0f;
                    if(yaw_ratio > 1.0f) yaw_ratio = 1.0f;
                    yaw_ratio = 1.0f - yaw_ratio;  // 误差大→ratio小, 误差小→ratio接近1
                }
                Car_Speed_X = target_vx * yaw_ratio;
                Car_Speed_Y = target_vy * yaw_ratio;

                if(abs(car_value.receive_fwd) < COMM_ARRIVE_THRESHOLD_FWD &&
                   abs(car_value.receive_right) < COMM_ARRIVE_THRESHOLD_RIGHT)
                {
                    pending_arrive_status = 1;
                    car_stop_requested = 1u;
                }
                else
                {
                    pending_arrive_status = 0;
                }
                // 保存反馈数据，防止被后续帧覆盖
                fb_seq   = car_value.target_seq;
                fb_fwd   = car_value.receive_fwd;
                fb_right = car_value.receive_right;
                need_send_arrive_flag = 1;
            }

            if((system_time - last_cmd_time) > CMD_TIMEOUT_MS)
            {
                Car_Speed_X = 0.0f;
                Car_Speed_Y = 0.0f;
                car_stop_requested = 1u;
                car_comm_lost = 1u;
            }

            // 检查 STOP 标志
            if(car_value.flags & COMM_FLAG_STOP)
            {
                Car_Speed_X = 0.0f;
                Car_Speed_Y = 0.0f;
                car_stop_requested = 1u;
            }
            }
            #endif
            uint32 _t_ctrl = DWT_CYCCNT;

            // ===== 车头 =====
            if(color_track_enable)
            {
                // 视觉要转(丢目标搜索)时车头交给视觉, 其余时间锁航向
                static uint8 ct_vision_turn = 0u;
                if(fabsf(color_track_yaw_cmd) > 0.5f)
                {
                    if(!ct_vision_turn)
                    {
                        ct_vision_turn = 1u;
                        Heading_Loop_Reset();
                    }
                    Car_Speed_Z = color_track_yaw_cmd;
                    Target_Angle = imu.gyro.angle[Z];   // 转圈期间目标跟随, 退出时以此为新车头
                }
                else
                {
                    if(ct_vision_turn)
                    {
                        ct_vision_turn = 0u;
                        Target_Angle = imu.gyro.angle[Z];
                        Heading_Loop_Reset();
                    }
                    Car_Speed_Z = Heading_Hold_Z();
                }
            }
            else
            {
                // 飞控模式: 原航向环
                Car_Speed_Z = Heading_Hold_Z();
            }

            uint32 _t_enc = DWT_CYCCNT;
            Encoder_Get_Speed();
            _e = PROFILE_US(_t_enc);
            if(_e > profile_enc_max) profile_enc_max = _e;

            // 编码器4轮正解 → 车体实际速度 cm/s（仅回传，不影响控制）
            car_actual_vx = ((float)LF_encoder_data + (float)RB_encoder_data -
                             (float)LB_encoder_data - (float)RF_encoder_data) *
                            0.25f * ENCODER_COUNT_TO_CM / Location_Control_T;
            car_actual_vy = ((float)LF_encoder_data + (float)RB_encoder_data +
                             (float)LB_encoder_data + (float)RF_encoder_data) *
                            0.25f * ENCODER_COUNT_TO_CM / Location_Control_T;

            // 停止确认：连续 N 帧合速度<阈值才确认已停稳
            if((car_stop_requested != 0u) &&
               (fabsf(car_actual_vx) <= CAR_STOP_SPEED_THRESHOLD_CM_S) &&
               (fabsf(car_actual_vy) <= CAR_STOP_SPEED_THRESHOLD_CM_S))
            {
                if(car_stopped_count < CAR_STOP_CONFIRM_COUNT)
                    car_stopped_count++;
                if(car_stopped_count >= CAR_STOP_CONFIRM_COUNT)
                    car_stopped_confirmed = 1u;
            }
            else
            {
                car_stopped_count = 0u;
                car_stopped_confirmed = 0u;
            }

            _t_enc = DWT_CYCCNT;
            Set_Car_Speed(Car_Speed_X,Car_Speed_Y,Car_Speed_Z);

            pid_control_incremental(&RB_speed_cycle,RB_Target_Speed,RB_encoder_data);
            pid_control_incremental(&RF_speed_cycle,RF_Target_Speed,RF_encoder_data);
            pid_control_incremental(&LF_speed_cycle,LF_Target_Speed,LF_encoder_data);
            pid_control_incremental(&LB_speed_cycle,LB_Target_Speed,LB_encoder_data);

            Motor(Right_back_Motor,RB_speed_cycle.out);
            Motor(Right_front_Motor,RF_speed_cycle.out);
            Motor(Left_front_Motor,LF_speed_cycle.out);
            Motor(Left_back_Motor,LB_speed_cycle.out);
            _e = PROFILE_US(_t_enc);
            if(_e > profile_pid_max) profile_pid_max = _e;

            _e = PROFILE_US(_t_ctrl);
            if(_e > profile_ctrl_max) profile_ctrl_max = _e;
        }

    }
   _e = PROFILE_US(_t_start);
   if(_e > profile_total_max) profile_total_max = _e;

   if(system_time % 1000 == 0)
    {
        BAT_Get_Loop();
    }
}
