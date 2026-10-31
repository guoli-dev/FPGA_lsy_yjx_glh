#include "zf_common_headfile.h"

uint16 valtage_adc = 0;
float valtage = 0;

void BAT_Get_Init(void)
{
    adc_init(VOLTAGE_PORT, ADC_12BIT);
}

void BAT_Get_Loop(void)
{
    valtage_adc = adc_convert(VOLTAGE_PORT);
    valtage = 36.3 * valtage_adc / 4096;
    if(valtage<11.4&&valtage>5.0)
    {
        Buzzer_Open();
    }
    else
    {
        Buzzer_Close();
    }
}