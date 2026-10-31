#include "zf_common_headfile.h"

float limit_float(float value, float min_val, float max_val)
{
    if(value < min_val) return min_val;
    if(value > max_val) return max_val;
    return value;
}

// ==================== 摇杆归一化 ====================
float normalize_stick(int16_t raw)
{
    if (abs(raw) < DEAD_ZONE) return 0.0f;
    float sign = (raw > 0) ? 1.0f : -1.0f;
    float val = (abs(raw) - DEAD_ZONE) / (2048.0f - DEAD_ZONE);
    return sign * limit_float(val, 0.0f, 1.0f);
}

