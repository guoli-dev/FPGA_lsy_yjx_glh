/*#ifndef CODE_MOTOR_H_
#define CODE_MOTOR_H_

#define MAX_DUTY            (50 )                                               // 最大 MAX_DUTY% 占空比
#define DIR_LF              (P05_1)
#define PWM_LF              (TCPWM_CH09_P05_0)
#define DIR_RF              (P05_3)
#define PWM_RF              (TCPWM_CH11_P05_2)

#define DIR_LB              (P10_3)
#define PWM_LB              (TCPWM_CH30_P10_2)
#define DIR_RB              (P09_1)
#define PWM_RB              (TCPWM_CH24_P09_0)

enum Motor{
    Right_front_Motor=1,
    Left_front_Motor,
    Left_back_Motor,
    Right_back_Motor
};

void Motor_Init(void);
void Motor(uint8_t Motor,int32 duty);

#endif */
#ifndef CODE_MOTOR_H_
#define CODE_MOTOR_H_

#define MAX_DUTY            (50 )            // 最大 MAX_DUTY% 占空比

#define MOTOR_RF_PWM        (TCPWM_CH30_P10_2)
#define MOTOR_RF_DIR        (P10_3)
#define MOTOR_LF_PWM        (TCPWM_CH24_P09_0)
#define MOTOR_LF_DIR        (P09_1)
#define MOTOR_LB_PWM        (TCPWM_CH11_P05_2)
#define MOTOR_LB_DIR        (P05_3)
#define MOTOR_RB_PWM        (TCPWM_CH09_P05_0)
#define MOTOR_RB_DIR        (P05_1)

enum Motor{
    Right_front_Motor=1,
    Left_front_Motor,
    Left_back_Motor,
    Right_back_Motor
};

void Motor_Init(void);
void Motor(uint8_t Motor,int32 duty);

#endif /* CODE_MOTOR_H_ */