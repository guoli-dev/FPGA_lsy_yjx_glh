/*
float R=30.0f;
float Angular_Speed=3.5f;
float current_angle = 0.0f;
current_angle += Angular_Speed * 0.02;
if (current_angle >= 2.0f * M_PI) 
{ 
    current_angle -= 2.0f * M_PI;
}
pid_control(&angle_cycle,Target_Angle,-imu.gyro.angle[Z]);//�ǶȻ�
pid_control(&angular_speed_cycle,angle_cycle.out,-(GYRO_DATA_Z / GYRO_SPL));//���ٶȻ�
Car_Speed_X=-R*Angular_Speed*sin(current_angle);
Car_Speed_Y=R*Angular_Speed*cos(current_angle);
Car_Speed_Z=angular_speed_cycle.out;
Set_Car_Speed(Car_Speed_X,Car_Speed_Y,Car_Speed_Z);
Բ*/

#ifndef CODE_CONTROL_H_
#define CODE_CONTROL_H_

#define M_PI 3.1415926f
#define Encoder_To_Distance_Factor 0.486f
#define Location_Control_T 0.02f

#define MAX_LINEAR_SPEED    80.0f   // ��ģ������ٶ� cm/s������ʵ�ʵ�
//#define POS_TO_SPEED_KP     3.0f    // ����/����ƫ��ת�ٶȵı���ϵ������Ҫ����
#define CMD_TIMEOUT_MS         200
typedef struct
{
    float self_vx;
    float self_vy;
    float vx1;
    float vy1;
    float vx2;
    float vy2;
    float global_vx;
    float global_vy;
    float location_x;
    float location_y;
    float Target_Location_X;
    float Target_Location_Y;
    float Last_Target_Location_X;
    float Last_Target_Location_Y;
    float Target_Location_Angle;
    float dx;
    float dy;
    float distance;
    float desired_speed;
    uint8 Control_State;
    int16 Speed;
    int16 max_speed;
    int16 min_speed;
}location_struct;

extern int16 Target_Speed;
extern float Target_Angle;
extern float Car_Speed_X;
extern float Car_Speed_Y;
extern float Car_Speed_Z;
extern int16_t LF_Target_Speed;
extern int16_t LB_Target_Speed;
extern int16_t RF_Target_Speed;
extern int16_t RB_Target_Speed;
extern location_struct location;
extern float POS_TO_SPEED_KP;

extern volatile uint8 need_send_arrive_flag;
extern volatile uint8 pending_arrive_status;
extern volatile uint8  fb_seq;
extern volatile int16  fb_fwd;
extern volatile int16  fb_right;

// ===== 速度反馈 & 停止确认（仅用于回传，不影响控制） =====
#define ENCODER_COUNT_TO_CM         0.486f   // 直线推车100cm标定得
#define CAR_STOP_SPEED_THRESHOLD_CM_S 3.0f
#define CAR_STOP_CONFIRM_COUNT        5u

extern volatile uint8  car_stop_requested;
extern volatile uint8  car_comm_lost;
extern volatile uint8  car_stopped_confirmed;
extern volatile uint8  car_stopped_count;
extern volatile float  car_actual_vx;
extern volatile float  car_actual_vy;

void pit_handler (void);
void profile_dwt_init(void);

extern volatile uint32 profile_total_max;
extern volatile uint32 profile_imu_max;
extern volatile uint32 profile_task_max;
extern volatile uint32 profile_ctrl_max;
extern volatile uint32 profile_enc_max;
extern volatile uint32 profile_pid_max;

#endif /* CODE_CONTROL_H_ */
