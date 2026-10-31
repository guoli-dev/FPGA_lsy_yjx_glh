#ifndef CODE_BAT_H_
#define CODE_BAT_H_

#define VOLTAGE_PORT    ADC0_CH21_P07_5 // 定义检测端口

void BAT_Get_Init(void);
void BAT_Get_Loop(void);

extern uint16 valtage_adc;
extern float valtage;

#endif