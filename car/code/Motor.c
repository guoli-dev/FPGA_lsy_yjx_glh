/*#include "zf_common_headfile.h"

void Motor_Init(void)
{
    gpio_init(DIR_RF, GPO, GPIO_HIGH, GPO_PUSH_PULL);             // GPIO 初始化为输出 默认上拉输出高
    pwm_init(PWM_RF, 17000, 0);                                      // PWM 通道初始化频率 17KHz 占空比初始为 0
    gpio_init(DIR_LF, GPO, GPIO_HIGH, GPO_PUSH_PULL);             // GPIO 初始化为输出 默认上拉输出高
    pwm_init(PWM_LF, 17000, 0);                                      // PWM 通道初始化频率 17KHz 占空比初始为 0

    gpio_init(DIR_RB, GPO, GPIO_HIGH, GPO_PUSH_PULL);             // GPIO 初始化为输出 默认上拉输出高
    pwm_init(PWM_RB, 17000, 0);                                     // PWM 通道初始化频率 17KHz 占空比初始为 0
    gpio_init(DIR_LB, GPO, GPIO_HIGH, GPO_PUSH_PULL);               // GPIO 初始化为输出 默认上拉输出高
    pwm_init(PWM_LB, 17000, 0);                                      // PWM 通道初始化频率 17KHz 占空比初始为 0
}

void Motor(uint8_t Motor,int32 duty)
{
    if(Motor==Left_front_Motor)
    {
        if(duty>=0)
        {
            gpio_set_level(DIR_LF, GPIO_HIGH);
            pwm_set_duty(PWM_LF, duty);
        }
        else
        {
            gpio_set_level(DIR_LF, GPIO_LOW);
            pwm_set_duty(PWM_LF, -duty);
        }
    }
    else if(Motor==Right_front_Motor)
    {
        if(duty>=0)
        {
            gpio_set_level(DIR_RF, GPIO_HIGH);
            pwm_set_duty(PWM_RF, duty);
        }
        else
        {
            gpio_set_level(DIR_RF, GPIO_LOW);
            pwm_set_duty(PWM_RF, -duty);
        }
    }
    else if(Motor==Left_back_Motor)
    {
        if(duty>=0)
        {
            gpio_set_level(DIR_LB, GPIO_HIGH);
            pwm_set_duty(PWM_LB, duty);
        }
        else
        {
            gpio_set_level(DIR_LB, GPIO_LOW);
            pwm_set_duty(PWM_LB, -duty);
        }
    }
    else if(Motor==Right_back_Motor)
    {
        if(duty>=0)
        {
            gpio_set_level(DIR_RB, GPIO_HIGH);
            pwm_set_duty(PWM_RB, duty);
        }
        else
        {
            gpio_set_level(DIR_RB, GPIO_LOW);
            pwm_set_duty(PWM_RB, -duty);
        }
    }
}*/
#include "zf_common_headfile.h"

void Motor_Init(void)
{
    gpio_init(MOTOR_RF_DIR, GPO, GPIO_HIGH, GPO_PUSH_PULL);         // GPIO 初始化为输出 默认上拉输出高
    pwm_init(MOTOR_RF_PWM, 17000, 0);                                 // PWM 通道初始化频率 17KHz 占空比初始为 0

    gpio_init(MOTOR_LF_DIR, GPO, GPIO_HIGH, GPO_PUSH_PULL);         // GPIO 初始化为输出 默认上拉输出高
    pwm_init(MOTOR_LF_PWM, 17000, 0);                                 // PWM 通道初始化频率 17KHz 占空比初始为 0

    gpio_init(MOTOR_RB_DIR, GPO, GPIO_HIGH, GPO_PUSH_PULL);         // GPIO 初始化为输出 默认上拉输出高
    pwm_init(MOTOR_RB_PWM, 17000, 0);                                 // PWM 通道初始化频率 17KHz 占空比初始为 0

    gpio_init(MOTOR_LB_DIR, GPO, GPIO_HIGH, GPO_PUSH_PULL);         // GPIO 初始化为输出 默认上拉输出高
    pwm_init(MOTOR_LB_PWM, 17000, 0);                                 // PWM 通道初始化频率 17KHz 占空比初始为 0
}

void Motor(uint8_t Motor, int32 duty)
{
    if(Motor == Left_front_Motor)
    {
        if(duty >= 0)
        {
            gpio_set_level(MOTOR_LF_DIR, GPIO_LOW);
            pwm_set_duty(MOTOR_LF_PWM, duty);
        }
        else
        {
            gpio_set_level(MOTOR_LF_DIR, GPIO_HIGH);
            pwm_set_duty(MOTOR_LF_PWM, -duty);
        }
    }
    else if(Motor == Right_front_Motor)
    {
        if(duty >= 0)
        {
            gpio_set_level(MOTOR_RF_DIR, GPIO_LOW);
            pwm_set_duty(MOTOR_RF_PWM, duty);
        }
        else
        {
            gpio_set_level(MOTOR_RF_DIR, GPIO_HIGH);
            pwm_set_duty(MOTOR_RF_PWM, -duty);
        }
    }
    else if(Motor == Left_back_Motor)
    {
        if(duty >= 0)
        {
            gpio_set_level(MOTOR_LB_DIR, GPIO_LOW);
            pwm_set_duty(MOTOR_LB_PWM, duty);
        }
        else
        {
            gpio_set_level(MOTOR_LB_DIR, GPIO_HIGH);
            pwm_set_duty(MOTOR_LB_PWM, -duty);
        }
    }
    else if(Motor == Right_back_Motor)
    {
        if(duty >= 0)
        {
            gpio_set_level(MOTOR_RB_DIR, GPIO_HIGH);
            pwm_set_duty(MOTOR_RB_PWM, duty);
        }
        else
        {
            gpio_set_level(MOTOR_RB_DIR, GPIO_LOW);
            pwm_set_duty(MOTOR_RB_PWM, -duty);
        }
    }
}

