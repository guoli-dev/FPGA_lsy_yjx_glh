#ifndef CODE_WIRELESS_H_
#define CODE_WIRELESS_H_

// 开源仓库不含真实 WiFi 凭据，编译前请改成自己的热点名称与密码。
// 原工程使用逐飞无线串口模块，两端（车端与上位机）需配成同一网络。
#ifndef WIFI_SSID_TEST
#define WIFI_SSID_TEST          "YOUR_WIFI_SSID"
#endif
#ifndef WIFI_PASSWORD_TEST
#define WIFI_PASSWORD_TEST      "YOUR_WIFI_PASSWORD"
#endif

void Wireless_Init(void);
void Wireless_Parameter(void);

extern char send_str[32];

#endif