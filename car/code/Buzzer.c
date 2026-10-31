#include "zf_common_headfile.h"

void Buzzer_Init(void)
{
    gpio_init(BUZZER_PIN, GPO, GPIO_LOW, GPO_PUSH_PULL);                        // 初始化 BUZZER_PIN 输出 默认低电平 推挽输出模式
}

void Buzzer_Open(void)
{
    gpio_set_level(BUZZER_PIN, GPIO_HIGH);
}

void Buzzer_Close(void)
{
    gpio_set_level(BUZZER_PIN, GPIO_LOW);
}