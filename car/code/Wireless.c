#include "zf_common_headfile.h"

char send_str[32] = {0};

void Wireless_Init(void)
{
    while(wifi_spi_init(WIFI_SSID_TEST, WIFI_PASSWORD_TEST))
    {
        printf("\r\n connect wifi failed. \r\n");
        system_delay_ms(100);                                                   // 初始化失败 等待 100ms
    }
    if(1 != WIFI_SPI_AUTO_CONNECT)                                              // 如果没有开启自动连接 就需要手动连接目标 IP
    {
        while(wifi_spi_socket_connect(                                          // 向指定目标 IP 的端口建立 TCP 连接
            "TCP",                                                              // 指定使用TCP方式通讯
            WIFI_SPI_TARGET_IP,                                                 // 指定远端的IP地址，填写上位机的IP地址
            WIFI_SPI_TARGET_PORT,                                               // 指定远端的端口号，填写上位机的端口号，通常上位机默认是8080
            WIFI_SPI_LOCAL_PORT))                                               // 指定本机的端口号
        {
            // 如果一直建立失败 考虑一下是不是没有接硬件复位
            printf("\r\n Connect TCP Servers error, try again.");
            system_delay_ms(100);                                               // 建立连接失败 等待 100ms
        }
    }
    seekfree_assistant_interface_init(SEEKFREE_ASSISTANT_WIFI_SPI);
}

void Wireless_Parameter(void)
{
    seekfree_assistant_data_analysis();
    for(uint8_t i = 0; i < SEEKFREE_ASSISTANT_SET_PARAMETR_COUNT; i++)
    {
       // 更新标志位
       if(seekfree_assistant_parameter_update_flag[i])
       {
           seekfree_assistant_parameter_update_flag[i] = 0;
           // 通过无线转串口发送信息
//           if(seekfree_assistant_parameter[0]!=0)
//               angle_cycle.p=seekfree_assistant_parameter[0];
//           if(seekfree_assistant_parameter[1]!=0)
//               angle_cycle.d=seekfree_assistant_parameter[1];
//           if(seekfree_assistant_parameter[2]!=0)
//               angle_cycle.out_max=seekfree_assistant_parameter[2];
//           if(seekfree_assistant_parameter[3]!=0)
//               angular_speed_cycle.p=seekfree_assistant_parameter[3];
//           if(seekfree_assistant_parameter[4]!=0)
//               angular_speed_cycle.d=seekfree_assistant_parameter[4];
//           if(seekfree_assistant_parameter[5]!=0)
//               angular_speed_cycle.out_max=seekfree_assistant_parameter[5];
//           if(seekfree_assistant_parameter[6]!=0)
//               Target_Angle=seekfree_assistant_parameter[6];
           sprintf(send_str,"receive data channel : %d ", i);
           wifi_spi_send_buffer((uint8 *)send_str,strlen(send_str));
           sprintf(send_str,"data : %.2f\r\n", seekfree_assistant_parameter[i]);
           wifi_spi_send_buffer((uint8 *)send_str,strlen(send_str));
       }
    }
//    if(angle_cycle.d==0.1)
//    {
//        angle_cycle.d=0;
//    }
//    if(Target_Angle==1)
//    {
//        Target_Angle=0;
//    }
}

