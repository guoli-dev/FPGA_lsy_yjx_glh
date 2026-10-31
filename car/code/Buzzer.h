#ifndef CODE_BUZZER_H_
#define CODE_BUZZER_H_

#define BUZZER_PIN              (P19_4)                                         // 定义主板蜂鸣器引脚

void Buzzer_Init(void);
void Buzzer_Open(void);
void Buzzer_Close(void);

#endif