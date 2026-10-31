/*
 * Pid.c
 *
 *  Created on: 2025��12��10��
 *      Author: lenovo
 */

#include "zf_common_headfile.h"

pid_cycle_struct RB_speed_cycle;
pid_cycle_struct RF_speed_cycle;
pid_cycle_struct LB_speed_cycle;
pid_cycle_struct LF_speed_cycle;
pid_cycle_struct angular_speed_cycle;
pid_cycle_struct angle_cycle;
pid_cycle_struct position_x_cycle;
pid_cycle_struct position_y_cycle;
//float tt1=0;

//-----
//�������      PID�ջ�����(λ��ʽ)
//����˵��      pid_cycle               PID�����ṹ��
//����˵��      target                  Ŀ��ֵ
//����˵��      real                    ��ǰֵ
//���ز���      void
//ʹ��ʾ��      pid_control(&balance cascade speed cycle,��,(left_motor.encoder_data+right_motor.encoder_data)/2);
//��ע��Ϣ
//
void pid_control(pid_cycle_struct *pid_cycle,float target,float real)
{
    float   proportion_value=0;     //������

    float   differential_value=0;   //΢����

    float p1=0;

    proportion_value =target -real; //������=Ŀ��ֵ-ʵ��ֵ

    pid_cycle->i_value +=(proportion_value *pid_cycle->i_value_pro); //������=������+������*���̶ֳ�

    pid_cycle->i_value =func_limit_ab(pid_cycle->i_value,-pid_cycle->i_value_max,pid_cycle->i_value_max);//�������޷�

    differential_value =proportion_value -pid_cycle->p_value_last;      //΢����=������-��һ�α�����

    pid_cycle->out =(int16)(pid_cycle->p*proportion_value +pid_cycle->i*pid_cycle->i_value +pid_cycle->d*differential_value);
    
    pid_cycle->out =func_limit_ab(pid_cycle->out,-pid_cycle->out_max,pid_cycle->out_max);   //PID����޷�

    pid_cycle->p_value_last =proportion_value;  //���������
}
//
//�������      PID�ջ�����(����ʽ)
//����˵��      pid_cycle           PID�����ṹ��
//����˵��      target              Ŀ��ֵ
//����˵��      real                ��ǰֵ
//���ز���      void
//ʹ��ʾ��      pid_control_incremental��&balancecascade.speed cycle,0,��left_motor.encoder_data+right_motor.encoder_data)/ 2);
//��ע��Ϣ
void pid_control_incremental(pid_cycle_struct *pid_cycle, float target, float real)
{
    // 1. ���㵱ǰ���
    float error = target - real;

    // 2. �����������������ǰ��� - �ϴ����
    float proportion_value = error - pid_cycle->incremental_data[0];

    // 3. �����ʹ�õ�ǰ���
    pid_cycle->i_value = error;

    // 4. ΢�����ǰ��� - 2*�ϴ���� + ���ϴ����
    float differential_value = error - 2*pid_cycle->incremental_data[0] + pid_cycle->incremental_data[1];

    // 5. ������ʷ���
    pid_cycle->incremental_data[1] = pid_cycle->incremental_data[0];
    pid_cycle->incremental_data[0] = error;

    // 6. �����������
    float increment = pid_cycle->p * proportion_value +
                     pid_cycle->i * pid_cycle->i_value +
                     pid_cycle->d * differential_value;

    // 7. �ۼӵ������
    pid_cycle->out += increment;
//    printf("%f\r\n",pid_cycle->out);

    // 8. ����޷�
    pid_cycle->out = func_limit_ab(pid_cycle->out, -pid_cycle->out_max, pid_cycle->out_max);
}

void Pid_Init(void)
{
    RB_speed_cycle.p=10.0f;
    RB_speed_cycle.i=0.8f;
    RB_speed_cycle.d=0.2f;
    RB_speed_cycle.out_max=5000.0f;
    
    RF_speed_cycle.p=10.0f;
    RF_speed_cycle.i=0.8f;
    RF_speed_cycle.d=0.2f;
    RF_speed_cycle.out_max=5000.0f;
    
    LF_speed_cycle.p=10.0f;
    LF_speed_cycle.i=0.8f;
    LF_speed_cycle.d=0.2f;
    LF_speed_cycle.out_max=5000.0f;
    
    LB_speed_cycle.p=10.0f;
    LB_speed_cycle.i=0.8f;
    LB_speed_cycle.d=0.2f;
    LB_speed_cycle.out_max=5000.0f;
    
    angular_speed_cycle.p=1.8f;
    angular_speed_cycle.i=1.0f;
    angular_speed_cycle.d=0.0f;
    angular_speed_cycle.i_value_pro=0.00f;
    angular_speed_cycle.i_value_max=50.0f;
    angular_speed_cycle.out_max=5000.0f;
    
    angle_cycle.p=10.6f;
    angle_cycle.i=0.0f;
    angle_cycle.d=0.0f;
    angle_cycle.i_value_pro=0.01f;
    angle_cycle.i_value_max=50.0f;
    angle_cycle.out_max=5000.0f;
}
