/*
 * Pid.h
 *
 *  Created on: 2025年12月10日
 *      Author: lenovo
 */

#ifndef CODE_PID_H_
#define CODE_PID_H_

#include "zf_common_typedef.h"

typedef struct
{
    float p;
    float i;
    float d;
    float out;//pid输出值
    float out_max;//输出限幅
    float p_value_last;//上一次比例量（位置pid用的）
    float i_value;//积分累加值
    float i_value_pro;//积分累积速率系数（位置式pid）
    float incremental_data[2];//增量式PID用，存上次、上上次误差
    float i_value_max;// 积分限幅
    float count;//现在还没有用  (QAQ)
}pid_cycle_struct;

extern pid_cycle_struct RB_speed_cycle;
extern pid_cycle_struct RF_speed_cycle;
extern pid_cycle_struct LB_speed_cycle;
extern pid_cycle_struct LF_speed_cycle;
extern pid_cycle_struct angular_speed_cycle;
extern pid_cycle_struct angle_cycle;
extern pid_cycle_struct position_x_cycle;
extern pid_cycle_struct position_y_cycle;
void pid_control(pid_cycle_struct *pid_cycle,float target,float real);
void pid_control_incremental(pid_cycle_struct *pid_cycle,float target,float real);
void Pid_Init(void);

#endif /* CODE_PID_H_ */
