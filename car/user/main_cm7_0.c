/*********************************************************************************************************************
* CYT4BB Opensourec Library ���� CYT4BB ��Դ�⣩��һ�����ڹٷ� SDK �ӿڵĵ�������Դ��
* Copyright (c) 2022 SEEKFREE ��ɿƼ�
*
* ���ļ��� CYT4BB ��Դ���һ����
*
* CYT4BB ��Դ�� ���������
* �����Ը���������������ᷢ���� GPL��GNU General Public License���� GNUͨ�ù�������֤��������
* �� GPL �ĵ�3�棨�� GPL3.0������ѡ��ģ��κκ����İ汾�����·�����/���޸���
*
* ����Դ��ķ�����ϣ�����ܷ������ã�����δ�������κεı�֤
* ����û�������������Ի��ʺ��ض���;�ı�֤
* ����ϸ����μ� GPL
*
* ��Ӧ�����յ�����Դ���ͬʱ�յ�һ�� GPL �ĸ���
* ���û�У������<https://www.gnu.org/licenses/>
*
* ����ע����
* ����Դ��ʹ�� GPL3.0 ��Դ����֤Э�� ������������Ϊ���İ汾
* ��������Ӣ�İ��� libraries/doc �ļ����µ� GPL3_permission_statement.txt �ļ���
* ����֤������ libraries �ļ����� �����ļ����µ� LICENSE �ļ�
* ��ӭ��λʹ�ò����������� ���޸�����ʱ���뱣����ɿƼ��İ�Ȩ����������������
*
* �ļ�����          main_cm7_0
* ��˾����          �ɶ���ɿƼ����޹�˾
* �汾��Ϣ          �鿴 libraries/doc �ļ����� version �ļ� �汾˵��
* ��������          IAR 9.40.1
* ����ƽ̨          CYT4BB
* ��������          https://seekfree.taobao.com/
*
* �޸ļ�¼
* ����              ����                ��ע
* 2024-1-4                  
********************************************************************************************************************/

#include "zf_common_headfile.h"
#include "zf_device_ips200.h"
#include "zf_device_imu660ra.h"
#include "Control.h"   // ������ʵ�ʵ�ͷ�ļ���

volatile uint8 imu_ready = 0u;
extern uint32 system_time;
static uint32 main_loop_heartbeat = 0u;
// ���µĹ��̻��߹����ƶ���λ�����ִ�����²���
// ��һ�� �ر��������д򿪵��ļ�
// �ڶ��� project->clean  �ȴ��·�����������

// �������ǿ�Դ��չ��� ��������ֲ���߲��Ը���������
// �������ǿ�Դ��չ��� ��������ֲ���߲��Ը���������
// �������ǿ�Դ��չ��� ��������ֲ���߲��Ը���������

// **************************** �������� ****************************
//��Ļ��ʾ������������������������������������
static char lcd_buf[32];
void LCD_ShowCarSpeed(float speed_x, float speed_y)
{
    static char lcd_buf[32];

    ips200_show_string(0, 0, "Recv X/Y");

    snprintf(lcd_buf, sizeof(lcd_buf), "RX: %+7.2f", speed_x);
    ips200_show_string(0, 20, lcd_buf);

    snprintf(lcd_buf, sizeof(lcd_buf), "RY: %+7.2f", speed_y);
    ips200_show_string(0, 40, lcd_buf);
}
/**
 * @brief ����Ļ��ͬʱ��ʾ����ٶ���Ϣ��������λʱ����ʾ��
 */
void LCD_ShowSpeedWithTime(float speed_x, float speed_y, uint32_t time_ms)
{
    static char lcd_buf[32];
    
    // ��ʾ�����ʱ��
    ips200_show_string(0, 0, "=== Speed Monitor ===");
    
    // ��ʾʱ���������ṩ��
    if(time_ms > 0)
    {
        snprintf(lcd_buf, sizeof(lcd_buf), "Time: %d ms", time_ms);
        ips200_show_string(0, 20, lcd_buf);
    }
    
    // ��ʾX���ٶ�
    snprintf(lcd_buf, sizeof(lcd_buf), "Vx: %+7.2f", speed_x);
    ips200_show_string(0, 45, lcd_buf);
    
    // ��ʾY���ٶ�
    snprintf(lcd_buf, sizeof(lcd_buf), "Vy: %+7.2f", speed_y);
    ips200_show_string(0, 65, lcd_buf);
    
    // ��ʾ�ٶȴ�С��������
    float speed_mag = sqrtf(speed_x * speed_x + speed_y * speed_y);
    snprintf(lcd_buf, sizeof(lcd_buf), "|V|: %6.2f", speed_mag);
    ips200_show_string(0, 85, lcd_buf);
}



// 修复：将函数名写在一行
void LCD_ShowSpeedAndIMU(float speed_x, float speed_y)
{
    // 直接使用全局lcd_buf
    LCD_ShowCarSpeed(speed_x, speed_y);
    snprintf(lcd_buf, sizeof(lcd_buf), "GyroZ:%+7.2f", imu.gyro.gyro[Z]);
    ips200_show_string(0, 75, lcd_buf);
    snprintf(lcd_buf, sizeof(lcd_buf), "Yaw  :%+6.1f", (float)eulerAngle.yaw);
    ips200_show_string(0, 95, lcd_buf);
}

void LCD_ShowTitle(const char *mode_name)
{
    ips200_clear();
    ips200_show_string(0, 0, "Fly Over Minefield");
    snprintf(lcd_buf, sizeof(lcd_buf), "Mode: %s", mode_name);
    ips200_show_string(0, 20, lcd_buf);
}
void IMU_Debug_Print(void)
{
    // ����һ����̬����,ȷ����ʾ������������
    imu_task();
    LCD_ShowTitle("IMU");

    // ---- ������ԭʼ���ٶ�(��λ: rad/s,���� imu_data_deal ת�����ֵ) ----
    snprintf(lcd_buf, sizeof(lcd_buf), "GyroX:%+7.3f", imu.gyro.gyro[X]);
    ips200_show_string(0, 20, lcd_buf);
    snprintf(lcd_buf, sizeof(lcd_buf), "GyroY:%+7.3f", imu.gyro.gyro[Y]);
    ips200_show_string(0, 40, lcd_buf);
    snprintf(lcd_buf, sizeof(lcd_buf), "GyroZ:%+7.3f", imu.gyro.gyro[Z]);
    ips200_show_string(0, 60, lcd_buf);

    // ---- ���ٶȼ�ԭʼ����(��λ: g) ----
    snprintf(lcd_buf, sizeof(lcd_buf), "AccX :%+7.3f", imu.acc.acc[X]);
    ips200_show_string(0, 80, lcd_buf);
    snprintf(lcd_buf, sizeof(lcd_buf), "AccY :%+7.3f", imu.acc.acc[Y]);
    ips200_show_string(0, 100, lcd_buf);
    snprintf(lcd_buf, sizeof(lcd_buf), "AccZ :%+7.3f", imu.acc.acc[Z]);
    ips200_show_string(0, 120, lcd_buf);

    // ---- ��Ԫ��������ŷ����(��λ: ��) ----
    snprintf(lcd_buf, sizeof(lcd_buf), "Pitch:%+6.1f", (float)eulerAngle.pitch);
    ips200_show_string(0, 140, lcd_buf);
    snprintf(lcd_buf, sizeof(lcd_buf), "Roll :%+6.1f", (float)eulerAngle.roll);
    ips200_show_string(0, 160, lcd_buf);
    snprintf(lcd_buf, sizeof(lcd_buf), "Yaw  :%+6.1f", (float)eulerAngle.yaw);
    ips200_show_string(0, 180, lcd_buf);
}
/**
 * @brief 屏幕显示四轮目标速度和编码器实际速度
 */
void LCD_ShowWheelSpeed(void)
{
    static char lcd_buf[32];

    ips200_show_string(0, 0, "Wheel Target / Actual");

    snprintf(lcd_buf, sizeof(lcd_buf), "LF T:%6d A:%6d", LF_Target_Speed, LF_encoder_data);
    ips200_show_string(0, 20, lcd_buf);
    snprintf(lcd_buf, sizeof(lcd_buf), "RF T:%6d A:%6d", RF_Target_Speed, RF_encoder_data);
    ips200_show_string(0, 40, lcd_buf);
    snprintf(lcd_buf, sizeof(lcd_buf), "LB T:%6d A:%6d", LB_Target_Speed, LB_encoder_data);
    ips200_show_string(0, 60, lcd_buf);
    snprintf(lcd_buf, sizeof(lcd_buf), "RB T:%6d A:%6d", RB_Target_Speed, RB_encoder_data);
    ips200_show_string(0, 80, lcd_buf);

    snprintf(lcd_buf, sizeof(lcd_buf), "RX:%6u F:%6u",
             (unsigned)color_track_rx_bytes, (unsigned)color_track_frames);
    ips200_show_string(0, 110, lcd_buf);
    snprintf(lcd_buf, sizeof(lcd_buf), "M:%u S:%+4d/%3u L:%u F:%u A:%u",
             (unsigned)color_track_mode,
             (int)color_track_dev, (unsigned)color_track_wid,
             (unsigned)color_track_locked, (unsigned)color_track_found,
             (unsigned)color_track_arrived);
    ips200_show_string(0, 130, lcd_buf);
    snprintf(lcd_buf, sizeof(lcd_buf), "IMU:%u Cal:%u En:%u",
             (unsigned)imu_ready, (unsigned)imu.gyro.zero_calc_flag,
             (unsigned)color_track_enable);
    ips200_show_string(0, 150, lcd_buf);
    snprintf(lcd_buf, sizeof(lcd_buf), "Cmd X:%4d Y:%4d",
             (int)Car_Speed_X, (int)Car_Speed_Y);
    ips200_show_string(0, 170, lcd_buf);
    snprintf(lcd_buf, sizeof(lcd_buf), "Loop:%6u ms:%6u",
             (unsigned)main_loop_heartbeat, (unsigned)system_time);
    ips200_show_string(0, 190, lcd_buf);
    snprintf(lcd_buf, sizeof(lcd_buf), "GZ:%+6d Z0:%+6.1f A:%+6.1f",
             (int)GYRO_DATA_Z, (float)imu.gyro.zero_angle[Z],
             (float)imu.gyro.angle[Z]);
    ips200_show_string(0, 210, lcd_buf);
}

/**
 * @brief ����Ļ����ʾ Car_Speed_X / Y / Z ����������ٶ�
 */
/**
 * @brief ����Ļ����ʾ���յ���ԭʼ���� x/y
 */


/**
 * @brief ����Ļ����ʾ Car_Speed_X / Y / Z ����������ٶ�
 */
void LCD_ShowSpeedXYZ(float speed_x, float speed_y, float speed_z)
{
    static char lcd_buf[32];

    ips200_show_string(0, 70, "Speed X/Y/Z");

    snprintf(lcd_buf, sizeof(lcd_buf), "Vx: %+7.2f", speed_x);
    ips200_show_string(0, 90, lcd_buf);

    snprintf(lcd_buf, sizeof(lcd_buf), "Vy: %+7.2f", speed_y);
    ips200_show_string(0, 110, lcd_buf);

    snprintf(lcd_buf, sizeof(lcd_buf), "Vz: %+7.2f", speed_z);
    ips200_show_string(0, 130, lcd_buf);
}
//��Ļ��ʾ����������������������������������������������
int main(void)
{
    clock_init(SYSTEM_CLOCK_250M); 	// ʱ�����ü�ϵͳ��ʼ��<��ر���>
    debug_init();                       // ���Դ�����Ϣ��ʼ��
    // �˴���д�û����� ���������ʼ�������
    // IMU 用于麦轮横移时保持车头方向；失败时安全停用，不无限重试。
    imu_ready = (imu660ra_init() == 0u) ? 1u : 0u;
    if(imu_ready)
    {
        gyro_data_init();
        printf("IMU660RA ready, keep still for calibration.\r\n");
    }
    else
    {
        printf("IMU660RA init failed, tracking disabled.\r\n");
    }
    Pid_Init();
    Motor_Init();
    Encoder_Init();
   //��Ļ��ʼ��**************************************
    ips200_init(IPS200_TYPE_SPI);
    ips200_set_color(RGB565_WHITE, RGB565_BLACK);
    ips200_clear();
    ips200_show_string(0, 0, "System Init...");
   //***********************************************
   // Wireless_Init();
//    lora3a22_init();
    //Buzzer_Init();
    //BAT_Get_Init();
    ColorTrack_Init();          // 色块帧接收口(COLOR_TRACK_RX_PORT), 115200 8N1, 开接收中断
    Telemetry_Init();           // 车端遥测(无线串口), UART_1 只发不收
    pit_ms_init(PIT_CH0, 1);
    // �˴���д�û����� ���������ʼ�������
    static uint32 last_fps_time = 0;
    static uint32 last_fps_count = 0;
    static uint16 fps = 0;
    profile_dwt_init();

    while(true)
    { 
       main_loop_heartbeat++;

       // 电机固定占空比测试：需要时取消下面四行注释，并暂停 ColorTrack_Poll/追踪控制。
       // Motor( Left_front_Motor, 2000);
       // Motor( Right_front_Motor, 2000);
       // Motor( Left_back_Motor, 2000);
       // Motor( Right_back_Motor, 2000);

       ColorTrack_Poll();          // 丢链保护: 长时间收不到色块帧则停车
       ColorTrack_KeyTask();       // 按键选色: KEY_1 循环 自动->红->绿->蓝
       Telemetry_Task();           // 车端遥测: 内部按 20ms 限速发往无线串口

#if COLOR_TRACK_LOOPBACK_TEST
       // 回环自测: 每500ms从接收口发一帧; 把该口 TX 和 RX 短接, RX/F 应持续增长
       {
           static uint32 last_tx_ms = 0;
           static const uint8 lb_frame[7] = {0xAA,0x00,0x14,0x80,0x00,0x80,0x00};
           if((uint32)(system_time - last_tx_ms) >= 500u)
           {
               last_tx_ms = system_time;
               uart_write_buffer(COLOR_TRACK_RX_UART, lb_frame, 7);
           }
       }
#endif

       // 红绿蓝坐标 printf 到上位机(调试串口 UART_0)，每 200ms 一条
       #if 1
       {
           static uint32 last_print_ms = 0;
           if((uint32)(system_time - last_print_ms) >= 200u)
           {
               last_print_ms = system_time;
               printf("CT f:%u rx:%u L:%u R:%d/%u G:%d/%u B:%d/%u cmd:%d/%d enc:%d/%d/%d/%d imu:%u/%u fifo:%u\r\n",
                      (unsigned)color_track_frames,
                      (unsigned)color_track_rx_bytes,
                      (unsigned)color_track_locked,
                      (int)color_track_dev_r, (unsigned)color_track_wid_r,
                      (int)color_track_dev_g, (unsigned)color_track_wid_g,
                      (int)color_track_dev_b, (unsigned)color_track_wid_b,
                      (int)Car_Speed_X, (int)Car_Speed_Y,
                      LF_encoder_data, RF_encoder_data, LB_encoder_data, RB_encoder_data,
                      (unsigned)imu_ready, (unsigned)imu.gyro.zero_calc_flag,
                      (unsigned)Cy_SCB_GetNumInRxFifo(get_scb_module(UART_1)));
           }
       }
       #endif

       {
           static uint8 lcd_loop_div = 0u;
           if(++lcd_loop_div >= 5u)
           {
               lcd_loop_div = 0u;
               LCD_ShowWheelSpeed();
           }
       }

       system_delay_ms(20);

      /*
   if(need_send_arrive_flag)
       {
           need_send_arrive_flag = 0;
           uint8 fb_status = COMM_STATUS_SPEED_VALID;
           if(car_comm_lost != 0u)
           {
               fb_status |= COMM_STATUS_COMM_LOST;
           }
           else if(car_stop_requested != 0u)
           {
               fb_status |= (car_stopped_confirmed != 0u) ?
                            COMM_STATUS_STOPPED : COMM_STATUS_STOPPING;
               if((pending_arrive_status != 0u) && (car_stopped_confirmed != 0u))
               {
                   fb_status |= COMM_STATUS_ARRIVED;
               }
           }
           else
           {
               fb_status |= COMM_STATUS_TRACKING;
           }
           car_send_feedback(car_value.target_seq, fb_status,
                             (int16)car_actual_vy, (int16)car_actual_vx);
       }
       // 编码器显示 (y=145/158)
        {
            static char lcd_buf[32];
            snprintf(lcd_buf, sizeof(lcd_buf), "LF:%6d RF:%6d", LF_encoder_data, RF_encoder_data);
            ips200_show_string(0, 145, lcd_buf);
            snprintf(lcd_buf, sizeof(lcd_buf), "LB:%6d RB:%6d", LB_encoder_data, RB_encoder_data);
            ips200_show_string(0, 158, lcd_buf);
        }
        LCD_ShowCarSpeed(car_value.receive_fwd, car_value.receive_right);
        LCD_ShowSpeedXYZ(Car_Speed_X, Car_Speed_Y, Car_Speed_Z);
        // 色块调试: 目标色块 偏差/宽度/是否看到  (y=210)
        {
            static char ctlcd[32];
            snprintf(ctlcd, sizeof(ctlcd), "CT dev:%+4d wid:%3d %s",
                     (int)color_track_dev, (int)color_track_wid,
                     color_track_found ? "FND" : "---");
            ips200_show_string(0, 210, ctlcd);
        }
        // 帧信息 (y=175/192)
        {
            static char lcd_buf[32];
            // 每秒更新一次 FPS
            uint32 now = system_time;
            if(now - last_fps_time >= 1000)
            {
                fps = (uint16)(car_value.frame_count - last_fps_count);
                last_fps_count = car_value.frame_count;
                last_fps_time = now;
            }
            snprintf(lcd_buf, sizeof(lcd_buf), "F:%d ITV:%dms",
                     car_value.frame_count, fps ? (1000 / fps) : 0);
            ips200_show_string(0, 175, lcd_buf);

            snprintf(lcd_buf, sizeof(lcd_buf), "IMU:%d Tsk:%d PID:%d Tot:%d",
                     profile_imu_max, profile_task_max, profile_pid_max, profile_total_max);
            ips200_show_string(0, 192, lcd_buf);
        }
       // printf("%f,%f\r\n",Car_Speed_X,Car_Speed_Y);
       // pit_handler();
//        seekfree_assistant_data_analysis();
//        for(uint8_t i = 0; i < SEEKFREE_ASSISTANT_SET_PARAMETR_COUNT; i++)
//        {
//           // ���±�־λ
//           if(seekfree_assistant_parameter_update_flag[i])
//            {
//               seekfree_assistant_parameter_update_flag[i] = 0;
//               // ͨ������ת���ڷ�����Ϣ
//               if(seekfree_assistant_parameter[0]!=0)
//                   POS_TO_SPEED_KP=seekfree_assistant_parameter[0];
//               if(seekfree_assistant_parameter[1]!=0)
//               {
//                   RF_speed_cycle.i=seekfree_assistant_parameter[1];
//               }
//               if(seekfree_assistant_parameter[2]!=0)
//                   Target_Angle=seekfree_assistant_parameter[2];
////               if(seekfree_assistant_parameter[3]!=0)
////                   y_speed_cycle.p=seekfree_assistant_parameter[3];
////               if(seekfree_assistant_parameter[4]!=0)
////               {
////                   y_speed_cycle.i_value_pro=seekfree_assistant_parameter[4];
////                   y_speed_cycle.i_value=0;
////               }
////               if(seekfree_assistant_parameter[5]!=0)
////                   y_speed_cycle.d=seekfree_assistant_parameter[5];
////               if(seekfree_assistant_parameter[6]!=0)
////                   y_speed_cycle.i_value_max=seekfree_assistant_parameter[6];//Target_Height
////               if(seekfree_assistant_parameter[6]!=0)
////                   y_speed_cycle.p=seekfree_assistant_parameter[6];//rol_angular_speed_cycle.d
////               if(seekfree_assistant_parameter[7]!=0)
////                   pit_angular_speed_cycle.d =seekfree_assistant_parameter[7];
//               sprintf(send_str,"receive data channel : %d ", i);
//               wifi_spi_send_buffer((uint8 *)send_str,strlen(send_str));
//               sprintf(send_str,"data : %.2f\r\n", seekfree_assistant_parameter[i]);
//               wifi_spi_send_buffer((uint8 *)send_str,strlen(send_str));
//           }
//        }
//        
//        seekfree_assistant_oscilloscope_data.data[0] = imu.gyro.angle[Z];
//        seekfree_assistant_oscilloscope_data.data[1] = car_value.receive_x_data;
//        seekfree_assistant_oscilloscope_data.data[2] = car_value.receive_y_data;
//        seekfree_assistant_oscilloscope_data.data[3] = LF_encoder_data;
//        seekfree_assistant_oscilloscope_data.data[4] = LB_encoder_data;
////        seekfree_assistant_oscilloscope_data.data[5] = 0;
////        seekfree_assistant_oscilloscope_data.data[6] = filtered_height;
////        seekfree_assistant_oscilloscope_data.data[7] = real_Target_height;
////        // ���ñ�����Ҫ���ͼ���ͨ��������
//        seekfree_assistant_oscilloscope_data.channel_num = 5;
////
//        // �����������4��ͨ�������ݣ����֧��8ͨ��
//        seekfree_assistant_oscilloscope_send(&seekfree_assistant_oscilloscope_data);                                                                                                                           
        // �˴���д��Ҫѭ��ִ�еĴ���*/
    }
}

// **************************** �������� ****************************
