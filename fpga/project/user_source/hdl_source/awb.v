/*****************************************************************
Company : MiLianKe Electronic Technology Co., Ltd.
WebSite:https://www.milianke.com
TechWeb:https://www.uisrc.com
tmall-shop:https://milianke.tmall.com
jd-shop:https://milianke.jd.com
taobao-shop: https://milianke.taobao.com
Description: 
The reference demo provided by Milianke is only used for learning. 
We cannot ensure that the demo itself is free of bugs, so users 
should be responsible for the technical problems and consequences
caused by the use of their own products.
@Author      :   XiaoQingquan 
@Time        :   2024/10 
version:     :   
@Description :   ??????????????????????????BRAM IP??
                 ???????????????????????????????
                 ????????????
*****************************************************************/
module awb  #(   
    parameter IMG_HEIGHT = 1080,
    parameter IMG_WIDTH  = 1920
) 
(
    input                   I_clk  ,
    input                   I_rst_n,

    input [19:0]            I_global_gain,  // ?????? Q16 (1.0=20'h10000)
    input [19:0]            I_wb_r_trim,
    input [19:0]            I_wb_g_trim,
    input [19:0]            I_wb_b_trim,

    input                   I_tlast  ,
    input                   I_tuser  ,
    input [95:0]            I_tdata  ,
    input                   I_tvalid , 
    output                  I_tready ,

    output                  O_tlast  ,
    output                  O_tuser  ,
    output [95:0]           O_tdata  ,
    output [95:0]           O_raw_tdata,
    output                  O_tvalid ,
    input                   O_tready
);

// White balance mode selection. Only one of these should be 1.
//
//   WB_LOCK_EN = 1: let the AWB converge on the ambient scene for
//                   WB_LOCK_FRAMES frames, then freeze the R/B gains.
//                   The gains come from the actual picture, so no button
//                   presses and no guessed constants are needed, and the
//                   correction range is the full AWB range.
//
//   FIXED_WB_ONLY = 1: bypass the AWB completely and use only the fixed
//                   I_wb_*_trim values. Kept as an option, but those trims
//                   are a guess, they cannot be tuned on the board (the key
//                   pins are unreliable), and the 0.75x~1.50x range limits
//                   the R/G correction to about 2x, which may not be enough
//                   to cancel the sensor's native green response.
//
// Currently enabled: lock-after-converge.
// Usage: power on with the target NOT filling the frame (a normal view is
// fine). The gains freeze about 2 s later and then stop responding to
// anything in the scene. To re-converge after a lighting change, power
// cycle the board.
//
// Why this matters for the colour detector (2026-10-05):
//   A live grey-world AWB keeps moving its R/B gains as the scene average
//   changes. Sliding a colour block in and out of the frame changes that
//   average a lot, so the balance swings every time -- and because this
//   sensor's native green is far stronger than R/B, the residual green bias
//   swings with it. The detector downstream then sees green cross its
//   threshold on neutral surfaces, i.e. boxes in a colour that is not in the
//   scene, flickering as the block moves. Freezing the gains after the
//   ambient has been measured removes that whole mechanism.
// 2026-10-07: 按用户要求**回到原厂的纯灰世界 + 全画面统计**。改为 0 = 不做锁定/
// 跟随, R/B 增益直接用当帧的全画面灰世界估计(和原厂 awb.v 行为一致)。
localparam        WB_LOCK_EN       = 1'b0;
localparam [15:0] WB_LOCK_FRAMES   = 16'd60;    // about 1 second at 60 fps
// Sanity bounds for the AWB's R/B gains (Q16).
//
// These must NOT be tight. A CMOS sensor with a Bayer CFA outputs green much
// stronger than red/blue, so the AWB's job is to RAISE R and B; the gains it
// computes are typically 1.5x~3x. The previous 0.75x~1.50x window clipped
// exactly that correction, which showed up as an overall green cast.
//
// The AWB's internal path already saturates at 16x, so these are only a
// backstop against a pathological estimate. Keep them well clear of the
// normal range: 0.25x ~ 4.0x never binds in practice.
localparam [19:0] WB_GAIN_MIN      = 20'h00001; // ~0, no practical lower bound
localparam [19:0] WB_GAIN_MAX      = 20'hFFFFF; // 16x, same guard the vendor used
// ---- 诊断开关 (2026-10-07): 旁路 AWB, 用来定位"画面一片紫色" ----
//
// 现象: 画面里有一块实心的紫色区域, 且在 AWB 增益施加改成"三通道同比例缩放"
// (修掉逐通道削顶) 之后**依然存在**。所以紫块不是削顶来的。
//
// 紫 = R 和 B 偏高, G 偏低。显示端那三个暖色修正函数是 R×1.0625 / G×0.969 /
// B×0.9375 —— 往暖(红)偏, 而且只有 6%, 做不出紫色。所以嫌疑在 AWB:
// 它算的是**全画面**的增益, 某块区域的原始颜色跟全画面平均不一样时(亮区、
// 窗户、反光面、镜头色阴影), 同一个全局增益在那块就过量 -> 那块偏色。
//
// 置 1 则完全旁路 AWB (R/B 增益恒 1.0, 与 G 相同), 画面会整体偏绿(传感器原生
// 绿强), 但应当是**均匀**的:
//   紫块消失 -> 确认是 AWB 全局增益在局部过量
//   紫块还在 -> 与 AWB 无关, 在更上游
// 定位完改回 1'b0。
localparam        FIXED_WB_ONLY    = 1'b0;  // 诊断开关, 定位完保持 0

/*****************************************************************
                          RGB565?RGB888                                        
*****************************************************************/

    // //RGB565??????888
    // wire [4:0]  rgb565_r   = I_st_data[11+:5];
    // wire [5:0]  rgb565_g   = I_st_data[5+:6];
    // wire [4:0]  rgb565_b   = I_st_data[0+:5];
    
    // wire [23:0] rgb888     = {{rgb565_r[4:0],rgb565_r[2:0]},{rgb565_g[5:0],rgb565_g[1:0]},{rgb565_b[4:0],rgb565_b[2:0]}};
    
    // wire [7:0]  rgb888_r   = rgb888[16+:8];
    // wire [7:0]  rgb888_g   = rgb888[8+:8] ;
    // wire [7:0]  rgb888_b   = rgb888[0+:8] ;
    
  /*****************************************************************
                          ????                                        
*****************************************************************/


  reg         I_tvalid_r0,I_tvalid_r1;
  reg  [95:0] I_tdata_d0,I_tdata_d1;


  //??RGB??????
  reg  [31:0]         sum_r[0:3];
  reg  [31:0]         sum_g[0:3];
  reg  [31:0]         sum_b[0:3];

  
  wire  [95:0]        data_d0 ;
  wire                valid_d0;
  wire                I_tuser_r0;    

  reg                 I_tuser_r1;

  reg   [95:0]        data_d1 ;
  reg                 valid_d1;
  reg   [9:0]         rgb_sum[0:3];//?????RGB??
  /*****************************************************************
                            ???????                                      
*****************************************************************/

// ????????????????????
always @(posedge I_clk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        I_tdata_d0  <= 0;
        I_tdata_d1  <= 0;
        {I_tvalid_r0,I_tvalid_r1} <= 0;
    end else begin
        I_tdata_d0  <= I_tdata   ;
        I_tdata_d1  <= I_tdata_d0;
        I_tvalid_r0 <= I_tvalid;
        I_tvalid_r1 <= I_tvalid_r0;
    end
end

// ????????4????RGB??
wire [7:0] rgb888_r_d[0:3];
wire [7:0] rgb888_g_d[0:3];
wire [7:0] rgb888_b_d[0:3];

assign  rgb888_r_d[0] = I_tdata[16+:8];
assign  rgb888_g_d[0] = I_tdata[8+:8];
assign  rgb888_b_d[0] = I_tdata[0+:8];


// ????????4????RGB??
wire [7:0] rgb888_r_d0[0:3];
wire [7:0] rgb888_g_d0[0:3];
wire [7:0] rgb888_b_d0[0:3];

assign  rgb888_r_d0[0] = I_tdata_d0[16+:8];
assign  rgb888_g_d0[0] = I_tdata_d0[8+:8];
assign  rgb888_b_d0[0] = I_tdata_d0[0+:8];


        ///????
        always @(posedge I_clk or negedge I_rst_n) begin
            if(!I_rst_n) begin
                rgb_sum[0] <= 0;
            end
            else if(I_tvalid)begin
                rgb_sum[0] <= rgb888_r_d[0] + rgb888_g_d[0] + rgb888_b_d[0];
            end
        end

        // ???????????????????
        //
        // ---- 白点检测: 统计只采信"看起来接近中性"的像素 ------------------
        //
        // 灰世界的前提是"整幅画面的平均是灰的"。这个前提在有大面积单色目标时
        // 不成立, 而且后果比"估计不准"更严重: AWB 会持续去补偿目标本身, 直到
        // 目标不再是那个颜色 —— 于是下游的颜色检测器再也认不出它。
        //
        // 做法是让像素同时满足三条才进统计:
        //   1) 不饱和 : 三通道都 < 240。过曝像素的颜色不可信(通道被削平)。
        //   2) 不太暗 : 最暗通道 >= WB_DARK_TH。暗部由噪声主导, 噪声会把色度
        //               随机拉开, 采信它们等于把噪声灌进估计。
        //   3) 色度低 : max-min <= WB_CHROMA_TH, 也就是"看起来接近灰/白"。
        //               这是关键的一条 —— 高饱和目标(一块绿布 max-min 常在
        //               100 以上)被挡在统计之外, AWB 只根据场景里的中性表面
        //               估计光源, 不会去中和目标。
        //
        // 门限不能卡太紧: 暖光下的白墙本身就偏黄(r>g>b), 色度也有几十。卡太死
        // 会把"白"也排除掉, 那就没像素可统计了, 估计反而更差。
        //
        // 这一条和上面的慢速跟随(WB_TRACK_SHIFT)是配套的: 万一某帧合格像素太少
        // 导致估计变差, 每帧只走 1/64 的跟随速度会把它的影响压下去。
        localparam [7:0] WB_DARK_TH   = 8'd32;  // 最暗通道下限, 排除暗部噪声
        // 色度门限改成相对判据了, 不再是固定常数 —— 原因见下面 S_stat_ok 处。

        wire [7:0] S_stat_r = rgb888_r_d0[0];
        wire [7:0] S_stat_g = rgb888_g_d0[0];
        wire [7:0] S_stat_b = rgb888_b_d0[0];
        wire [7:0] S_stat_max = (S_stat_r > S_stat_g) ? ((S_stat_r > S_stat_b) ? S_stat_r : S_stat_b)
                                                      : ((S_stat_g > S_stat_b) ? S_stat_g : S_stat_b);
        wire [7:0] S_stat_min = (S_stat_r < S_stat_g) ? ((S_stat_r < S_stat_b) ? S_stat_r : S_stat_b)
                                                      : ((S_stat_g < S_stat_b) ? S_stat_g : S_stat_b);
        wire [7:0] S_stat_chroma = S_stat_max - S_stat_min;
        wire [9:0] S_stat_sum    = {2'b0,S_stat_r} + {2'b0,S_stat_g} + {2'b0,S_stat_b};
        wire [9:0]  S_stat_chroma3 = {S_stat_chroma, 1'b0} + S_stat_chroma;   // chroma * 3

        // ★ 色度判据必须是相对值, 不能是绝对值。
        //
        // 原来写的是 "max-min <= 80"。80 是固定的 8 位数值, 但色度跟着信号幅度走:
        // 曝光或增益一翻倍, 同一个表面的色度也翻倍, 原来合格的像素就整片被排除,
        // AWB 的统计对象悄悄换了一批 —— 表现就是"把亮度目标调高之后颜色识别变得
        // 不稳"。在 8 倍模拟增益加数字提亮的链路上尤其明显。
        //
        // 改成和像素自身亮度成比例: chroma * 6 <= (R+G+B), 即色度不超过三通道平均的
        // 50%。这样门限与曝光/增益完全无关 —— 和颜色判据那边把固定余量改成相对
        // 余量是同一个道理。
        // ★ 门限从 240 放到 252 (2026-10-05)。
        //
        // 原来写 "< 240" 是想排除过曝像素 —— 削顶的像素颜色不可信, 这个出发点
        // 没错, 但 240 这个值太狠了: 它把"很亮但没有削顶"的中性表面也一并排除。
        // 而亮的中性表面(白墙、天花板、白纸)恰恰是最可靠的白点参考。
        //
        // 后果实测就是这样: 白色的天花板最亮, 被排除在统计之外 -> AWB 只按房间
        // 里偏暗偏暖的部分估计 -> 算出"抬高 B"的补偿 -> 增益是全局施加的, 天花板
        // 照样吃到这个 B -> 本该中性的天花板发蓝 -> 蓝色检测器把它认成目标。
        //
        // 放到 252: 只排除真正削顶(255 附近)的像素, 亮的中性表面重新参与统计。
        localparam [7:0] WB_SAT_TH = 8'd252;

        // ---- 空间均匀采样 (2026-10-05) -------------------------------------
        // 原来的统计是"像素合格就累加", 于是画面里合格像素多的区域(通常是中间亮区)
        // 会主导估计 —— AWB 就只把那一块调成中性, 其余区域带残余色偏, 表现就是
        // 空间性的色差。官方例程用纯灰世界全画面统计, 没有这个问题(代价是彩色目标
        // 一进画面它就跑偏)。
        //
        // 这里保留白点筛选, 但把采样改成空间均匀: 每 32x16 像素的格子最多贡献一个
        // 样本, 各区域权重相同, 不管哪个区域亮、哪个区域合格像素多。
        // 每帧约 40x45 = 1800 个样本, 对均值估计足够。
        reg [2:0]  S_awb_x;    // 0..7   拍计数 (8 拍 = 32 像素)
        reg [3:0]  S_awb_y;    // 0..15  行计数
        always @(posedge I_clk or negedge I_rst_n) begin
            if (!I_rst_n || I_tuser) begin
                S_awb_x <= 3'd0;
                S_awb_y <= 4'd0;
            end else if (I_tvalid) begin
                S_awb_x <= (S_awb_x == 3'd7) ? 3'd0 : (S_awb_x + 3'd1);
                if (S_awb_x == 3'd7)
                    S_awb_y <= (S_awb_y == 4'd15) ? 4'd0 : (S_awb_y + 4'd1);
            end
        end
        wire S_awb_samp = (S_awb_x == 3'd0) && (S_awb_y == 4'd0);

        // ---- 去掉饱和度门限 (2026-10-05, 第二次修正) ----------------------
        //
        // 原来这里有一条 "三通道都 < WB_SAT_TH" 的上限, 想排除过曝像素。
        // 先把它从 240 放到 252 —— 没用。原因现在看清楚了:
        // 一块很亮的天花板经过数字提亮后**已经被硬截断到 255**, 240 和 252 对它
        // 没有区别, 两头都进不了统计。于是 AWB 只按画面里其余部分(室内暖色)算增益,
        // 抬 B 去中和它们; 而增益是全局施加的, 天花板照样吃到这个 B -> 发蓝 ->
        // 蓝色检测器把它认成目标。
        //
        // 关键在于: **削顶的白色像素 (255,255,255) 恰恰是最可靠的白点参考。**
        // 而排除饱和像素本来是想防"彩色物体污染估计" —— 但那个目的色度判据
        // (chroma*6 <= R+G+B) 已经达成了: 饱和红 (255,60,55) 的 chroma=200,
        // sum=370, 200*6=1200 > 370, 早就被挡在外面。
        // 所以饱和度门限是冗余的, 它唯一的作用就是把最白的参考点排除掉。
        // 直接删掉。
        //
        // 现在只剩两道判据: 不太暗(排除噪声主导的暗部) + 色度低(排除彩色目标)。
        // ★ 2026-10-07 (第二次): 按用户要求**改回原厂的判据** —— 纯灰世界、全画面统计,
        // 只排除极亮的像素。原厂 awb.v 第 136 行就是:
        //     end else if (I_tvalid_r0 && (rgb_sum[0] < 720)) begin
        // 没有色度门限、没有暗部门限、没有空间采样、没有锁定。
        //
        // 为什么回退: 原厂这套在官方例程(lab3_osd_720p)里是验证过能用的, 而我们
        // 自己加的那几道门限反而引入了 bug —— 色度门限把天生偏绿的原始像素挡在统计
        // 之外, 导致 AWB 补偿不足、整幅发绿。少一层自作聪明的筛选, 少一类错误。
        //
        // 代价要知道: 灰世界按"全画面平均"估计光源, 画面里出现大色块时会被带偏 ——
        // 这正是用户最开始报的"拿红纸出来周围颜色变化"。测光(自动亮度)那边已经用
        // "只采信中性像素"解决了同类问题; 白平衡这边先按用户要求回原厂。如果色块
        // 干扰又变明显, 再考虑给统计加中性筛选 —— 但注意门限必须放到 100%,
        // 因为原始数据天生偏绿(色度/平均 ≈ 50%)。
        wire       S_stat_ok = (S_stat_sum < 10'd720);

        always @(posedge I_clk or negedge I_rst_n) begin
            if (!I_rst_n || I_tuser) begin
                // ?????????????????
                sum_r[0] <= 1;
                sum_g[0] <= 1;
                sum_b[0] <= 1;
            end else if (I_tvalid_r0 && S_stat_ok) begin
                // ?????????RGB????
                sum_r[0] <= sum_r[0] + S_stat_r;
                sum_g[0] <= sum_g[0] + S_stat_g;
                sum_b[0] <= sum_b[0] + S_stat_b;
            end
        end

  /*****************************************************************
                           ????                                       
*****************************************************************/

  wire [47:0] S_div_quotient;
  wire        S_div_done;
  reg         S_div_sel;
  reg  [49:0] S_div_sel_pipe;

  // The generated divider accepts one request per clock and has an exact
  // 50-cycle start-to-done pipeline. Alternate R and B requests so one IP
  // replaces two identical dividers without changing either division formula.
  always @(posedge I_clk or negedge I_rst_n) begin
      if (!I_rst_n) begin
          S_div_sel      <= 1'b0;
          S_div_sel_pipe <= 50'd0;
      end else begin
          S_div_sel_pipe <= {S_div_sel_pipe[48:0], S_div_sel};
          if (I_tvalid_r1)
              S_div_sel <= ~S_div_sel;
      end
  end



/*****************************************************************
                   IP ??                                    
*****************************************************************/
    //??????????????????

      divider div_gen_G_RB_r1 (
          .clk(I_clk),  // input wire aclk
          .rst(!I_rst_n),
          .start(I_tvalid_r1),
          .denominator(S_div_sel ? sum_b[0] : sum_r[0]),
          .numerator({sum_g[0],16'd0}),  // input wire [47 : 0] s_axis_dividend_tdata
          .quotient(S_div_quotient),
          .done(S_div_done)
      );

     
    signal_delay #(
        .IMG_HEIGHT   (IMG_HEIGHT),
        .IMG_WIDTH    (IMG_WIDTH ),
        .DATA_WIDTH   (96  ),
        .DELAY_CYCLE  (50)
    )signal_delay_d (
        /*input                       */ .I_clk  (I_clk  ),
        /*input                       */ .I_rst_n(I_rst_n),
        /*input                       */ .I_tuser(I_tuser),  //synthesis keep 
        /*input  wire                 */ .I_valid(I_tvalid_r1),  //synthesis keep 
        /*input  wire [DATA_WIDTH-1:0]*/ .I_data (I_tdata_d1 ),   //synthesis keep 
        /*output wire                 */ .O_valid(valid_d0   ),  //synthesis keep 
        /*output wire [DATA_WIDTH-1:0]*/ .O_data (data_d0    ),   //synthesis keep 
        /*output wire                 */ .O_tuser(I_tuser_r0 )
    );

    

/*****************************************************************
                            ????????                                      
*****************************************************************/

    reg  [19:0]   in_r_r1;
    reg  [19:0]   in_b_r1;
    always @(posedge I_clk or negedge I_rst_n)begin 
        if(!I_rst_n || I_tuser)begin
            in_r_r1 <= 20'h10000;
            in_b_r1 <= 20'h10000;
        end
        else if(S_div_done)begin
            if(!S_div_sel_pipe[49]) begin
                if(|S_div_quotient[47:20])
                    in_r_r1 <= 20'hfffff;
                else
                    in_r_r1 <= S_div_quotient[19:0];
            end else begin
                if(|S_div_quotient[47:20])
                    in_b_r1 <= 20'hfffff;
                else
                    in_b_r1 <= S_div_quotient[19:0];
            end
        end
    end


    ////????
    always @(posedge I_clk or negedge I_rst_n) begin
      if (!I_rst_n) begin
          valid_d1 <= 0;
          data_d1  <= 0;
          I_tuser_r1 <= 0;
      end else begin
          valid_d1 <= valid_d0;
          data_d1  <= data_d0 ;
          I_tuser_r1 <= I_tuser_r0;
      end
    end
/*****************************************************************
                           ????????                                       
*****************************************************************/

    reg [27:0] R_new_r1;
    reg [27:0] G_new_r1;
    reg [27:0] B_new_r1;

    reg [27:0] R_new_r2;
    reg [27:0] G_new_r2;
    reg [27:0] B_new_r2;

    reg [27:0] R_new_r3;
    reg [27:0] G_new_r3;
    reg [27:0] B_new_r3;

    reg [27:0] R_new_r4;
    reg [27:0] G_new_r4;
    reg [27:0] B_new_r4;


    wire   [7:0] rgb888_r_d1[0:3];
    wire   [7:0] rgb888_g_d1[0:3];
    wire   [7:0] rgb888_b_d1[0:3];

    assign  rgb888_r_d1[0] = data_d1[16+:8];
    assign  rgb888_g_d1[0] = data_d1[8+:8];
    assign  rgb888_b_d1[0] = data_d1[0+:8];

    assign  rgb888_r_d1[1] = data_d1[40+:8];
    assign  rgb888_g_d1[1] = data_d1[32+:8];
    assign  rgb888_b_d1[1] = data_d1[24+:8];

    assign  rgb888_r_d1[2] = data_d1[64+:8];
    assign  rgb888_g_d1[2] = data_d1[56+:8];
    assign  rgb888_b_d1[2] = data_d1[48+:8];

    assign  rgb888_r_d1[3] = data_d1[88+:8];
    assign  rgb888_g_d1[3] = data_d1[80+:8];
    assign  rgb888_b_d1[3] = data_d1[72+:8];

    function [19:0] wb_gain_clip;
        input [19:0] gain;
        begin
            if (gain < WB_GAIN_MIN)
                wb_gain_clip = WB_GAIN_MIN;
            else if (gain > WB_GAIN_MAX)
                wb_gain_clip = WB_GAIN_MAX;
            else
                wb_gain_clip = gain;
        end
    endfunction

    wire S_frame_start = I_tuser;
    reg [15:0] S_wb_frame_cnt;
    reg        S_wb_locked;
    reg        S_wb_lock_armed;
    reg [19:0] S_R_wb_lock;
    reg [19:0] S_B_wb_lock;
    wire [19:0] S_R_wb_live = wb_gain_clip(in_r_r1);
    wire [19:0] S_B_wb_live = wb_gain_clip(in_b_r1);
    wire [19:0] S_R_wb_use  = FIXED_WB_ONLY ? 20'h10000 : ((WB_LOCK_EN && S_wb_locked) ? S_R_wb_lock : S_R_wb_live);
    wire [19:0] S_B_wb_use  = FIXED_WB_ONLY ? 20'h10000 : ((WB_LOCK_EN && S_wb_locked) ? S_B_wb_lock : S_B_wb_live);
    wire [39:0] S_R_wb_trim_full = S_R_wb_use * I_wb_r_trim;
    wire [39:0] S_G_wb_trim_full = 20'h10000 * I_wb_g_trim;
    wire [39:0] S_B_wb_trim_full = S_B_wb_use * I_wb_b_trim;
    wire [19:0] S_R_wb_trim = (|S_R_wb_trim_full[39:36]) ? 20'hfffff : S_R_wb_trim_full[35:16];
    wire [19:0] S_G_wb_trim = (|S_G_wb_trim_full[39:36]) ? 20'hfffff : S_G_wb_trim_full[35:16];
    wire [19:0] S_B_wb_trim = (|S_B_wb_trim_full[39:36]) ? 20'hfffff : S_B_wb_trim_full[35:16];

    // ---- 增益跟随方式: 慢速低通, 不是硬冻结 --------------------------------
    //
    // in_r_r1/in_b_r1 是"每帧从头重算"的灰世界估计 (上面那个 always 里, 每帧
    // I_tuser 把它复位回 1.0, 再由当帧统计重新算出)。所以它们是逐帧独立的估计,
    // 不是一个带时间常数的累积量。
    //
    // 硬冻结 = 把某一帧的估计永久钉住。那一帧内容但凡不典型 (上电时画面里有暖色
    // 区域, 或者某个色块正占着画面), 偏差就永久留在画面上 —— 实测表现就是整幅
    // 画面固定偏色。改成每帧朝当帧估计靠 1/2^WB_TRACK_SHIFT:
    //   - 收敛到长期平均, 按灰世界定义就是中性 -> 不残留固定色偏
    //   - 逐帧估计的噪声被压掉 1/64 -> 下游检测器看到的平衡足够稳定
    // 两者兼得, 而且上电时机的敏感度大大降低。
    // ---- 时间常数分两档: 先快收敛, 后极慢跟随 ------------------------------
    //   收敛期 1/16  每帧 (τ ≈ 16 帧 ≈ 0.27 秒)
    //   收敛后 1/256 每帧 (τ ≈ 256 帧 ≈ 4.3 秒) —— 实际等同于锁定
    //
    // 为什么依然不用硬冻结: 上一版试过硬冻结, 它把一个错误的平衡永久钉死了,
    // 画面固定偏蓝, 只能断电重来。慢到 4 秒的效果和"锁定"一样, 但万一锁偏了
    // 还能自己慢慢走回来。配合白点筛选(统计里只要接近白/灰的像素), 红纸进出
    // 画面也不会把统计带偏。
    localparam WB_TRACK_FAST    = 4;
    localparam WB_TRACK_SLOW    = 8;
    localparam [15:0] WB_SETTLE_FRAMES = 16'd90;   // 快收敛持续约 1.5 秒

    reg        S_wb_settled;
    reg [20:0] S_R_delta, S_B_delta;
    reg [20:0] S_R_next,  S_B_next;

    wire [3:0] WB_TRACK_SHIFT = S_wb_settled ? WB_TRACK_SLOW : WB_TRACK_FAST;

    always @(*) begin
        if (S_R_wb_live >= S_R_wb_lock) begin
            S_R_delta = {1'b0, S_R_wb_live} - {1'b0, S_R_wb_lock};
            S_R_next  = {1'b0, S_R_wb_lock} + (S_R_delta >> WB_TRACK_SHIFT);
        end else begin
            S_R_delta = {1'b0, S_R_wb_lock} - {1'b0, S_R_wb_live};
            S_R_next  = {1'b0, S_R_wb_lock} - (S_R_delta >> WB_TRACK_SHIFT);
        end

        if (S_B_wb_live >= S_B_wb_lock) begin
            S_B_delta = {1'b0, S_B_wb_live} - {1'b0, S_B_wb_lock};
            S_B_next  = {1'b0, S_B_wb_lock} + (S_B_delta >> WB_TRACK_SHIFT);
        end else begin
            S_B_delta = {1'b0, S_B_wb_lock} - {1'b0, S_B_wb_live};
            S_B_next  = {1'b0, S_B_wb_lock} - (S_B_delta >> WB_TRACK_SHIFT);
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_wb_frame_cnt <= 16'd0;
            S_wb_locked    <= 1'b0;
            S_wb_lock_armed <= 1'b0;
            S_wb_settled   <= 1'b0;
            S_R_wb_lock    <= 20'h10000;
            S_B_wb_lock    <= 20'h10000;
        end else if (!WB_LOCK_EN) begin
            S_wb_frame_cnt  <= 16'd0;
            S_wb_locked     <= 1'b0;
            S_wb_lock_armed <= 1'b0;
            S_wb_settled    <= 1'b0;
            S_R_wb_lock     <= 20'h10000;
            S_B_wb_lock     <= 20'h10000;
        end else if (S_frame_start) begin
            // 只在帧边界动作: in_*_r1 在 I_tuser 那一拍仍是上一帧累积完的值
            // (复位赋值要下一拍才生效), 所以这里是唯一能读到完整估计的时刻。
            if (!S_wb_lock_armed) begin
                // 预热期: 画面暂时还用当帧估计, 等场景稳定
                if (S_wb_frame_cnt >= WB_LOCK_FRAMES) begin
                    S_wb_lock_armed <= 1'b1;
                    S_wb_locked     <= 1'b1;
                    S_wb_frame_cnt  <= 16'd0;      // 重新计数, 用于判快收敛何时结束
                    S_R_wb_lock     <= S_R_wb_live; // 起点
                    S_B_wb_lock     <= S_B_wb_live;
                end else
                    S_wb_frame_cnt <= S_wb_frame_cnt + 16'd1;
            end else begin
                // 收敛期/锁定: 朝当帧估计靠, 步长由 WB_TRACK_SHIFT 决定
                S_R_wb_lock <= (S_R_next > {1'b0, WB_GAIN_MAX}) ? WB_GAIN_MAX : S_R_next[19:0];
                S_B_wb_lock <= (S_B_next > {1'b0, WB_GAIN_MAX}) ? WB_GAIN_MAX : S_B_next[19:0];

                if (!S_wb_settled) begin
                    if (S_wb_frame_cnt >= WB_SETTLE_FRAMES)
                        S_wb_settled <= 1'b1;      // 之后切到极慢跟随, 等同锁定
                    else
                        S_wb_frame_cnt <= S_wb_frame_cnt + 16'd1;
                end
            end
        end
    end

    // Restore the reference gray-world gains; fixed unity gains bypassed AWB.
    // Register the combined Q16 gains so the gain multiply is not in the
    // same combinational path as the pixel multiply. Clamp instead of wrap.
    wire [39:0] S_R_gain_full = I_global_gain * S_R_wb_trim;
    wire [39:0] S_G_gain_full = I_global_gain * S_G_wb_trim;
    wire [39:0] S_B_gain_full = I_global_gain * S_B_wb_trim;
    reg [19:0] S_R_gain;
    reg [19:0] S_G_gain;
    reg [19:0] S_B_gain;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_R_gain <= 20'h10000;
            S_G_gain <= 20'h10000;
            S_B_gain <= 20'h10000;
        end else begin
            S_R_gain <= (|S_R_gain_full[39:36]) ? 20'hfffff : S_R_gain_full[35:16];
            S_G_gain <= (|S_G_gain_full[39:36]) ? 20'hfffff : S_G_gain_full[35:16];
            S_B_gain <= (|S_B_gain_full[39:36]) ? 20'hfffff : S_B_gain_full[35:16];
        end
    end

    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            R_new_r1 <= 0;
            G_new_r1 <= 0;
            B_new_r1 <= 0;

            R_new_r2 <= 0;
            G_new_r2 <= 0;
            B_new_r2 <= 0;

            R_new_r3 <= 0;
            G_new_r3 <= 0;
            B_new_r3 <= 0;

            R_new_r4 <= 0;
            G_new_r4 <= 0;
            B_new_r4 <= 0;
        end
        else if(valid_d1) begin
            R_new_r1 <= {20'd0, rgb888_r_d1[0]} * S_R_gain;
            G_new_r1 <= {20'd0, rgb888_g_d1[0]} * S_G_gain;
            B_new_r1 <= {20'd0, rgb888_b_d1[0]} * S_B_gain;

            R_new_r2 <= {20'd0, rgb888_r_d1[1]} * S_R_gain;
            G_new_r2 <= {20'd0, rgb888_g_d1[1]} * S_G_gain;
            B_new_r2 <= {20'd0, rgb888_b_d1[1]} * S_B_gain;

            R_new_r3 <= {20'd0, rgb888_r_d1[2]} * S_R_gain;
            G_new_r3 <= {20'd0, rgb888_g_d1[2]} * S_G_gain;
            B_new_r3 <= {20'd0, rgb888_b_d1[2]} * S_B_gain;

            R_new_r4 <= {20'd0, rgb888_r_d1[3]} * S_R_gain;
            G_new_r4 <= {20'd0, rgb888_g_d1[3]} * S_G_gain;
            B_new_r4 <= {20'd0, rgb888_b_d1[3]} * S_B_gain;
        end
    end

/*****************************************************************
                            ??????????                                      
*****************************************************************/

    wire [7:0] R_new_x1;
    wire [7:0] G_new_x1;
    wire [7:0] B_new_x1;

    wire [7:0] R_new_x2;
    wire [7:0] G_new_x2;
    wire [7:0] B_new_x2;

    wire [7:0] R_new_x3;
    wire [7:0] G_new_x3;
    wire [7:0] B_new_x3;

    wire [7:0] R_new_x4;
    wire [7:0] G_new_x4;
    wire [7:0] B_new_x4;

    // ---- 白平衡增益施加 (2026-10-07 第二次修正) ---------------------------
    //
    // 这里修了三轮, 前两轮都是错的, 记下来免得再犯:
    //
    // 原厂: 哪个通道溢出就单独削到 255。三个通道增益不一样大(G 恒为 1.0, 从不
    //   缩放, 而 R/B 被抬到 1.5~2.5 倍), 于是亮的中性区域 R、B 先被推过 255 削平、
    //   G 不削 -> (255, G, 255) -> 一整块亮区变成紫/品红。
    //
    // 上一版: 三通道一起右移同样的位数(比例严格保持)。比例是对了, 但**右移是 2 的
    //   幂** —— 跨过溢出阈值时亮度整档跳变(最多差一倍), 相邻像素有的移位有的不移,
    //   最亮的地方就变成一片花屏。等于把"色块"换成了"花屏"。
    //
    // 现在: 任一通道溢出就把三个通道**一起置成其中的最大值**(上限 255), 也就是
    //   "高光冲向白"。这是真实相机的行为 —— 过曝的高光就是白的, 不是彩色的。
    //   纯比较器 + mux, 不占乘法器, 也不需要除法器。
    //
    // 它同时治两件事: 亮区花屏(颜色对了), 以及高光被判成蓝色(高光不再有 b 明显
    // 大于 r 的畸变, 而 is_blue 要 b 比 r/g 高 25% 才通过)。
    //
    // 副作用: 高光区会比正确曝光略白/略亮 —— 但那本来就是过曝区, 丢的是细节不是颜色。
    function [11:0] wb_max3;
        input [11:0] a, b, c;
        reg   [11:0] m;
        begin
            m = (a > b) ? a : b;
            wb_max3 = (m > c) ? m : c;
        end
    endfunction

    function [7:0] wb_hi;          // 溢出时的统一输出: 压到 255
        input [11:0] m;
        begin
            wb_hi = (m > 12'd255) ? 8'hff : m[7:0];
        end
    endfunction

    wire [11:0] mx1 = wb_max3(R_new_r1[27:16], G_new_r1[27:16], B_new_r1[27:16]);
    wire [11:0] mx2 = wb_max3(R_new_r2[27:16], G_new_r2[27:16], B_new_r2[27:16]);
    wire [11:0] mx3 = wb_max3(R_new_r3[27:16], G_new_r3[27:16], B_new_r3[27:16]);
    wire [11:0] mx4 = wb_max3(R_new_r4[27:16], G_new_r4[27:16], B_new_r4[27:16]);

    assign R_new_x1 = (mx1 > 12'd255) ? wb_hi(mx1) : R_new_r1[23:16];
    assign G_new_x1 = (mx1 > 12'd255) ? wb_hi(mx1) : G_new_r1[23:16];
    assign B_new_x1 = (mx1 > 12'd255) ? wb_hi(mx1) : B_new_r1[23:16];

    assign R_new_x2 = (mx2 > 12'd255) ? wb_hi(mx2) : R_new_r2[23:16];
    assign G_new_x2 = (mx2 > 12'd255) ? wb_hi(mx2) : G_new_r2[23:16];
    assign B_new_x2 = (mx2 > 12'd255) ? wb_hi(mx2) : B_new_r2[23:16];

    assign R_new_x3 = (mx3 > 12'd255) ? wb_hi(mx3) : R_new_r3[23:16];
    assign G_new_x3 = (mx3 > 12'd255) ? wb_hi(mx3) : G_new_r3[23:16];
    assign B_new_x3 = (mx3 > 12'd255) ? wb_hi(mx3) : B_new_r3[23:16];

    assign R_new_x4 = (mx4 > 12'd255) ? wb_hi(mx4) : R_new_r4[23:16];
    assign G_new_x4 = (mx4 > 12'd255) ? wb_hi(mx4) : G_new_r4[23:16];
    assign B_new_x4 = (mx4 > 12'd255) ? wb_hi(mx4) : B_new_r4[23:16];
/*****************************************************************
                           ??????                                       
*****************************************************************/

    reg valid_d2,I_tuser_r2;
    reg [95:0] raw_tdata_d2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)begin
            valid_d2 <= 0;
            I_tuser_r2 <= 0;
            raw_tdata_d2 <= 96'd0;
        end
        else begin
            valid_d2 <= valid_d1;
            I_tuser_r2 <= I_tuser_r1;
            raw_tdata_d2 <= data_d1;
        end
    end


    assign  O_tlast  = (valid_d1 == 0) && (valid_d2 == 1);   
    assign  O_tuser  = I_tuser ;   
    assign  O_tvalid = valid_d2;
    assign  O_raw_tdata = O_tvalid ? raw_tdata_d2 : 96'd0;

    assign  O_tdata = O_tvalid?{R_new_x4,G_new_x4,B_new_x4,
                       R_new_x3,G_new_x3,B_new_x3,
                       R_new_x2,G_new_x2,B_new_x2,
                       R_new_x1,G_new_x1,B_new_x1}:0;
    // assign O_t_data = {R_new[7-:5],G_new[7-:6],B_new[7-:5]};
    assign  I_tready = O_tready;
 
endmodule





