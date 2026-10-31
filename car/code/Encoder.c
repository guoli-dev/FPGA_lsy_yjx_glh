/*
 * Encoder.c
 *
 *  Created on: 2025年12月16日
 *      Author: lenovo
 */

/*#include "zf_common_headfile.h"

int16 LB_encoder_data = 0;
int16 RB_encoder_data = 0;
int16 RF_encoder_data = 0;
int16 LF_encoder_data = 0;
int16 LB_encoder_data_Save = 0;
int16 RB_encoder_data_Save = 0;
int16 RF_encoder_data_Save = 0;
int16 LF_encoder_data_Save = 0;

void Encoder_Init(void)
{
    encoder_quad_init(ENCODER_1, ENCODER_1_A, ENCODER_1_B);                     // 初始化编码器模块与引脚 正交解码编码器模式
    encoder_quad_init(ENCODER_2, ENCODER_2_A, ENCODER_2_B);                     // 初始化编码器模块与引脚 正交解码编码器模式
    encoder_quad_init(ENCODER_3, ENCODER_3_A, ENCODER_3_B);                     // 初始化编码器模块与引脚 正交解码编码器模式
    encoder_quad_init(ENCODER_4, ENCODER_4_A, ENCODER_4_B);                     // 初始化编码器模块与引脚 正交解码编码器模式
}

void Encoder_Get_Speed(void)
{
    LB_encoder_data = -encoder_get_count(ENCODER_1);
    encoder_clear_count(ENCODER_1);
    
    RB_encoder_data = encoder_get_count(ENCODER_2);
    encoder_clear_count(ENCODER_2);
    
    RF_encoder_data = encoder_get_count(ENCODER_3);
    encoder_clear_count(ENCODER_3);
    
    LF_encoder_data = -encoder_get_count(ENCODER_4);
    encoder_clear_count(ENCODER_4);
}
*/
#include "zf_common_headfile.h"

int16 LB_encoder_data = 0;
int16 RB_encoder_data = 0;
int16 RF_encoder_data = 0;
int16 LF_encoder_data = 0;

void Encoder_Init(void)
{
    encoder_dir_init(ENCODER_1, ENCODER_1_PULSE, ENCODER_1_DIR);
    encoder_dir_init(ENCODER_2, ENCODER_2_PULSE, ENCODER_2_DIR);
    encoder_dir_init(ENCODER_3, ENCODER_3_PULSE, ENCODER_3_DIR);
    encoder_dir_init(ENCODER_4, ENCODER_4_PULSE, ENCODER_4_DIR);
    
    // 初始化完成后立刻冲刷一次,清除上电瞬间可能积累的噪声计数
    encoder_clear_count(ENCODER_1);
    encoder_clear_count(ENCODER_2);
    encoder_clear_count(ENCODER_3);
    encoder_clear_count(ENCODER_4);
}

void Encoder_Get_Speed(void)
{
    LB_encoder_data = -encoder_get_count(ENCODER_1);
    encoder_clear_count(ENCODER_1);

    RB_encoder_data = encoder_get_count(ENCODER_2);
    encoder_clear_count(ENCODER_2);

    RF_encoder_data = encoder_get_count(ENCODER_3);
    encoder_clear_count(ENCODER_3);

    LF_encoder_data = -encoder_get_count(ENCODER_4);
    encoder_clear_count(ENCODER_4);
    
    //printf("LF:%d,RF:%d,LB:%d,RB:%d\r\n",
           //LF_encoder_data, RF_encoder_data, LB_encoder_data, RB_encoder_data);
}