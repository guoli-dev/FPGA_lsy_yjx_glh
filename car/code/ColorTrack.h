#ifndef CODE_COLOR_TRACK_H_
#define CODE_COLOR_TRACK_H_

#include "zf_common_headfile.h"

/*
 * 色块追踪（FPGA/无线 -> 小车，接收口见下方 COLOR_TRACK_RX_PORT）
 *
 * 协议: 每帧 7 字节, 60Hz
 *   AA | 红dev | 红宽 | 绿dev | 绿宽 | 蓝dev | 蓝宽
 *   dev 有符号: 0x80=无目标, 0x00=正中, 0x01~0x4F 偏右, 0xB0~0xFF 偏左
 *   wid 宽度:   0 ~ 159
 * 0xAA 不会出现在 6 个数据字节里(dev 的合法值域跳过了 0xAA, wid<=0x9F),
 * 所以不需要校验和/帧尾, 只靠 0xAA 对齐即可。
 */

// ======================= 接收串口 =======================
// 无线/FPGA 接收口: 1=UART_1(P04_0/P04_1)  2=UART_2(P10_0/P10_1)  5=UART_5(P02_0/P02_1)
// 注意: UART_5 与 SPI0 共用 P02_0/P02_1, 不能同时启用 WiFi-SPI
#define COLOR_TRACK_RX_PORT     5

#if (COLOR_TRACK_RX_PORT == 1)
  #define COLOR_TRACK_RX_UART       UART_1
  #define COLOR_TRACK_RX_TX_PIN     UART1_TX_P04_1
  #define COLOR_TRACK_RX_RX_PIN     UART1_RX_P04_0
#elif (COLOR_TRACK_RX_PORT == 2)
  #define COLOR_TRACK_RX_UART       UART_2
  #define COLOR_TRACK_RX_TX_PIN     UART2_TX_P10_1
  #define COLOR_TRACK_RX_RX_PIN     UART2_RX_P10_0
#elif (COLOR_TRACK_RX_PORT == 5)
  #define COLOR_TRACK_RX_UART       UART_5
  #define COLOR_TRACK_RX_TX_PIN     UART5_TX_P02_1
  #define COLOR_TRACK_RX_RX_PIN     UART5_RX_P02_0
#endif

// ======================= 可调参数 =======================
#define COLOR_TRACK_USE_MASK        0x07u // 参与选择的颜色: bit0红 bit1绿 bit2蓝
#define COLOR_TRACK_SWITCH_MARGIN   5u    // 换目标滞回: 另一色宽 > 当前锁定宽+此值才切换
#define COLOR_TRACK_LOCK_LOST_FRAMES 5u   // 锁定色连续丢这么多帧才放弃(约83ms@60Hz)
#define COLOR_TRACK_DEV_INVERT  0     // dev 符号取反: 1=摄像头画面左右镜像时用; 0=正常(默认)
#define COLOR_TRACK_DEADBAND    4     // 偏差死区(像素*8), 挡住抖动
#define COLOR_TRACK_NEAR_W      30    // [旧] 距离三段阈值, 现已不用
#define COLOR_TRACK_FAR_W       10    // [旧]
#define COLOR_TRACK_LATERAL_ON          1     // 1=转向+横移同时; 0=只靠车头转向对准
#define COLOR_TRACK_LATERAL_KP          2.0f  // dev -> 横移速度
#define COLOR_TRACK_MAX_LATERAL_SPEED  40.0f  // 横移速度上限

// 追到判定: 宽度达到它就算"到达", 停车并锁存; 宽度回落到 到达值-回差 以下才解除
#define COLOR_TRACK_ARRIVE_W            85.0f // 到达宽度(略小于 DIST_W)
#define COLOR_TRACK_ARRIVE_HYST         12.0f // 解除回差: 宽度要掉到 73 以下才重新追

// 丢目标后的旋转搜索: 看得见只平移, 看不见才转圈找, 转满一圈停
// 注意: 本车混控里 Car_Speed_Z>0 = 左轮进/右轮退 = 顺时针 = 右转
#define COLOR_TRACK_SEARCH_ENABLE       1     // 1=丢目标后旋转寻找; 0=丢目标就停
#define COLOR_TRACK_LOST_MS             300u  // 连续看不到多久才开始找
#define COLOR_TRACK_SEARCH_SPIN         32.0f // 搜索时的旋转速度(Car_Speed_Z)
#define COLOR_TRACK_SEARCH_MAX_DEG      360.0f// 转满这么多度还没找到就停下
#define COLOR_TRACK_SEARCH_SIGN         1     // 搜索转向反了就改 -1

// 丢过目标后重新看到: 先靠横移把色块拉回中央再追, 不转车头(避免转过头)
// 偏离中心越大, 前进速度越小; |dev| 超过 END 时完全停止前进, 只横移居中
#define COLOR_TRACK_FWD_GATE_START     28.0f  // |dev| 超过它开始减少前进
#define COLOR_TRACK_FWD_GATE_END       55.0f  // |dev| 到这里前进=0(先横移居中)

// 前后: 用"宽度误差"连续控制(不再是三段阶跃), 更平顺
// 注意: FPGA 宽度量程 0~159, 越近越大. COLOR_TRACK_DIST_W = 想停下来的宽度
#define COLOR_TRACK_DIST_W              90.0f // 期望宽度(停车距离); 实测远处约57, 所以设大
#define COLOR_TRACK_DIST_KP             1.0f  // 近处: 宽度误差 -> 前后速度(决定收敛精度)
#define COLOR_TRACK_DIST_DEADBAND_W     3.0f  // 宽度死区
#define COLOR_TRACK_FAR_BOOST_START     20.0f // 误差超过它才额外加速(只提速远处, 近处不变)
#define COLOR_TRACK_FAR_BOOST_KP        1.2f  // 远处额外加速斜率
#define COLOR_TRACK_MAX_FWD             70.0f // 最大前进速度
#define COLOR_TRACK_MAX_BACK            0.0f  // 最大后退速度; 0=太近只停不后退

// 平滑: 一阶低通 + 命令斜率限制, 消除卡顿/硬起停
#define COLOR_TRACK_DEV_ALPHA           0.30f // dev 低通系数(0~1, 越小越平滑)
#define COLOR_TRACK_WID_ALPHA           0.30f // 宽度低通系数
#define COLOR_TRACK_ACCEL_STEP          5.0f  // 每20ms横移/前后命令最大变化量
#define COLOR_TRACK_Z_STEP              10.0f // 每20ms车头修正量最大变化量(抑制左右抖)
#define COLOR_TRACK_BASE_SPEED         35.0f  // [旧]
#define COLOR_TRACK_FAR_SPEED          50.0f  // [旧]

#define COLOR_TRACK_ENABLE      1     // 无线串口/FPGA 帧驱动；断帧 200ms 自动停车

// ======================= 自测 =======================
#define COLOR_TRACK_LOOPBACK_TEST  0   // 1=每500ms从UART_1发一帧测试帧(P04_1和P04_0短接时RX/F应持续增长)

// ======================= 按键选色 =======================
#define COLOR_TRACK_USE_KEY        1     // 1=启用按键选色; 0=完全禁用(排查串口问题时用)
#define COLOR_TRACK_KEY            KEY_1  // 板载按键(KEY_1~KEY_4): 每按一次循环切换目标色
#define COLOR_TRACK_KEY_SCAN_MS    10u    // 按键扫描周期(ms)

// ======================= 对外接口 =======================
extern volatile uint8 color_track_enable;   // 1=视觉麦轮追踪; 0=只解析/监视
extern volatile int8  color_track_dev;      // 调试用: 最近一帧目标色块偏差
extern volatile uint8 color_track_wid;      // 调试用: 最近一帧目标色块宽度
extern volatile uint8 color_track_found;    // 调试用: 最近一帧是否看到目标(1/0)
extern volatile uint8 color_track_locked;   // 当前锁定的颜色: 0无 1红 2绿 3蓝
extern volatile uint8 color_track_mode;     // 目标选择: 0自动(就近) 1红 2绿 3蓝
extern volatile float color_track_yaw_cmd;  // 车头跟随色块算出的转向命令(已平滑)
extern volatile uint8 color_track_arrived;  // 1=已追到(锁存停车), 宽度回落才解除
extern volatile uint32 color_track_frames;  // 已收帧计数
extern volatile uint32 color_track_rx_bytes;// 调试用: UART_1 收到的原始字节总数
extern volatile int8  color_track_dev_r;
extern volatile int8  color_track_dev_g;
extern volatile int8  color_track_dev_b;
extern volatile uint8 color_track_wid_r;
extern volatile uint8 color_track_wid_g;
extern volatile uint8 color_track_wid_b;

void ColorTrack_Init(void);                 // 初始化接收串口 + 使能接收中断
void ColorTrack_UartRxByte(uint8 b);        // 串口中断里每收到一个字节调一次
void ColorTrack_Poll(void);                 // 主循环里周期调用(丢链保护)
void ColorTrack_KeyTask(void);              // 周期调用: 扫描按键, 每按一次循环切换目标色
void ColorTrack_UpdateCommand(void);        // 20ms控制周期: 生成麦轮横移/前进指令

#endif /* CODE_COLOR_TRACK_H_ */
