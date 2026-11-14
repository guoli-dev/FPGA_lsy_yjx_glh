#ifndef CODE_IMU_H_
#define CODE_IMU_H_

#define delta_T  0.005f                 //四元数计算的周期

#define GYRO_SPL 16.4                   //陀螺仪数据转换系数（LSB/(°/s)）
#define ACC_SPL  4096.0                 //加速度计数据转换系数（LSB/g）

#define my_pow(a) ((a)*(a))
#define my_3_norm(x,y,z) (my_sqrt(my_pow((x)) + my_pow((y)) + my_pow((z))))
#define LPF_1_(hz,t,in,out) ((out) += ( 1 / ( 1 + 1 / ( (hz) *6.28f *(t) ) ) ) *( (in) - (out) ))

#define GYR_CKS_VAL  0.1f             //静止检测的

#define ZERO_CALC_COUNT  1000            //计算零漂的时间

#define GYRO_DATA_X (imu660ra_gyro_x) //陀螺仪 X 轴原始数据
#define GYRO_DATA_Y (imu660ra_gyro_y) //陀螺仪 Y 轴原始数据（带方向转换）
#define GYRO_DATA_Z (imu660ra_gyro_z) //陀螺仪 Z 轴原始数据（带方向转换） 

#define ACC_DATA_X (imu660ra_acc_x) //加速度计 X 轴原始数据
#define ACC_DATA_Y (imu660ra_acc_y) //加速度计 Y 轴原始数据（带方向转换）
#define ACC_DATA_Z (imu660ra_acc_z) //加速度计 Z 轴原始数据（带方向转换）

//三轴
typedef enum
{
    X,
    Y,
    Z,
    NUM_XYZ
}imu_info_enum;

//陀螺仪
typedef struct
{

   bool zero_calc_flag;//零漂计算标志

   double angle[NUM_XYZ];//简单积分得到的角度

   double last_angle[NUM_XYZ];//上一次角度

   double zero_angle[NUM_XYZ];//总漂移量

   double gyro[NUM_XYZ];//角速度

   int count;

}gyroscope_info_struct;

//加速度计
typedef struct
{
    double acc[NUM_XYZ];//角加速度
}acc_info_struct;

//imu
typedef struct
{
    gyroscope_info_struct gyro; //陀螺仪
    acc_info_struct acc; //加速度计
}imu_info_struct;

//欧拉角结构体
typedef struct
{
    double pitch;
    double roll;
    double yaw;
}eulerAngle_info_struct;

typedef struct
{
    uint8_t GryState;
    uint8_t AccState;
    uint8_t Count;
} Static_struct;

extern imu_info_struct imu;
extern eulerAngle_info_struct eulerAngle;
extern double imu_kp;                                             //加速度计的收敛速率比例增益
extern double imu_ki;                                             //陀螺仪收敛速率的积分增益
extern double I_ex, I_ey, I_ez;                                  // 误差积分
extern double ex, ey, ez;

void get_imu_data(void);
void gyro_get_angle(void);
void gyro_data_init(void);
void imu_task(void);
void Update_Angle(void);
void imu_data_deal(void);
void gyroOffsetInit(void);
void accOffsetInit(void);
#endif /* CODE_QUATER_QUATER_H_ */
