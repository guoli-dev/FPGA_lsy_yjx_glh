#ifndef CODE_RC_H_
#define CODE_RC_H_


// ==================== 配置参数 ====================
#define DEAD_ZONE               100         // 摇杆死区
#define MAX_LINEAR_SPEED        600.0f      // 前后/左右最大平移速度（根据实际电机响应调整）
#define MAX_Z_SPEED             400.0f      // 最大旋转速度

float normalize_stick(int16_t raw);

#endif