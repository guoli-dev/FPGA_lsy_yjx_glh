#include "zf_common_headfile.h"

double q0 = 1, q1 = 0, q2 = 0, q3 = 0;    // ��ʼλ����̬��Ϊ��0��0��0����Ӧ��Ԫ��Ϊ��1��0��0��0��q = cos(��/2) + sin(��/2)��(xi + yj + zk)q0 = cos(��/2)
eulerAngle_info_struct eulerAngle;                            //ŷ��
Static_struct Sta;
double I_ex, I_ey, I_ez;                                  // ������
double imu_kp= 1.5;                                           //���ٶȼƵ��������ʱ�������
double imu_ki= 0.0005;                                       //�������������ʵĻ�������
imu_info_struct imu;
#define M_PI 3.14159265358979323846
// �򻯵�atan2ʵ�֣������ڵ���
//double my_atan2(double y, double x)
//{
//    if (x > 0.0) {
//        return atan(y / x);
//    } else if (x < 0.0 && y >= 0.0) {
//        return atan(y / x) + M_PI;
//    } else if (x < 0.0 && y < 0.0) {
//        return atan(y / x) - M_PI;
//    } else if (x == 0.0 && y > 0.0) {
//        return M_PI_2;
//    } else if (x == 0.0 && y < 0.0) {
//        return -M_PI_2;
//    } else {
//        // x=0, y=0�����
//        return 0.0;
//    }
//}

float my_sqrt_reciprocal(float number)
{
    long i;
    float x, y;

    x = number * 0.5F;
    y = number;
    i = * ( long * ) &y;
    i = 0x5f3759df - ( i >> 1 );

    y = * ( float * ) &i;
    y = y * ( 1.5f - ( x * y * y ) );
    y = y * ( 1.5f - ( x * y * y ) );

    return y;
}
//����ƽ�����㷨
float my_sqrt(float number)
{
    return number * my_sqrt_reciprocal(number);
}
//������ʼ�����ͼ�����Ư�йصı�����
void gyro_data_init(void)
{
    imu.gyro.count = 0;
    imu.gyro.zero_calc_flag = true;
}
//���ԭʼ����
void get_imu_data(void)
{
    imu660ra_get_acc();//��ȡ���ٶȼ�����
    imu660ra_get_gyro();//��ȡ�Ƕ�����
}
//imu���ݴ������˲��͵�λת����
void imu_data_deal(void)
{
    float alpha = 0.2;  //0.35

     //һ�׵�ͨ�˲�����λg
    imu.acc.acc[X] =  ACC_DATA_X / ACC_SPL * alpha  + imu.acc.acc[X] * (1 - alpha);
    imu.acc.acc[Y] =  ACC_DATA_Y / ACC_SPL * alpha  + imu.acc.acc[Y] * (1 - alpha);
    imu.acc.acc[Z] =  ACC_DATA_Z / ACC_SPL * alpha  + imu.acc.acc[Z] * (1 - alpha);

    imu.gyro.gyro[X] = ANGLE_TO_RAD(GYRO_DATA_X / GYRO_SPL);
    imu.gyro.gyro[Y] = ANGLE_TO_RAD(GYRO_DATA_Y / GYRO_SPL);
    imu.gyro.gyro[Z] = ANGLE_TO_RAD(GYRO_DATA_Z / GYRO_SPL);
}
//��ֹ��⺯��
void Static_detection(float dT_s,double gyr_dps_in[3])
{
    static float gyr_tmp[3];
    static float gyr_delta_tmp[3];
    static float gyr_delta_length;
    for(uint8_t i=0;i<3;i++)
    {
        //�����������ݽ��е�ͨ�˲�����ֹƵ��2Hz��
        LPF_1_(2.0f,dT_s,(gyr_dps_in[i] ),gyr_tmp[i]);
        //���㵱ǰֵ���˲�ֵ�Ĳ�ֵ���仯����
        gyr_delta_tmp[i] = gyr_dps_in[i]  - gyr_tmp[i];
    }
    //������ά������ģ����������仯�����ۺϷ��ȣ���ӳ�����˶�ǿ��
    gyr_delta_length = my_3_norm(gyr_delta_tmp[0],gyr_delta_tmp[1],gyr_delta_tmp[2]);
//    if(gyr_delta_length>GYR_CKS_VAL)//����
//    {
//        printf("cnieuhfiuwaerhuirewfhiuaewsfuireaw");
//    }
//    printf("%f\r\n",gyr_delta_length);

    //���gyr�Ƿ��ȶ�
    if(gyr_delta_length>GYR_CKS_VAL)//�����Ǿ�ֹ��⣨�߼���ͬ��
    {
        Sta.GryState = 0;
    }
    else
    {
        Sta.GryState = 1;
    }
}
/**
 * @brief �û����˲��㷨������������̬(�����ü��ٶȼ����������ǵĻ������)
 * ���ٶȼƶ���֮��������Ƚ����У��������ݼ��������̬���ţ������Ƕ������������У��������ݿ��ţ�
 * ������ʹ�û����������(�ڲ������㷨�Ŵ�̬���)��
 * ���ʹ����̬�����˲����������������ǣ��������ż��ٶȼơ�
 */
//��Ԫ������Ƕȣ�ֻ�õ��˸����Ǻͺ���ǣ�
double ex, ey, ez;     // ��ǰ���ټƲ�õ��������ٶ��������ϵķ������õ�ǰ��̬��������������������ϵķ��������
void Update_Angle(void)
{
    double halfT = 0.5 * delta_T;    // ��������һ��

    double vx, vy, vz;     // ��ǰ��̬��������������������ϵķ���

    double q0q0 = q0 * q0;//����ˣ������������
    double q0q1 = q0 * q1;
    double q0q2 = q0 * q2;
    //double q0q3 = q0 * q3;//δʹ��
    double q1q1 = q1 * q1;
    //double q1q2 = q1 * q2;//δʹ��
    double q1q3 = q1 * q3;
    double q2q2 = q2 * q2;
    double q2q3 = q2 * q3;
    double q3q3 = q3 * q3;
    
    // ������ֹ״̬Ϊ-g ����������
    if(imu.acc.acc[X] * imu.acc.acc[Y] * imu.acc.acc[Z] == 0) // ���ٶȼƴ�����������״̬ʱ(��ʱg = 0)��������̬���㣬��Ϊ�������ĸ���������
        return;
    
    // �Լ��ٶ����ݽ��й�һ���õ���λ���ٶ�
    //���ٶȼ�<����>���������ٶ�����(��������ϵ)
    double norm = 1/my_sqrt(imu.acc.acc[X] *imu.acc.acc[X] + imu.acc.acc[Y]*imu.acc.acc[Y] + imu.acc.acc[Z]* imu.acc.acc[Z]);
    
  // printf("%f,%f,%f\r\n  imu.acc",imu.acc.acc[X],imu.acc.acc[Y],imu.acc.acc[Z]);
    imu.acc.acc[X] = imu.acc.acc[X] * norm;
    imu.acc.acc[Y] = imu.acc.acc[Y] * norm;
    imu.acc.acc[Z] = imu.acc.acc[Z] * norm;
   //printf("%f\r\n guiyihua", imu.acc.acc[X] *imu.acc.acc[X]+ imu.acc.acc[Y]*imu.acc.acc[Y] + imu.acc.acc[Z]* imu.acc.acc[Z]);
    //printf("%f\r\n norm1",norm);
    //�����ǻ���<����>��������(��������ϵ)
    // ��������ϵ���������������ϵķ���
    vx = 2 * (q1q3 - q0q2);
    vy = 2 * (q0q1 + q2q3);
    vz = q0q0 - q1q1 - q2q2 + q3q3;

    //�����ٶȼƻ�õ�����������һ�����ֵ����ȡ����̬���������������˻�ȡ��̬���
    ex = imu.acc.acc[Y] * vz - imu.acc.acc[Z]* vy;
    ey = imu.acc.acc[Z] * vx - imu.acc.acc[X]* vz;
    ez = imu.acc.acc[X] * vy - imu.acc.acc[Y]* vx;

    //�������л���
    I_ex += ex;
    I_ey += ey;
    I_ez += ez;

    //���������PID���������������ǲ�õĽ��ٶ���ӣ��������ٶ�ֵ
    imu.gyro.gyro[X] = imu.gyro.gyro[X] + imu_kp* ex + imu_ki* I_ex;
    imu.gyro.gyro[Y] = imu.gyro.gyro[Y] + imu_kp* ey + imu_ki* I_ey;
    imu.gyro.gyro[Z] = imu.gyro.gyro[Z] + imu_kp* ez + imu_ki* I_ez;

    // һ����������������Ԫ��΢�ַ��̣�����halfTΪ�������ڵ�1/2
    q0 = q0 + (-q1 * imu.gyro.gyro[X] - q2 * imu.gyro.gyro[Y] - q3 * imu.gyro.gyro[Z]) * halfT;
    q1 = q1 + ( q0 * imu.gyro.gyro[X] + q2 * imu.gyro.gyro[Z] - q3 * imu.gyro.gyro[Y]) * halfT;
    q2 = q2 + ( q0 * imu.gyro.gyro[Y] - q1 * imu.gyro.gyro[Z] + q3 * imu.gyro.gyro[X]) * halfT;
    q3 = q3 + ( q0 * imu.gyro.gyro[Z] + q1 * imu.gyro.gyro[Y] - q2 * imu.gyro.gyro[X]) * halfT;
//    
    // ��λ����Ԫ���ڿռ���תʱ�������죬������ת�Ƕȣ������㷨�������Դ�����������任
    norm = 1/my_sqrt(q0*q0 + q1*q1 + q2*q2 + q3*q3);
   // printf("%f\r\n norm2     ",norm);
    q0 = q0 * norm;
    q1 = q1 * norm;
    q2 = q2 * norm;
    q3 = q3 * norm;
  //printf("%f,%f,%f,%f\r\n q0123     ",q0,q1,q2,q3);
    eulerAngle.roll = RAD_TO_ANGLE(asin(2 * q0 * q2 - 2 * q1 * q3));//-90~90
    eulerAngle.pitch = RAD_TO_ANGLE(atan2(2 * q2 * q3 + 2* q0 * q1, q0 * q0 - q1 * q1 - q2 * q2 + q3 * q3));//-180~180
    eulerAngle.yaw = RAD_TO_ANGLE(atan2(2 * q1 * q2 + 2 * q0 * q3,  q0 * q0 +q1 * q1 - q2 * q2 - q3 * q3));//0~360
  //printf("%f,%f,%f\r\n",eulerAngle.pitch,eulerAngle.roll,imu.gyro.angle[Z]);
}
//零漂校准（只对 Z 轴）
void gyro_get_angle(void) // Z-axis gyro zero-bias calibration
{
    if (imu.gyro.zero_calc_flag) // 还没有完成零漂校准
    {
        Static_detection(0.005f, imu.gyro.gyro); // 判断是否静止

        if (Sta.GryState == 0) // 校准期间只要检测到不静止, 就把相关量清零重来
        {
            imu.gyro.count = 0;
            imu.gyro.zero_angle[Z] = 0;
            imu.gyro.angle[Z] = 0;
            imu.gyro.last_angle[Z] = 0;
        }
        else if (Sta.GryState == 1) // 静止
        {
            // 逐步积分
            imu.gyro.angle[Z] -= imu660ra_gyro_z / GYRO_SPL * 0.005;

            if (imu.gyro.count < ZERO_CALC_COUNT) // 零漂采样中
            {
                // 把每一步的角度增量累加起来 = 累积漂移
                imu.gyro.zero_angle[Z] += imu.gyro.angle[Z] - imu.gyro.last_angle[Z];
                imu.gyro.last_angle[Z] = imu.gyro.angle[Z];
                imu.gyro.count++;
            }
            else // 采样够了, 求平均零漂并补偿
            {
                imu.gyro.zero_angle[Z] /= ZERO_CALC_COUNT;
                imu.gyro.angle[Z] -= imu.gyro.zero_angle[Z]; // 补偿掉累积的零漂

                imu.gyro.zero_calc_flag = false;
                imu.gyro.count = 0;
            }
        }
    }
    else // 去掉零漂(每步都减掉平均零漂)
    {
        imu.gyro.angle[Z] -= imu660ra_gyro_z / GYRO_SPL * 0.005;
        imu.gyro.angle[Z] -= imu.gyro.zero_angle[Z];
    }
}
// IMU attitude task
void imu_task(void)
{
    gyro_get_angle();
    //����Ƕ�
    Update_Angle();
}
