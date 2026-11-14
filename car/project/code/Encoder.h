/*
 * Encoder.h
 *
 *  Created on: 2025年12月16日
 *      Author: lenovo
 */

/*#ifndef CODE_ENCODER_H_
#define CODE_ENCODER_H_

#define ENCODER_1                   (TC_CH58_ENCODER)
#define ENCODER_1_A                 (TC_CH58_ENCODER_CH1_P17_3)
#define ENCODER_1_B                 (TC_CH58_ENCODER_CH2_P17_4)

#define ENCODER_2                   (TC_CH27_ENCODER)
#define ENCODER_2_A                 (TC_CH27_ENCODER_CH1_P19_2)
#define ENCODER_2_B                 (TC_CH27_ENCODER_CH2_P19_3)

#define ENCODER_3                   (TC_CH07_ENCODER)
#define ENCODER_3_A                 (TC_CH07_ENCODER_CH1_P07_6)
#define ENCODER_3_B                 (TC_CH07_ENCODER_CH2_P07_7)

#define ENCODER_4                   (TC_CH20_ENCODER)
#define ENCODER_4_A                 (TC_CH20_ENCODER_CH1_P08_1)
#define ENCODER_4_B                 (TC_CH20_ENCODER_CH2_P08_2)

extern int16 LB_encoder_data;
extern int16 RB_encoder_data;
extern int16 RF_encoder_data;
extern int16 LF_encoder_data;

void Encoder_Init(void);
void Encoder_Get_Speed(void);

#endif /* CODE_ENCODER_H_ */
#ifndef CODE_ENCODER_H_
#define CODE_ENCODER_H_

/*#define ENCODER_1                   (TC_CH58_ENCODER)
#define ENCODER_1_PULSE             (TC_CH58_ENCODER_CH1_P17_3)
#define ENCODER_1_DIR               (TC_CH58_ENCODER_CH2_P17_4)
#define ENCODER_2                   (TC_CH27_ENCODER)
#define ENCODER_2_PULSE             (TC_CH27_ENCODER_CH1_P19_2)
#define ENCODER_2_DIR               (TC_CH27_ENCODER_CH2_P19_3)
#define ENCODER_3                   (TC_CH07_ENCODER)
#define ENCODER_3_PULSE             (TC_CH07_ENCODER_CH1_P07_6)
#define ENCODER_3_DIR               (TC_CH07_ENCODER_CH2_P07_7)
#define ENCODER_4                   (TC_CH20_ENCODER)
#define ENCODER_4_PULSE             (TC_CH20_ENCODER_CH1_P08_1)
#define ENCODER_4_DIR               (TC_CH20_ENCODER_CH2_P08_2)
*/
// ========== 右前轮 ==========
#define ENCODER_3                      TC_CH58_ENCODER
#define ENCODER_3_PULSE                TC_CH58_ENCODER_CH1_P17_3   // A相（小引脚）
#define ENCODER_3_DIR                  TC_CH58_ENCODER_CH2_P17_4   // Dir（大引脚）

// ========== 左前轮 ==========
#define ENCODER_4                      TC_CH27_ENCODER
#define ENCODER_4_PULSE                TC_CH27_ENCODER_CH1_P19_2
#define ENCODER_4_DIR                  TC_CH27_ENCODER_CH2_P19_3

// ========== 左后轮 ==========
#define ENCODER_1                      TC_CH07_ENCODER
#define ENCODER_1_PULSE                TC_CH07_ENCODER_CH1_P07_6
#define ENCODER_1_DIR                  TC_CH07_ENCODER_CH2_P07_7

// ========== 右后轮 ==========
#define ENCODER_2                      TC_CH20_ENCODER
#define ENCODER_2_PULSE                TC_CH20_ENCODER_CH1_P08_1
#define ENCODER_2_DIR                  TC_CH20_ENCODER_CH2_P08_2

extern int16 LB_encoder_data;
extern int16 RB_encoder_data;
extern int16 RF_encoder_data;
extern int16 LF_encoder_data;

void Encoder_Init(void);
void Encoder_Get_Speed(void);

#endif /* CODE_ENCODER_H_ */