module hdmi_mixer #(
    parameter H_OFFSET = 128,
    parameter V_OFFSET = 60,
    parameter IMG_WIDTH = 1280,
    parameter IMG_HEIGHT = 720,
    parameter integer DEBUG_MODE = 0
)(
    input wire        I_clk,
    input wire        I_rst_n,

    // OSD 总开关 (顶层接 I_button[1] = 焊球 A9 = KEY2, 低有效按键)。
    // 默认 1 = 显示 —— 赛题基础要求 4 要求输出画面里含"安路"标识 Logo, 所以上电
    // 必须带着; 按键是用来"一键清屏"看干净画面的, 不是反过来。
    // 2026-10-10: 它现在**同时门控 Logo 图标和 "安路 CNT: N" 文字** —— 按键要求
    // 两者一起消失。
    input wire        I_logo_en,

    // 当前显示模式 (2026-10-10, 2026-10-12 扩成 5 种), 用来在画面上显示"当前算法状态"。
    // 这个值在 ISP 域产生(按键驱动), 这里是 HDMI 域 —— 顶层负责把它同步过来,
    // 本模块只做展示。只在按键时变, 不需要额外的握手。
    //   0=原图 1=边缘 2=卡通 3=跟踪 4=运动检测
    input wire [2:0]  I_mode,
    input wire [15:0] I_ae_exp,
    input wire [7:0]  I_ae_gain,

    // 运动切片计数 (2026-10-12), 从 ISP 域同步过来。
    // ★ 它是 **BCD** —— 4 个十进制数字 {千,百,十,个}, ISP 域是边计数边进位的,
    //   所以这里**不需要任何进制转换器**, 直接拿去做字形就行。
    //   (原来这里挂着一个 Double Dabble 二进制->BCD 转换器, 但它从没被显示过、
    //    也就从没被验证 —— 板上实测转出来是乱码。)
    input wire [15:0] I_mot_cnt,

    // 采集→显示的延迟, 单位**帧** (2026-10-14 新增)。从 ddr 域同步过来,
    // 在 video_in 里算好 —— 帧号真的穿过 4 块帧缓存走了一圈, 不是写死的常数。
    // 详见 video_in.v 末尾那段注释。
    input wire [15:0] I_lat_fid,

    // 三色检测结果 (2026-10-10), 从 ISP 域同步过来。每色 64 位:
    //   [9:0]=bottom [19:10]=top [30:20]=right [41:31]=left [42]=valid
    //   [53:43]=质心x [63:54]=质心y     红=[63:0] 绿=[127:64] 蓝=[191:128]
    // 用途: 在质心画十字(跟踪标识) + 在 OSD 里显示颜色名(文字说明)。
    input wire [191:0] I_det_boxes,

    input wire        I_video_vsync,
    input wire        I_video_hsync,
    input wire        I_video_de,
    input wire        I_video_user,
    input wire        I_video_last,

    input wire[3:0]   I_debug_status,

    output wire       O_video_rd_en,
    input wire[23:0]  I_video_rd_data,

    output reg        O_hdmi_vsync,
    output reg        O_hdmi_hsync,
    output reg        O_hdmi_de,
    output reg[23:0]  O_hdmi_data
);

    reg        S_video_vsync_1d;
    reg        S_video_vsync_2d;
    reg        S_video_hsync_1d;
    reg        S_video_hsync_2d;
    reg        S_video_de_1d;
    reg        S_video_de_2d;
    reg [23:0] S_video_data_1d;
    reg [23:0] S_video_data_2d;
    reg [11:0] S_x;
    reg [11:0] S_y;
    reg [11:0] S_x_1d;
    reg [11:0] S_x_2d;
    reg [11:0] S_y_1d;
    reg [11:0] S_y_2d;

    reg        S_osd_hit;
    // ★ 2026-10-12: 模式值在**显示帧首**锁存 (见下面 S_mode_r 的 always)。
    //   为的是让 OSD 文字和画面的模式切换发生在**同一帧** —— 进阶要求(1) 的
    //   "力求切换平稳"要补的就是这一点。详见 S_mode_r 那段说明。
    reg [2:0]  S_mode_r;
    reg [23:0] S_osd_color;
    reg [3:0]  S_char_idx;
    reg [2:0]  S_char_row;
    reg [2:0]  S_char_col;
    reg [4:0]  S_char_bits;
    reg        S_char_on;
    reg        S_logo_blue_on;
    reg        S_logo_red_on;
    reg [11:0] S_logo_tmp_y;
    reg [3:0]  S_logo_red_band;
    reg [11:0] S_logo_red_x_start;
    reg [11:0] S_logo_red_x_end;
    reg [31:0] S_frame_cnt;
    reg [11:0] S_dyn_x;
    reg [11:0] S_dyn_y;
    reg [3:0]  S_dyn_char;
    reg [2:0]  S_dyn_col;
    reg [2:0]  S_dyn_row;
    reg [4:0]  S_dyn_bits;
    reg        S_dyn_on;
    reg [3:0]  S_dyn_digit_idx;
    reg [11:0] S_dyn_digit_x;
    reg [6:0]  S_dyn_seg;
    reg [3:0]  S_cnt_d0;
    reg [3:0]  S_cnt_d1;
    reg [3:0]  S_cnt_d2;
    reg [3:0]  S_cnt_d3;
    reg [3:0]  S_cnt_d4;
    reg [3:0]  S_cnt_d5;
    reg [2:0]  S_lbl_row;
    reg [2:0]  S_lbl_col;
    reg [1:0]  S_lbl_idx;
    reg [4:0]  S_lbl_bits;
    reg [6:0]  S_lbl_local_x;
    reg [3:0]  S_dyn_dec_digit;
    reg [4:0]  S_cn_local_x;
    reg [4:0]  S_cn_local_y;
    reg [3:0]  S_cn_col;
    reg [3:0]  S_cn_row;
    reg [15:0] S_cn_row_bits;
    reg        S_cn_on;
    reg [9:0]  S_cn_scale_x;
    reg [9:0]  S_cn_scale_y;
    reg [7:0]  S_pf_char;
    reg [4:0]  S_pf_local_x;
    // ★ 2026-10-10: 4 位 -> 7 位。原来 S_dyn_y 最大 23, 减 CN_Y_OFFSET 得 0..21,
    //   4 位装得下。但 OSD 高度从 24 改成 108 之后 S_dyn_y 能到 107, "安路"那块
    //   又只用 (S_pf_local_y < 24) 当"在字形内"的判断 —— **寄存器溢出回绕**会让
    //   y=34/66/98 附近再判定成"在字形内", 于是画面上重复出现好几处"安路"。
    //   加宽后 107-2=105 装得下, 判断自然为假。
    reg [7:0]  S_pf_local_y;
    reg [3:0]  S_pf_col;
    reg [3:0]  S_pf_row;
    wire [15:0] S_pf_row_bits;
    reg        S_pf_on;
    reg [9:0]  S_pf_scale_x;
    reg [9:0]  S_pf_scale_y;

    localparam LOGO_X = 12'd0;
    localparam LOGO_Y = 12'd0;
    localparam LOGO_W = 12'd160;
    localparam LOGO_H = 12'd160;

    localparam COLOR_LOGO_BLUE   = 24'h1f315c;
    localparam COLOR_LOGO_RED    = 24'hec1c2d;
    localparam COLOR_TEXT        = 24'h00e6ff;
    localparam DYN_OSD_X         = 12'd375;
    localparam DYN_OSD_Y         = 12'd120;
    // 2026-10-10: 200 -> 216。原来 x 110..200 那 6 位是帧计数; 现在把 x 52..212
    // 整段改用来显示**当前模式名**("MODE RAW"/"MODE EDGE"/...)。10 个 16 像素宽的
    // 字符需要 160 像素, 从 x=52 起 -> 到 212, 所以宽度要放到 216。
    localparam DYN_OSD_W         = 12'd264;   // 2026-10-10: 216->264, 因为模式名最长是 "MODE CARTOON"(12字符)
    // 2026-10-10: 高度回到 26 (刚好放下"安路"+模式名那一行)。
    // 之前为了放三行颜色名临时放大到 108, 现在颜色名改成"贴在检测框上"的标签,
    // OSD 只剩一行了, 框也收回来。
    localparam DYN_OSD_H         = 12'd90;   // 2026-10-14: 46->68, 再腾出第三行给延迟读数
                                             // (第三行占 y 48..64, 所以高度要到 68)
                                             // 2026-10-12 时是 26->46, 腾出第二行给 "MOT: nnn"
    // 2026-10-10: 原来那行右边是 6 位帧计数, 现在改成显示模式名, 帧计数关掉。
    // 它和模式名用的是同一片区域(x 52..212), 两个都开会重叠着画。
    localparam CNT_DIGITS_EN     = 1'b0;
    localparam CN_Y_OFFSET       = 12'd2;
    localparam COLOR_DYN_TEXT    = 24'hfff200;
    localparam CHAR_AN           = 8'h80;
    localparam CHAR_LU           = 8'h81;
    // 模式名要用的字母。字模在 osd_char_lib.v 里**全都有**, 这里只是给码值起个名。
    localparam CHAR_SP           = 8'h20;   // 空格 (字库里没显式名字, 直接用码值)
    localparam CHAR_A            = 8'h41;
    localparam CHAR_B            = 8'h42;
    localparam CHAR_C            = 8'h43;
    localparam CHAR_D            = 8'h44;
    localparam CHAR_E            = 8'h45;
    localparam CHAR_F            = 8'h46;   // 2026-10-14: 延迟那一行的 "2F" 要用
    localparam CHAR_G            = 8'h47;
    localparam CHAR_I            = 8'h49;   // 2026-10-12: 给 "MOTION" 用
    localparam CHAR_K            = 8'h4b;
    localparam CHAR_L            = 8'h4c;
    localparam CHAR_M            = 8'h4d;
    localparam CHAR_N            = 8'h4e;
    localparam CHAR_O            = 8'h4f;
    localparam CHAR_P            = 8'h50;
    localparam CHAR_R            = 8'h52;
    localparam CHAR_S            = 8'h53;
    localparam CHAR_T            = 8'h54;
    localparam CHAR_U            = 8'h55;
    localparam CHAR_V            = 8'h56;
    localparam CHAR_W            = 8'h57;
    // 2026-10-14: 坐标标注 "X0512 Y0288" 要用。字模库里 A-Z 本来就是齐的
    // (osd_char_lib.v 第 9-34 行), 这里只是补两个本文件没定义过的常量。
    localparam CHAR_X            = 8'h58;
    localparam CHAR_Y            = 8'h59;
    localparam CHAR_0            = 8'h30;
    localparam CHAR_COLON        = 8'h3a;

    // ---- 16 位字形取一位 (2026-10-10) ------------------------------------
    // osd_char_lib 每个字符给出 I_row 那一行的 16 个列像素。原来每一处渲染都写一个
    // 16 分支的 case 把某一位挑出来, 重复了四五遍。新加的渲染统一用这个函数 ——
    // 短, 而且不容易写错。col=0 对应最高位 bits[15]。
    function F_bit16;
        input [15:0] bits;
        input [3:0]  col;
        begin
            F_bit16 = bits[4'd15 - col];
        end
    endfunction

    // ---- 模式名的第 pos 个字符 (2026-10-10) -------------------------------
    // 进阶要求 2.5(1) 要求在画面上"显示当前算法状态", 这就是那块内容。
    // 前 5 个字符是四种模式共用的前缀 "MODE ", 后面拼模式名。
    // 字符码用上面那些 localparam; 空格用 CHAR_SP(0x20,字库按默认分支渲染成空白)。
    // **字模不用新做** —— osd_char_lib.v 里 A-Z 0-9 全都有。
    function [7:0] F_mode_char;
        input [3:0] pos;
        input [2:0] mode;
        reg [7:0] c;
        begin
            case(pos)
                4'd0: c = CHAR_M;
                4'd1: c = CHAR_O;
                4'd2: c = CHAR_D;
                4'd3: c = CHAR_E;
                4'd4: c = CHAR_SP;
                default: begin
                    case(mode)
                        3'd0: c = (pos==4'd5) ? CHAR_R : (pos==4'd6) ? CHAR_A :
                                 (pos==4'd7) ? CHAR_W : CHAR_SP;                       // RAW
                        3'd1: c = (pos==4'd5) ? CHAR_E : (pos==4'd6) ? CHAR_D :
                                 (pos==4'd7) ? CHAR_G : (pos==4'd8) ? CHAR_E : CHAR_SP; // EDGE
                        3'd2: c = (pos==4'd5) ? CHAR_C : (pos==4'd6) ? CHAR_A :
                                 (pos==4'd7) ? CHAR_R : (pos==4'd8) ? CHAR_T :
                                 (pos==4'd9) ? CHAR_O : (pos==4'd10) ? CHAR_O :
                                 (pos==4'd11) ? CHAR_N : CHAR_SP;                      // CARTOON
                        3'd4: c = (pos==4'd5) ? CHAR_M : (pos==4'd6) ? CHAR_O :
                                 (pos==4'd7) ? CHAR_T : (pos==4'd8) ? CHAR_I :
                                 (pos==4'd9) ? CHAR_O : (pos==4'd10) ? CHAR_N : CHAR_SP; // MOTION
                        3'd5: c = (pos==4'd5) ? CHAR_A : (pos==4'd6) ? CHAR_W :
                                 (pos==4'd7) ? CHAR_B : CHAR_SP;                       // AWB demo
                        3'd6: c = (pos==4'd5) ? CHAR_G : (pos==4'd6) ? CHAR_A :
                                 (pos==4'd7) ? CHAR_M : (pos==4'd8) ? CHAR_M :
                                 (pos==4'd9) ? CHAR_A : CHAR_SP;                       // GAMMA demo
                        3'd7: c = (pos==4'd5) ? CHAR_A : (pos==4'd6) ? CHAR_E :
                                 (pos==4'd7) ? CHAR_SP : (pos==4'd8) ? CHAR_L :
                                 (pos==4'd9) ? CHAR_I : (pos==4'd10) ? CHAR_V :
                                 (pos==4'd11) ? CHAR_E : CHAR_SP;                      // AE LIVE
                        default: c = (pos==4'd5) ? CHAR_T : (pos==4'd6) ? CHAR_R :
                                    (pos==4'd7) ? CHAR_A : (pos==4'd8) ? CHAR_C :
                                    (pos==4'd9) ? CHAR_K : CHAR_SP;                    // TRACK (步骤2b/3)
                    endcase
                end
            endcase
            F_mode_char = c;
        end
    endfunction

    // ========================================================================
    // 质心十字标记 + 三色有效位 (2026-10-10)
    //
    // 扩展要求 2.4(2) 要"叠加检测结果", 进阶要求 2.5(2) 要"叠加跟踪标识或坐标信息"
    // —— 这里在每色**质心**画一个白色十字。
    //
    // ★ 时序: HDMI 域只剩 0.108ns, 所以比较器**不能挂在 S_x_2d/S_y_2d 那一级**
    //   (那一级的路径终点就是 O_hdmi_data_reg, 是全局最差路径)。做法是提前一级:
    //   用 S_x_1d/S_y_1d 算, 结果寄存成 S_cross_1d, 到 2d 那一级直接用寄存值 ——
    //   整条比较链都不在 OSD 输出的临界路径上。
    //   十字的四条边界(质心±臂长)是**帧级常量**, 每帧预先算一次存进寄存器,
    //   逐像素只剩比较。
    // ========================================================================
    localparam [11:0] CROSS_ARM = 12'd16;   // 十字臂长(像素)
    localparam [11:0] CROSS_HW  = 12'd1;    // 十字线半宽, 线宽 = 2*HW+1 = 3 像素

    // 每色 8 个边界: 横条的 x 范围/hy 厚度, 竖条的 y 范围/x 厚度
    reg [11:0] S_hx0_r, S_hx1_r, S_hy0_r, S_hy1_r, S_vx0_r, S_vx1_r, S_vy0_r, S_vy1_r;
    reg [11:0] S_hx0_g, S_hx1_g, S_hy0_g, S_hy1_g, S_vx0_g, S_vx1_g, S_vy0_g, S_vy1_g;
    reg [11:0] S_hx0_b, S_hx1_b, S_hy0_b, S_hy1_b, S_vx0_b, S_vx1_b, S_vy0_b, S_vy1_b;
    reg        S_cval_r, S_cval_g, S_cval_b;

    // 从 192 位总线拆出每色的质心与有效位 (每色 64 位, 见端口注释)
    wire        D_v_r = I_det_boxes[ 42];
    wire        D_v_g = I_det_boxes[106];
    wire        D_v_b = I_det_boxes[170];
    wire [11:0] D_cx_r = {1'b0,  I_det_boxes[ 53: 43]};
    wire [11:0] D_cx_g = {1'b0,  I_det_boxes[117:107]};
    wire [11:0] D_cx_b = {1'b0,  I_det_boxes[181:171]};
    wire [11:0] D_cy_r = {2'b0,  I_det_boxes[ 63: 54]};
    wire [11:0] D_cy_g = {2'b0,  I_det_boxes[127:118]};
    wire [11:0] D_cy_b = {2'b0,  I_det_boxes[191:182]};

    // ========================================================================
    // 坐标标注: 选"有效且最大"的那一色 (2026-10-14)
    //
    // 进阶要求 2.5(2)「叠加跟踪标识**或**坐标信息」—— 十字已经满足"跟踪标识",
    // 这里把**数值坐标**也显示出来, 演示更直观。
    //
    // 为什么只显示一个颜色: OSD 那块宽 264 px, 三个坐标(13 字符 x 16 px x 3)挤不下。
    // 演示时手里通常就一个物体, 所以显示**最大的那个**。真正的目的是
    // **防止背景里的大片同色区域(绿墙/绿植/蓝天)把标签抢走**。
    //
    // 面积代理 = (right-left)+(bottom-top), **纯加法, 不占 DSP**。
    // (真面积要乘法器, 而 DSP 只剩 25 个; 这里只需要比大小, 不需要真值。)
    // 无效的那一色直接记 0 分 —— 否则它会拿上一帧的陈坐标跟别人比。
    // ========================================================================
    function [11:0] F_size;
        input [10:0] l, r;
        input [ 9:0] t, b;
        begin
            F_size = ((r > l) ? (r - l) : 11'd0) + ((b > t) ? (b - t) : 10'd0);
        end
    endfunction

    wire [11:0] S_sz_r = D_v_r ? F_size(I_det_boxes[ 41:31], I_det_boxes[ 30:20], I_det_boxes[ 19:10], I_det_boxes[  9: 0]) : 12'd0;
    wire [11:0] S_sz_g = D_v_g ? F_size(I_det_boxes[105:95], I_det_boxes[ 94:84], I_det_boxes[ 83:74], I_det_boxes[ 73:64]) : 12'd0;
    wire [11:0] S_sz_b = D_v_b ? F_size(I_det_boxes[169:159], I_det_boxes[158:148], I_det_boxes[147:138], I_det_boxes[137:128]) : 12'd0;

    // 帧首锁存 (和 S_cxv_* / S_lx_* 同一个手法): 此刻 I_det_boxes 稳定不动。
    reg  [1:0]  S_csel;                 // 0=红 1=绿 2=蓝 3=一个有效目标都没有
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)           S_csel <= 2'd3;
        else if(I_video_user) begin
            if      (S_sz_r == 12'd0 && S_sz_g == 12'd0 && S_sz_b == 12'd0) S_csel <= 2'd3;
            else if (S_sz_r >= S_sz_g && S_sz_r >= S_sz_b)                  S_csel <= 2'd0;
            else if (S_sz_g >= S_sz_b)                                      S_csel <= 2'd1;
            else                                                            S_csel <= 2'd2;
        end
    end

    // 帧级锁存: 十字边界每帧算一次。用 I_video_user (帧首) 当使能 ——
    // 此刻 I_det_boxes 上是上一帧算好的结果, 稳定不动, 采到的是自洽的一份。
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_cval_r <= 1'b0; S_cval_g <= 1'b0; S_cval_b <= 1'b0;
            S_hx0_r <= 12'd0; S_hx1_r <= 12'd0; S_hy0_r <= 12'd0; S_hy1_r <= 12'd0;
            S_vx0_r <= 12'd0; S_vx1_r <= 12'd0; S_vy0_r <= 12'd0; S_vy1_r <= 12'd0;
            S_hx0_g <= 12'd0; S_hx1_g <= 12'd0; S_hy0_g <= 12'd0; S_hy1_g <= 12'd0;
            S_vx0_g <= 12'd0; S_vx1_g <= 12'd0; S_vy0_g <= 12'd0; S_vy1_g <= 12'd0;
            S_hx0_b <= 12'd0; S_hx1_b <= 12'd0; S_hy0_b <= 12'd0; S_hy1_b <= 12'd0;
            S_vx0_b <= 12'd0; S_vx1_b <= 12'd0; S_vy0_b <= 12'd0; S_vy1_b <= 12'd0;
        end else if(I_video_user) begin
            S_cval_r <= D_v_r;
            S_hx0_r  <= (D_cx_r > CROSS_ARM) ? (D_cx_r - CROSS_ARM) : 12'd0;
            S_hx1_r  <= D_cx_r + CROSS_ARM;
            S_hy0_r  <= (D_cy_r > CROSS_HW ) ? (D_cy_r - CROSS_HW ) : 12'd0;
            S_hy1_r  <= D_cy_r + CROSS_HW;
            S_vx0_r  <= (D_cx_r > CROSS_HW ) ? (D_cx_r - CROSS_HW ) : 12'd0;
            S_vx1_r  <= D_cx_r + CROSS_HW;
            S_vy0_r  <= (D_cy_r > CROSS_ARM) ? (D_cy_r - CROSS_ARM) : 12'd0;
            S_vy1_r  <= D_cy_r + CROSS_ARM;

            S_cval_g <= D_v_g;
            S_hx0_g  <= (D_cx_g > CROSS_ARM) ? (D_cx_g - CROSS_ARM) : 12'd0;
            S_hx1_g  <= D_cx_g + CROSS_ARM;
            S_hy0_g  <= (D_cy_g > CROSS_HW ) ? (D_cy_g - CROSS_HW ) : 12'd0;
            S_hy1_g  <= D_cy_g + CROSS_HW;
            S_vx0_g  <= (D_cx_g > CROSS_HW ) ? (D_cx_g - CROSS_HW ) : 12'd0;
            S_vx1_g  <= D_cx_g + CROSS_HW;
            S_vy0_g  <= (D_cy_g > CROSS_ARM) ? (D_cy_g - CROSS_ARM) : 12'd0;
            S_vy1_g  <= D_cy_g + CROSS_ARM;

            S_cval_b <= D_v_b;
            S_hx0_b  <= (D_cx_b > CROSS_ARM) ? (D_cx_b - CROSS_ARM) : 12'd0;
            S_hx1_b  <= D_cx_b + CROSS_ARM;
            S_hy0_b  <= (D_cy_b > CROSS_HW ) ? (D_cy_b - CROSS_HW ) : 12'd0;
            S_hy1_b  <= D_cy_b + CROSS_HW;
            S_vx0_b  <= (D_cx_b > CROSS_HW ) ? (D_cx_b - CROSS_HW ) : 12'd0;
            S_vx1_b  <= D_cx_b + CROSS_HW;
            S_vy0_b  <= (D_cy_b > CROSS_ARM) ? (D_cy_b - CROSS_ARM) : 12'd0;
            S_vy1_b  <= D_cy_b + CROSS_ARM;
        end
    end

    // 单色十字判定: 横条 (y 在厚度内 且 x 在跨度内) 或 竖条 (x 在厚度内 且 y 在跨度内)
    function F_cross;
        input [11:0] x, y;
        input        v;
        input [11:0] hx0, hx1, hy0, hy1, vx0, vx1, vy0, vy1;
        begin
            F_cross = v &&
                      ( ((y >= hy0) && (y <= hy1) && (x >= hx0) && (x <= hx1)) ||
                        ((x >= vx0) && (x <= vx1) && (y >= vy0) && (y <= vy1)) );
        end
    endfunction

    // 用 **1d 级**坐标算, 结果寄存 —— 到 2d 级直接使用, 比较链不占临界路径
    reg S_cross_1d;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_cross_1d <= 1'b0;
        else
            S_cross_1d <= F_cross(S_x_1d, S_y_1d, S_cval_r,
                                  S_hx0_r, S_hx1_r, S_hy0_r, S_hy1_r,
                                  S_vx0_r, S_vx1_r, S_vy0_r, S_vy1_r) ||
                          F_cross(S_x_1d, S_y_1d, S_cval_g,
                                  S_hx0_g, S_hx1_g, S_hy0_g, S_hy1_g,
                                  S_vx0_g, S_vx1_g, S_vy0_g, S_vy1_g) ||
                          F_cross(S_x_1d, S_y_1d, S_cval_b,
                                  S_hx0_b, S_hx1_b, S_hy0_b, S_hy1_b,
                                  S_vx0_b, S_vx1_b, S_vy0_b, S_vy1_b);
    end

    // 三色名文字的第 pos 个字符 (行 0=RED 1=GREEN 2=BLUE)
    function [7:0] F_col_char;
        input [3:0] pos;
        input [1:0] line;
        reg [7:0] c;
        begin
            case(line)
                2'd0: c = (pos==4'd0) ? CHAR_R : (pos==4'd1) ? CHAR_E :
                          (pos==4'd2) ? CHAR_D : CHAR_SP;                        // RED
                2'd1: c = (pos==4'd0) ? CHAR_G : (pos==4'd1) ? CHAR_R :
                          (pos==4'd2) ? CHAR_E : (pos==4'd3) ? CHAR_E :
                          (pos==4'd4) ? CHAR_N : CHAR_SP;                        // GREEN
                default: c = (pos==4'd0) ? CHAR_B : (pos==4'd1) ? CHAR_L :
                             (pos==4'd2) ? CHAR_U : (pos==4'd3) ? CHAR_E : CHAR_SP; // BLUE
            endcase
            F_col_char = c;
        end
    endfunction

    // ========================================================================
    // DYN_OSD (安路 + 模式名) 的字符解码, 提前一级 (2026-10-10)
    //
    // 和颜色名标签用的是同一个手法。实测 (build 2e) HDMI 域最差路径
    //     起点 S_x_2d_reg  ->  终点 O_hdmi_data_reg
    //     14.140ns, **Logic Level 18**
    // 走的就是这条"相对坐标 → 安路缩放/模式名字符 → ROM → 选位 → 合成"的链。
    // 把前半截挪到 1d 级并寄存, 2d 级只剩 ROM 读 + 选位。
    //
    // ★ 对齐: S_x_1d 在第 N 拍对应的像素, 就是 S_x_2d 在第 N+1 拍的像素。
    //   所以 1d 级算、寄存一拍、2d 级用 —— 对应的还是同一个像素, 无位移。
    // ========================================================================
    wire [11:0] S_dx1 = S_x_1d - DYN_OSD_X;
    wire [11:0] S_dy1 = S_y_1d - DYN_OSD_Y;

    // "安路"两个汉字的区域判定 (24x24 字形缩到 16x16, 见 F_scale24to16)
    wire [11:0] S_an_lx = (S_dx1 < 12'd24) ? S_dx1 : (S_dx1 - 12'd24);
    wire [11:0] S_an_ly = S_dy1 - CN_Y_OFFSET;
    wire        S_an_zone = (((S_dx1 < 12'd24) ||
                              ((S_dx1 >= 12'd24) && (S_dx1 < 12'd48))) &&
                             (S_dy1 >= CN_Y_OFFSET) &&
                             (S_dy1 < (CN_Y_OFFSET + 12'd24)) &&
                             (S_an_lx < 12'd24) && (S_an_ly < 12'd24));
    // 模式名那一行的区域 (最多 "MODE CARTOON" 12 个字符)
    wire        S_md_zone = (S_dx1 >= 12'd52) && (S_dx1 < 12'd244) &&
                            (S_dy1 >= 12'd4) && (S_dy1 < 12'd20);
    // 第二行: 运动块计数 "MOT:nnnn" (2026-10-12)
    // 8 个字符 x 16 px = 128 -> x 52..179; 纵向 y 26..42。
    // 只在运动模式(4)下出现。
    wire        S_mot_zone = (S_mode_r == 3'd4) &&
                             (S_dx1 >= 12'd52) && (S_dx1 < 12'd180) &&
                             (S_dy1 >= 12'd26) && (S_dy1 < 12'd42);

    // 坐标标注 (2026-10-14) —— 跟踪模式(3)的第二行, 格式 "R X0512 Y0288"。
    // 13 字符 x 16 px = 208 -> x 52..260 (DYN_OSD_W=264 装得下, 不用加宽)。
    // 和 S_mot_zone 同一片位置, 但两个模式互斥(3 和 4), 不会同时画。
    wire        S_coord_zone = (S_mode_r == 3'd3) &&
                               (S_dx1 >= 12'd52) && (S_dx1 < 12'd260) &&
                               (S_dy1 >= 12'd26) && (S_dy1 < 12'd42);
    wire        S_demo_zone = (S_mode_r == 3'd5 || S_mode_r == 3'd6 || S_mode_r == 3'd7) &&
                              (S_dx1 >= 12'd52) && (S_dx1 < 12'd228) &&
                              (S_dy1 >= 12'd26) && (S_dy1 < 12'd42);
    wire        S_ae_gain_zone = (S_mode_r == 3'd7) &&
                                 (S_dx1 >= 12'd52) && (S_dx1 < 12'd196) &&
                                 (S_dy1 >= 12'd70) && (S_dy1 < 12'd86);

    // 延迟读数 (2026-10-14) —— **第三行, 三种模式都显示**。
    // 格式 "LAT 2F 033MS", 12 字符 x 16 px = 192 -> x 52..244。
    // 它是系统指标(采集到显示多少帧), 不属于某个算法模式, 所以不按模式门控。
    wire        S_lat_zone = (S_dx1 >= 12'd52) && (S_dx1 < 12'd244) &&
                             (S_dy1 >= 12'd48) && (S_dy1 < 12'd64);
    // frame counter row: "CNT: nnnnnn" -> 10 chars x 16 px = 160 -> x 52..212
    wire        S_cnt_zone = (S_mode_r != 3'd7) &&
                             (S_dx1 >= 12'd52) && (S_dx1 < 12'd212) &&
                             (S_dy1 >= 12'd70) && (S_dy1 < 12'd86);

    // 运动块计数的 BCD 结果 (2026-10-12, Double Dabble 第 7 路)。
    // ★ 声明在这里而不是和 S_bx_r 那一组放一起 —— F_mot_char 要用它,
    //   而函数不能前向引用后面的声明。
    reg [15:0] S_mot_bcd;
    reg [15:0] S_ae_exp_bcd, S_ae_gain_bcd;
    reg [10:0] S_ae_exp_v;
    reg [7:0] S_ae_gain_v;

    // ★ 2026-10-14: 质心 BCD 结果 (Double Dabble 的 6 路输出) 的声明也挪到这里。
    //   原因和上面 S_mot_bcd 一模一样 —— F_coord_char 要用它, 而**函数不能前向
    //   引用后面的声明** (这条已经吃过一次亏, 见上面那段注释)。
    //   声明挪走、赋值留在原处 (下面 Double Dabble 那个 always 块), 功能不变。
    reg [15:0] S_bx_r, S_by_r;         // 红 cx / cy
    reg [15:0] S_bx_g, S_by_g;         // 绿
    reg [15:0] S_bx_b, S_by_b;         // 蓝

    // 坐标标注选中那一色的 BCD (无效时 S_cok=0, 整行显示空格)
    wire [15:0] S_bx_sel = (S_csel == 2'd0) ? S_bx_r : (S_csel == 2'd1) ? S_bx_g : S_bx_b;
    wire [15:0] S_by_sel = (S_csel == 2'd0) ? S_by_r : (S_csel == 2'd1) ? S_by_g : S_by_b;
    wire        S_ok_sel = (S_csel != 2'd3);

    // Coordinate hold: the detector drops its box for a frame now and then
    // (AREA_TH hysteresis, window hand-off), which used to blank the whole
    // coordinate row for one frame -> visible flicker. Latch the last valid
    // reading and keep showing it for HOLD frames after the target is lost.
    reg [1:0]  S_csel_h;
    reg [15:0] S_cbx_h, S_cby_h;
    reg [3:0]  S_hold_cnt;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_csel_h   <= 2'd3;
            S_cbx_h    <= 16'd0;
            S_cby_h    <= 16'd0;
            S_hold_cnt <= 4'd0;
        end else if(I_video_user) begin
            if(S_ok_sel) begin
                S_csel_h   <= S_csel;
                S_cbx_h    <= S_bx_sel;
                S_cby_h    <= S_by_sel;
                S_hold_cnt <= 4'd12;        // ~0.4 s at 30 fps
            end else if(S_hold_cnt != 4'd0)
                S_hold_cnt <= S_hold_cnt - 4'd1;
        end
    end

    wire [1:0]  S_csel_u = S_ok_sel ? S_csel   : S_csel_h;
    wire [15:0] S_cbx    = S_ok_sel ? S_bx_sel : S_cbx_h;
    wire [15:0] S_cby    = S_ok_sel ? S_by_sel : S_cby_h;
    wire        S_cok    = S_ok_sel || (S_hold_cnt != 4'd0);

    // ========================================================================
    // 模式值的帧首锁存 (2026-10-12) —— 进阶要求(1)「力求切换平稳」
    //
    // 图像那一侧本来就是平稳的: isp_top 在**摄像头帧边界**采样模式, 所以画面
    // 永远整帧整帧地换, 不会半帧撕裂。
    //
    // 但 OSD 文字原来直接用跨时钟域同步过来的 I_mode —— 它在**显示帧的任意
    // 位置**变, 于是切换之后有整整一帧是"画面还是旧模式、文字已经变成新名字"。
    // 16ms, 肉眼几乎看不出, 但严格说就是不平稳。
    //
    // 现在在 I_video_user (显示帧首) 把它锁进 S_mode_r, 后面全部用 S_mode_r ——
    // 文字和画面就永远同一帧切换了。和 S_cval_*/S_lx_* 用的是同一个手法。
    // ========================================================================
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)        S_mode_r <= 3'd0;
        else if(I_video_user) S_mode_r <= I_mode;
    end

    // 一个 BCD 数字 (0..9) 转成字符码; 前导零用"最高位有效标志"变成空格。
    // ★ 2026-10-12: 从坐标显示那一块挪到这里 —— F_mot_char 要用它，而 Verilog
    //   的函数不能前向引用(不像 wire/reg 那样能蒙混)。
    function [7:0] F_bcd_char;
        input [3:0] d;
        input       show;      // 0 = 前导零, 显示空格
        begin
            F_bcd_char = show ? (CHAR_0 + {4'd0, d}) : CHAR_SP;
        end
    endfunction
    // frame counter line: "CNT: nnnnnn" (6 decimal digits, wraps at 1e6)
    function [7:0] F_cnt_char;
        input [3:0] pos;
        case(pos)
            4'd0: F_cnt_char = CHAR_C;
            4'd1: F_cnt_char = CHAR_N;
            4'd2: F_cnt_char = CHAR_T;
            4'd3: F_cnt_char = CHAR_COLON;
            4'd4: F_cnt_char = CHAR_0 + {4'd0, S_cnt_d5};
            4'd5: F_cnt_char = CHAR_0 + {4'd0, S_cnt_d4};
            4'd6: F_cnt_char = CHAR_0 + {4'd0, S_cnt_d3};
            4'd7: F_cnt_char = CHAR_0 + {4'd0, S_cnt_d2};
            4'd8: F_cnt_char = CHAR_0 + {4'd0, S_cnt_d1};
            4'd9: F_cnt_char = CHAR_0 + {4'd0, S_cnt_d0};
            default: F_cnt_char = CHAR_SP;
        endcase
    endfunction

    // ========================================================================
    // 采集→显示延迟的读数 (2026-10-14) —— 进阶要求 2.5(3)「处理延迟可视化」
    //
    // 数值在 video_in.v 里测好 (帧号穿过帧缓存表走了一圈, 相减得到), 这里只负责画。
    // 显示在**第三行**, 三种模式都出现 —— 它是系统指标, 不该只在某个模式里看得到。
    //
    // ★ 预处理放在函数**外面**: 函数里只做查表。函数里做算术会被综合器折成常量、
    //   把整条下游剪光 —— 这个坑本工程踩过 (见下面 F_coord_char 的注释)。
    // ========================================================================
    // 帧数, 夹到 0..9 (实际只有 2 左右; 夹住是为了让下面那张表的索引位宽可控)
    wire [3:0]  S_latf  = (I_lat_fid > 16'd9) ? 4'd9 : I_lat_fid[3:0];
    // 毫秒 = 帧数 x 16.667。**直接查表, 不做乘法** (0/17/33/50/67/83/100/117/133/150)
    reg  [11:0] S_latms;                       // 3 位 BCD: [11:8]百 [7:4]十 [3:0]个
    always @(*) case(S_latf)
        4'd0: S_latms = 12'h000;   4'd1: S_latms = 12'h017;
        4'd2: S_latms = 12'h033;   4'd3: S_latms = 12'h050;
        4'd4: S_latms = 12'h067;   4'd5: S_latms = 12'h083;
        4'd6: S_latms = 12'h100;   4'd7: S_latms = 12'h117;
        4'd8: S_latms = 12'h133;   default: S_latms = 12'h150;
    endcase

    // "LAT 2F 033MS" 的第 pos 个字符 (12 个字符 = 192 px)
    function [7:0] F_lat_char;
        input [3:0] pos;
        begin
            case(pos)
                4'd0:  F_lat_char = CHAR_L;
                4'd1:  F_lat_char = CHAR_A;
                4'd2:  F_lat_char = CHAR_T;
                4'd3:  F_lat_char = CHAR_SP;
                4'd4:  F_lat_char = F_bcd_char(S_latf,        1'b1);   // 帧数
                4'd5:  F_lat_char = CHAR_F;
                4'd6:  F_lat_char = CHAR_SP;
                4'd7:  F_lat_char = F_bcd_char(S_latms[11: 8], 1'b1);  // 毫秒 x3
                4'd8:  F_lat_char = F_bcd_char(S_latms[ 7: 4], 1'b1);
                4'd9:  F_lat_char = F_bcd_char(S_latms[ 3: 0], 1'b1);
                4'd10: F_lat_char = CHAR_M;
                4'd11: F_lat_char = CHAR_S;
                default: F_lat_char = CHAR_SP;
            endcase
        end
    endfunction

    // 坐标标注 "R X0512 Y0288" 的第 pos 个字符 (pos = 0..12) —— 2026-10-14。
    // 前面那个字母是**当前选中的颜色**(S_csel), 没有有效目标时整行空格。
    // 前导零按空格, 和 F_mot_char 同一个手法; 位置固定, 所以数字不会左右跳。
    // ★ 这个函数里**没有局部变量、没有算术** —— 只做比较和查表。函数里做算术
    //   (case/乘法) 会被综合器折成常量、把整条下游剪光, 这是踩过的坑, 别再往里加。
    function [7:0] F_coord_char;
        input [3:0] pos;
        begin
            case(pos)
                4'd0:  F_coord_char = S_cok ? ((S_csel_u == 2'd0) ? CHAR_R :
                                               (S_csel_u == 2'd1) ? CHAR_G : CHAR_B) : CHAR_SP;
                4'd1:  F_coord_char = CHAR_SP;
                4'd2:  F_coord_char = S_cok ? CHAR_X : CHAR_SP;
                4'd3:  F_coord_char = S_cok ? F_bcd_char(S_cbx[15:12], (S_cbx[15:12] != 4'd0 )) : CHAR_SP;
                4'd4:  F_coord_char = S_cok ? F_bcd_char(S_cbx[11: 8], (S_cbx[15: 8] != 8'd0 )) : CHAR_SP;
                4'd5:  F_coord_char = S_cok ? F_bcd_char(S_cbx[ 7: 4], (S_cbx[15: 4] != 12'd0)) : CHAR_SP;
                4'd6:  F_coord_char = S_cok ? F_bcd_char(S_cbx[ 3: 0], 1'b1                     ) : CHAR_SP;
                4'd7:  F_coord_char = CHAR_SP;
                4'd8:  F_coord_char = S_cok ? CHAR_Y : CHAR_SP;
                4'd9:  F_coord_char = S_cok ? F_bcd_char(S_cby[15:12], (S_cby[15:12] != 4'd0 )) : CHAR_SP;
                4'd10: F_coord_char = S_cok ? F_bcd_char(S_cby[11: 8], (S_cby[15: 8] != 8'd0 )) : CHAR_SP;
                4'd11: F_coord_char = S_cok ? F_bcd_char(S_cby[ 7: 4], (S_cby[15: 4] != 12'd0)) : CHAR_SP;
                4'd12: F_coord_char = S_cok ? F_bcd_char(S_cby[ 3: 0], 1'b1                     ) : CHAR_SP;
                default: F_coord_char = CHAR_SP;
            endcase
        end
    endfunction

    // OSD 第二行 "MOT:nnnn" 的第 pos 个字符 (运动块计数)。
    // 它引用的 S_mot_bcd 在后面声明 —— reg 的前向引用 TD 是接受的。
    // 前导零按空格: 静止时显示 "MOT:   0", 挥手时 "MOT: 123"。
    function [7:0] F_mot_char;
        input [3:0] pos;
        begin
            case(pos)
                4'd0: F_mot_char = CHAR_M;
                4'd1: F_mot_char = CHAR_O;
                4'd2: F_mot_char = CHAR_T;
                4'd3: F_mot_char = CHAR_COLON;
                4'd4: F_mot_char = F_bcd_char(S_mot_bcd[15:12], (S_mot_bcd[15:12] != 4'd0));
                4'd5: F_mot_char = F_bcd_char(S_mot_bcd[11: 8], (S_mot_bcd[15: 8] != 8'd0));
                4'd6: F_mot_char = F_bcd_char(S_mot_bcd[ 7: 4], (S_mot_bcd[15: 4] != 12'd0));
                4'd7: F_mot_char = F_bcd_char(S_mot_bcd[ 3: 0], 1'b1);
                default: F_mot_char = CHAR_SP;
            endcase
        end
    endfunction

    // Demo caption; both halves are live pixels from the same sensor frame.
    // AE has no physically independent off/on exposure on a single sensor.
    function [7:0] F_demo_char;
        input [3:0] pos;
        begin
            if (S_mode_r == 3'd7) begin
                case(pos)
                    4'd0: F_demo_char = CHAR_E;
                    4'd1: F_demo_char = CHAR_X;
                    4'd2: F_demo_char = CHAR_P;
                    4'd3: F_demo_char = CHAR_COLON;
                    4'd4: F_demo_char = F_bcd_char(S_ae_exp_bcd[15:12], 1'b1);
                    4'd5: F_demo_char = F_bcd_char(S_ae_exp_bcd[11:8], 1'b1);
                    4'd6: F_demo_char = F_bcd_char(S_ae_exp_bcd[7:4], 1'b1);
                    4'd7: F_demo_char = F_bcd_char(S_ae_exp_bcd[3:0], 1'b1);
                    default: F_demo_char = CHAR_SP;
                endcase
            end else begin
                case(pos)
                    4'd0: F_demo_char = CHAR_L;
                    4'd1: F_demo_char = CHAR_COLON;
                    4'd2: F_demo_char = CHAR_O;
                    4'd3: F_demo_char = CHAR_F;
                    4'd4: F_demo_char = CHAR_F;
                    4'd5: F_demo_char = CHAR_SP;
                    4'd6: F_demo_char = CHAR_R;
                    4'd7: F_demo_char = CHAR_COLON;
                    4'd8: F_demo_char = CHAR_O;
                    4'd9: F_demo_char = CHAR_N;
                    default: F_demo_char = CHAR_SP;
                endcase
            end
        end
    endfunction

    function [7:0] F_ae_gain_char;
        input [3:0] pos;
        begin
            case(pos)
                4'd0: F_ae_gain_char = CHAR_G;
                4'd1: F_ae_gain_char = CHAR_A;
                4'd2: F_ae_gain_char = CHAR_I;
                4'd3: F_ae_gain_char = CHAR_N;
                4'd4: F_ae_gain_char = CHAR_COLON;
                4'd5: F_ae_gain_char = F_bcd_char(S_ae_gain_bcd[11:8], 1'b1);
                4'd6: F_ae_gain_char = F_bcd_char(S_ae_gain_bcd[7:4], 1'b1);
                4'd7: F_ae_gain_char = F_bcd_char(S_ae_gain_bcd[3:0], 1'b1);
                default: F_ae_gain_char = CHAR_SP;
            endcase
        end
    endfunction

    reg        S_dosd_hit_r;
    reg [7:0]  S_dosd_char_r;
    reg [3:0]  S_dosd_col_r, S_dosd_row_r;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_dosd_hit_r  <= 1'b0;
            S_dosd_char_r <= 8'h20;
            S_dosd_col_r  <= 4'd0;
            S_dosd_row_r  <= 4'd0;
        end else begin
            S_dosd_hit_r <= 1'b0;
            if(S_an_zone) begin
                S_dosd_hit_r  <= 1'b1;
                S_dosd_char_r <= (S_dx1 < 12'd24) ? CHAR_AN : CHAR_LU;
                S_dosd_col_r  <= F_scale24to16(S_an_lx[4:0]);
                S_dosd_row_r  <= F_scale24to16(S_an_ly[4:0]);
            end
            else if(S_md_zone) begin
                S_dosd_hit_r  <= 1'b1;
                S_dosd_char_r <= F_mode_char((S_dx1 - 12'd52) >> 4, S_mode_r);
                S_dosd_col_r  <= (S_dx1 - 12'd52) & 4'hf;
                S_dosd_row_r  <= (S_dy1 - 12'd4);
            end
            else if(S_mot_zone) begin
                // 2026-10-12: 第二行显示运动块计数
                S_dosd_hit_r  <= 1'b1;
                S_dosd_char_r <= F_mot_char((S_dx1 - 12'd52) >> 4);
                S_dosd_col_r  <= (S_dx1 - 12'd52) & 4'hf;
                S_dosd_row_r  <= (S_dy1 - 12'd26);
            end
            else if(S_coord_zone) begin
                // 2026-10-14: 跟踪模式的第二行显示选中目标的坐标 "R X0512 Y0288"
                S_dosd_hit_r  <= 1'b1;
                S_dosd_char_r <= F_coord_char((S_dx1 - 12'd52) >> 4);
                S_dosd_col_r  <= (S_dx1 - 12'd52) & 4'hf;
                S_dosd_row_r  <= (S_dy1 - 12'd26);
            end
            else if(S_demo_zone) begin
                S_dosd_hit_r  <= 1'b1;
                S_dosd_char_r <= F_demo_char((S_dx1 - 12'd52) >> 4);
                S_dosd_col_r  <= (S_dx1 - 12'd52) & 4'hf;
                S_dosd_row_r  <= (S_dy1 - 12'd26);
            end
            else if(S_lat_zone) begin
                // 2026-10-14: 第三行显示采集到显示的延迟 "LAT 2F 033MS" (所有模式)
                S_dosd_hit_r  <= 1'b1;
                S_dosd_char_r <= F_lat_char((S_dx1 - 12'd52) >> 4);
                S_dosd_col_r  <= (S_dx1 - 12'd52) & 4'hf;
                S_dosd_row_r  <= (S_dy1 - 12'd48);
            end
            else if(S_cnt_zone) begin
                S_dosd_hit_r  <= 1'b1;
                S_dosd_char_r <= F_cnt_char((S_dx1 - 12'd52) >> 4);
                S_dosd_col_r  <= (S_dx1 - 12'd52) & 4'hf;
                S_dosd_row_r  <= (S_dy1 - 12'd70);
            end
            else if(S_ae_gain_zone) begin
                S_dosd_hit_r  <= 1'b1;
                S_dosd_char_r <= F_ae_gain_char((S_dx1 - 12'd52) >> 4);
                S_dosd_col_r  <= (S_dx1 - 12'd52) & 4'hf;
                S_dosd_row_r  <= (S_dy1 - 12'd70);
            end
        end
    end

    // ========================================================================
    // 质心坐标的十进制显示 (2026-10-10)
    //
    // 进阶要求 2.5(2) 说"叠加跟踪标识**或**坐标信息" —— 十字已经满足"跟踪标识",
    // 这里是额外把**数值坐标**也显示出来, 演示更直观。
    //
    // ★ 怎么把二进制转十进制 —— **不用除法**(要乘法器, DSP 只剩 5 个):
    //   用 Double Dabble 算法, 纯"移位 + 加三", 11 拍出 4 个 BCD 数字。
    //   标准做法: 每次移位前, 若某个 BCD 数字 >= 5 就先加 3。
    //
    // ★ 一帧只转一次: 有个 6 状态的小状态机, 在帧首依次转
    //   红cx 红cy 绿cx 绿cy 蓝cx 蓝cy —— 6 x 11 = 66 拍, 一帧有 57600 拍,
    //   占用可以忽略。所以**一个转换器大家轮流用**, 不用做 6 份。
    // ========================================================================
    // 2026-10-12: 11 -> 14 位。第 7 路(运动块计数)最大 9999(饱和后), 需要 14 位。
    // 前 6 路是 11 位的坐标, 零扩展到 14 位后再转 —— 多出来的高位全是 0,
    // 只是多移 3 次, 结果不变。每帧多花 7x3=21 拍, 帧间空隙有几万拍, 无所谓。
    localparam DD_BITS = 14;

    reg  [13:0] S_dd_bin;              // 待转换的二进制值
    reg  [15:0] S_dd_bcd;              // 转换结果: [15:12]千 [11:8]百 [7:4]十 [3:0]个
    reg  [3:0]  S_dd_i;                // 已移位次数 0..DD_BITS
    reg  [2:0]  S_dd_sel;              // 0..6: 当前转的是哪一路
    reg         S_dd_busy;

    // Double Dabble 每一步的"若 >=5 则 +3"预处理 (纯组合)。
    // 单独提成 wire, 是为了让下面那一步能把"加三"和"左移"写成一条合并赋值 ——
    // **原来只写了加三、把左移那一行弄丢了**, 见下面 always 里的修复注释。
    wire [3:0] DD3_0 = (S_dd_bcd[ 3: 0] >= 4'd5) ? (S_dd_bcd[ 3: 0] + 4'd3) : S_dd_bcd[ 3: 0];
    wire [3:0] DD3_1 = (S_dd_bcd[ 7: 4] >= 4'd5) ? (S_dd_bcd[ 7: 4] + 4'd3) : S_dd_bcd[ 7: 4];
    wire [3:0] DD3_2 = (S_dd_bcd[11: 8] >= 4'd5) ? (S_dd_bcd[11: 8] + 4'd3) : S_dd_bcd[11: 8];
    wire [3:0] DD3_3 = (S_dd_bcd[15:12] >= 4'd5) ? (S_dd_bcd[15:12] + 4'd3) : S_dd_bcd[15:12];

    // 转换结果寄存器: 每路 4 个 BCD 数字 (16 位)
    // ★ S_bx_*/S_by_* (6 路) 和 S_mot_bcd (第 7 路) 的**声明都挪到前面去了** ——
    //   F_coord_char / F_mot_char 要用它们, 而函数不能前向引用后面的声明。
    //   这里只留着赋值 (在下面的 Double Dabble 状态机里), 功能不变。

    // 各路待转换的原始值 (帧首锁存, 转换期间保持不动)
    reg [10:0] S_cxv_r, S_cyv_r, S_cxv_g, S_cyv_g, S_cxv_b, S_cyv_b;
    // 运动计数: 12 位最大 14400, 但 4 位 BCD 只到 9999 —— **饱和到 9999**。
    // 实际场景里计数都在几十到几百, 撞不到上限; 这样不用把 BCD 加宽成 5 位。
    reg [13:0] S_motv;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_dd_bin <= 14'd0; S_dd_bcd <= 16'd0; S_dd_i <= 4'd0;
            S_dd_sel <= 3'd0;  S_dd_busy <= 1'b0;
            S_bx_r <= 16'd0; S_by_r <= 16'd0;
            S_bx_g <= 16'd0; S_by_g <= 16'd0;
            S_bx_b <= 16'd0; S_by_b <= 16'd0;
            S_mot_bcd <= 16'd0; S_motv <= 14'd0;
            S_ae_exp_bcd <= 16'd0; S_ae_gain_bcd <= 16'd0;
            S_ae_exp_v <= 11'd0; S_ae_gain_v <= 8'd0;
            S_cxv_r <= 11'd0; S_cyv_r <= 11'd0;
            S_cxv_g <= 11'd0; S_cyv_g <= 11'd0;
            S_cxv_b <= 11'd0; S_cyv_b <= 11'd0;
        end else begin
            // ---- 帧首: 锁存 6 个坐标 + 运动计数, 启动转换 --------------------
            if(I_video_user) begin
                S_cxv_r <= D_cx_r[10:0];  S_cyv_r <= D_cy_r[10:0];
                S_cxv_g <= D_cx_g[10:0];  S_cyv_g <= D_cy_g[10:0];
                S_cxv_b <= D_cx_b[10:0];  S_cyv_b <= D_cy_b[10:0];
                S_mot_bcd <= I_mot_cnt;     // 已经是 BCD, 直接存
                S_ae_exp_v <= I_ae_exp[10:0];
                S_ae_gain_v <= I_ae_gain;
                S_dd_sel  <= 3'd0;
                S_dd_i    <= 4'd0;
                S_dd_bcd  <= 16'd0;
                S_dd_busy <= 1'b1;
                // 第 0 路先装载 (下面 sel==0 那一支)
                S_dd_bin  <= D_cx_r[10:0];
            end else if(S_dd_busy) begin
                if(S_dd_i == DD_BITS[3:0]) begin
                    // 本路转换完: 存结果, 换下一路
                    case(S_dd_sel)
                        3'd0: S_bx_r <= S_dd_bcd;
                        3'd1: S_by_r <= S_dd_bcd;
                        3'd2: S_bx_g <= S_dd_bcd;
                        3'd3: S_by_g <= S_dd_bcd;
                        3'd4: S_bx_b <= S_dd_bcd;
                        3'd5: S_by_b <= S_dd_bcd;
                        3'd6: S_ae_exp_bcd <= S_dd_bcd;
                        3'd7: S_ae_gain_bcd <= S_dd_bcd;
                    endcase
                    S_dd_i   <= 4'd0;
                    S_dd_bcd <= 16'd0;
                    if(S_dd_sel == 3'd7) begin
                        S_dd_busy <= 1'b0;          // 坐标六路 + AE 两路全完
                    end else begin
                        S_dd_sel <= S_dd_sel + 3'd1;
                        // 装载下一路的原始值 (用**刚锁存进 S_cxv_* 的值**,
                        // 所以这里用 if(I_video_user) 之外的分支读 D_* 也行 ——
                        // 但 D_* 每帧都在变, 所以直接读刚锁存的那组更稳)
                        // ★★ 2026-10-14 修复 —— 这里**错位了一路**。
                        //   上面 S_dd_sel <= S_dd_sel + 3'd1 是**非阻塞**的, 所以这一拍
                        //   case(S_dd_sel) 读到的还是**刚算完的那一路**; 而我们要装的是
                        //   **下一路**的源。原来按 "sel=k 装源 k" 写, 于是每一路都在转
                        //   上一路的输入值 —— 结果 S_bx_r = 红的 cx(碰巧对),
                        //   S_by_r 也 = 红的 cx (**X 和 Y 显示同一个数**), 后面全串位。
                        //   包上 S_dd_sel+1 才是对的; 这里直接把映射下移一格写开, 更省。
                        //   (和上面"丢了左移"一样, 这个 bug 也是因为输出从没上过屏才藏住的。)
                        case(S_dd_sel)
                            3'd0: S_dd_bin <= S_cyv_r;   // 第 1 路 (红 cy)
                            3'd1: S_dd_bin <= S_cxv_g;   // 第 2 路 (绿 cx)
                            3'd2: S_dd_bin <= S_cyv_g;   // 第 3 路 (绿 cy)
                            3'd3: S_dd_bin <= S_cxv_b;   // 第 4 路 (蓝 cx)
                            3'd4: S_dd_bin <= S_cyv_b;   // 第 5 路 (蓝 cy)
                            3'd5: S_dd_bin <= {3'd0, S_ae_exp_v};
                            3'd6: S_dd_bin <= {6'd0, S_ae_gain_v};
                            // 3'd5 (最后一路) 不走这里 —— 那一支直接清 S_dd_busy
                        endcase
                    end
                end else begin
                    // 一步 Double Dabble: 先"若>=5则+3", 再整体左移一位、
                    // 把 bin 的最高位补进 BCD 的最低位。
                    //
                    // ★★ 2026-10-14 修复 —— **原来只有"+3"那一步, 左移那一行丢了**。
                    //   S_dd_bcd 从初值 0 出发, 每一步都因为"0 >= 5 不成立"而不加 3,
                    //   于是它**永远停在 0**: 6 路坐标的 BCD 恒为 0。
                    //   为什么一直没暴露: CNT_DIGITS_EN=1'b0 从来没显示过它的输出,
                    //   而 "MOT:nnnn" 走的是另一条路 (S_mot_bcd 直接拿 I_mot_cnt)。
                    //   **这个转换器的输出从来没上过屏** —— 第一次真正用它(坐标标注,
                    //   2026-10-14)才现形。教训: 没被显示过的功能等于没验证过。
                    S_dd_bcd <= {DD3_3[2:0], DD3_2, DD3_1, DD3_0, S_dd_bin[DD_BITS-1]};
                    S_dd_bin <= {S_dd_bin[12:0], 1'b0};
                    S_dd_i   <= S_dd_i + 4'd1;
                end
            end
        end
    end

    // 一个 BCD 数字 (0..9) 转成字符码; 前导零用"最高位有效标志"变成空格
    // ★ 2026-10-12: 挪到前面去了 —— F_mot_char 要用它, 而函数不能前向引用。
    //   (原来它在坐标显示那一块里, 现在在 "S_mot_zone" 那段上面。)

    // ---- 24x24 汉字缩到 16x16 的等比缩放表 (2026-10-10) --------------------
    // 原来写的是 S_pf_scale_x = local_x * 16; S_pf_col = scale_x / 24;
    // 那个"除以 24"综合出来是**一个真的除法器**(10 位除以常数), 组合深度不小,
    // 而 HDMI 域那条路径本来就只有 13.333ns。
    // local_x 只有 0..23 共 24 个取值 —— 直接查表: (x*16)/24 = (x*2)/3。
    // 24 项的小表约 24 个 LUT, 换掉一个除法器, 稳赚。
    function [3:0] F_scale24to16;
        input [4:0] x;              // 0..23
        begin
            case(x)
                5'd0:  F_scale24to16 = 4'd0;   5'd1:  F_scale24to16 = 4'd0;
                5'd2:  F_scale24to16 = 4'd1;   5'd3:  F_scale24to16 = 4'd2;
                5'd4:  F_scale24to16 = 4'd2;   5'd5:  F_scale24to16 = 4'd3;
                5'd6:  F_scale24to16 = 4'd4;   5'd7:  F_scale24to16 = 4'd4;
                5'd8:  F_scale24to16 = 4'd5;   5'd9:  F_scale24to16 = 4'd6;
                5'd10: F_scale24to16 = 4'd6;   5'd11: F_scale24to16 = 4'd7;
                5'd12: F_scale24to16 = 4'd8;   5'd13: F_scale24to16 = 4'd8;
                5'd14: F_scale24to16 = 4'd9;   5'd15: F_scale24to16 = 4'd10;
                5'd16: F_scale24to16 = 4'd10;  5'd17: F_scale24to16 = 4'd11;
                5'd18: F_scale24to16 = 4'd12;  5'd19: F_scale24to16 = 4'd12;
                5'd20: F_scale24to16 = 4'd13;  5'd21: F_scale24to16 = 4'd14;
                5'd22: F_scale24to16 = 4'd14;  5'd23: F_scale24to16 = 4'd15;
                default: F_scale24to16 = 4'd15;
            endcase
        end
    endfunction

    // ========================================================================
    // 颜色名标签的几何 + 字形查表 —— 拆成两级寄存 (2026-10-11 重构)
    //
    // ★ 板子上量到的根因 (上一版 build: HDMI -5.230ns / Logic Level 24):
    //   把标签从 DYN_OSD 矩形里挪出来时, 用 `!S_osd_hit` 做优先级 —— 而
    //   S_osd_hit 依赖 **Logo ROM 的输出**。于是 2d 级变成:
    //       S_x_2d → Logo 地址/Logo ROM → S_osd_hit → 选 S_pf_char
    //              → 字符 ROM → 选位 → S_osd_hit → 颜色 → O_hdmi_data
    //   **两个大 ROM 串成一条链** = 24 级 / 18.3ns, 而 HDMI 只有 13.333ns。
    //   (原来标签嵌在 DYN 矩形里, 选择条件不含 Logo, 所以没暴露。)
    //
    // ★ 现在: 标签用**自己的第二个字形 ROM**, 而且把字形查表也提前:
    //       S_x/S_y --[几何]--> R1 (字符/列/行/色号/命中) --[ROM+选位]--> R2 (一位)
    //   到 2d 级只剩一个已经寄存好的 S_lbl_on_r —— 标签完全不占 O_hdmi_data 的锥。
    //   代价: 多一个字形 ROM 实例 (osd_char_lib), 换掉 5.2ns 的时序违例。
    //
    // ★ 对齐 (关键, 不能搞错):  S_x_2d(M) = S_x(M-2)
    //   所以从 S_x 出发**打两拍**: R2(M) = 几何(S_x(M-2)), 与 S_x_2d(M) 同拍同像素 ✓
    //   (原来是从 S_x_1d 出发打一拍, 总延迟同样是 2 拍, 等价。)
    // ========================================================================
    wire        C_lbl_in_r = (S_x >= S_lx_r) && (S_x < (S_lx_r + 12'd80)) &&
                             (S_y >= S_ly_r) && (S_y < (S_ly_r + 12'd16));
    wire        C_lbl_in_g = (S_x >= S_lx_g) && (S_x < (S_lx_g + 12'd80)) &&
                             (S_y >= S_ly_g) && (S_y < (S_ly_g + 12'd16));
    wire        C_lbl_in_b = (S_x >= S_lx_b) && (S_x < (S_lx_b + 12'd80)) &&
                             (S_y >= S_ly_b) && (S_y < (S_ly_b + 12'd16));
    // 优先级: 红 > 绿 > 蓝 (和框的绘制优先级一致)
    wire        C_lbl_sel_r = S_cval_r && C_lbl_in_r;
    wire        C_lbl_sel_g = (!C_lbl_sel_r) && S_cval_g && C_lbl_in_g;
    wire        C_lbl_sel_b = (!C_lbl_sel_r) && (!C_lbl_sel_g) && S_cval_b && C_lbl_in_b;

    wire        C_lbl_hit  = C_lbl_sel_r || C_lbl_sel_g || C_lbl_sel_b;
    wire [1:0]  C_lbl_cid  = C_lbl_sel_r ? 2'd0 : (C_lbl_sel_g ? 2'd1 : 2'd2);
    wire [11:0] C_lbl_lx   = C_lbl_sel_r ? S_lx_r : (C_lbl_sel_g ? S_lx_g : S_lx_b);
    wire [11:0] C_lbl_ly   = C_lbl_sel_r ? S_ly_r : (C_lbl_sel_g ? S_ly_g : S_ly_b);

    // (S_x - C_lbl_lx) 只会在命中时被用到, 那时它落在 0..79 -> >>4 = 0..4 是字序号 ✓
    wire [3:0]  C_lbl_col  = (S_x - C_lbl_lx) & 4'hf;
    wire [3:0]  C_lbl_row  = S_y - C_lbl_ly;          // 命中时落在 0..15
    wire [7:0]  C_lbl_char = F_col_char((S_x - C_lbl_lx) >> 4, C_lbl_cid);

    // ---- 第 1 级: 标签几何 ----
    reg        R1_lbl_hit;
    reg [1:0]  R1_lbl_cid;
    reg [7:0]  R1_lbl_char;
    reg [3:0]  R1_lbl_col, R1_lbl_row;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            R1_lbl_hit  <= 1'b0;
            R1_lbl_cid  <= 2'd0;
            R1_lbl_char <= 8'h20;
            R1_lbl_col  <= 4'd0;
            R1_lbl_row  <= 4'd0;
        end else begin
            R1_lbl_hit  <= C_lbl_hit;
            R1_lbl_cid  <= C_lbl_cid;
            R1_lbl_char <= C_lbl_char;
            R1_lbl_col  <= C_lbl_col;
            R1_lbl_row  <= C_lbl_row;
        end
    end

    // ---- 第 2 级: 字形查表 + 选位, 结果寄存成一位 ----
    // 独立 ROM 实例 —— **不能**和 DYN_OSD 共用 u_osd_char_lib, 因为那个的输入
    // S_pf_char 是在 2d 级由坐标比较选出来的, 共用就等于把标签又拖回那条深链。
    wire [15:0] S_lbl_rowbits;
    osd_char_lib u_lbl_char_lib(
        .I_char     ( R1_lbl_char    ),
        .I_row      ( R1_lbl_row     ),
        .O_row_bits ( S_lbl_rowbits  )
    );

    reg        S_lbl_hit_r;
    reg [1:0]  S_lbl_cid_r;
    reg        S_lbl_on_r;      // 本像素要不要点亮 (字形位), 2d 级只用这一位

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_lbl_hit_r <= 1'b0;
            S_lbl_cid_r <= 2'd0;
            S_lbl_on_r  <= 1'b0;
        end else begin
            S_lbl_hit_r <= R1_lbl_hit;
            S_lbl_cid_r <= R1_lbl_cid;
            // ★★ 必须 AND 上 R1_lbl_hit (2026-10-11 修的 bug) ——
            //   字形位 F_bit16(...) 对**任意**像素都可能为 1: C_lbl_lx/ly 在没有
            //   命中任何框时取的是蓝色框的值, 于是 (S_x - lx, S_y - ly) 满屏乱走,
            //   总会撞到某个字形的亮点上。只寄存字形位 = 整屏按字形图案被点亮,
            //   而 S_lbl_cid_r 默认是 2'd2 -> **满屏蓝色**。板上实测就是这个现象。
            //   字形位只有在"确实落在某个有效框的标签矩形内"时才算数。
            S_lbl_on_r  <= R1_lbl_hit && F_bit16(S_lbl_rowbits, R1_lbl_col);
        end
    end

    // ========================================================================
    // 颜色名标签 —— 跟着检测框走 (2026-10-10)
    //
    // 用户要求"颜色名随在框上": 标签不放在固定的一行, 而是贴在**每个检测框**上,
    // 这样一眼就能看出哪个名字对应哪个物体。标签画在框的左上角**往上一行**
    // (top-18), top 太小(贴到画面上边)就钳到 0。
    //
    // ★ 为什么单独一套: 现在所有文字渲染都走 DYN_OSD 那个固定框, 用的是**相对
    //   坐标**(S_dyn_x = S_x_2d - DYN_OSD_X)。而检测框可能在画面任何位置,
    //   所以标签必须用**绝对屏幕坐标** S_x_2d/S_y_2d 单独判。
    //   两者共用同一个字形 ROM(osd_char_lib), 所以还是同一套 S_pf_char/S_pf_row
    //   机制, 只是坐标来源不同。
    //
    // 位置同样在帧首锁存, 转换期间不动。
    // ========================================================================
    wire [11:0] D_l_r = {1'b0,  I_det_boxes[ 41: 31]};   // 左边界
    wire [11:0] D_t_r = {2'b0,  I_det_boxes[ 19: 10]};   // 上边界
    wire [11:0] D_l_g = {1'b0,  I_det_boxes[105: 95]};
    wire [11:0] D_t_g = {2'b0,  I_det_boxes[ 83: 74]};
    wire [11:0] D_l_b = {1'b0,  I_det_boxes[169:159]};
    wire [11:0] D_t_b = {2'b0,  I_det_boxes[147:138]};

    localparam [11:0] LABEL_DY = 12'd18;   // 标签在框上方多少像素

    reg [11:0] S_lx_r, S_ly_r, S_lx_g, S_ly_g, S_lx_b, S_ly_b;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_lx_r <= 12'd0; S_ly_r <= 12'd0;
            S_lx_g <= 12'd0; S_ly_g <= 12'd0;
            S_lx_b <= 12'd0; S_ly_b <= 12'd0;
        end else if(I_video_user) begin
            S_lx_r <= D_l_r;
            S_ly_r <= (D_t_r > LABEL_DY) ? (D_t_r - LABEL_DY) : 12'd0;
            S_lx_g <= D_l_g;
            S_ly_g <= (D_t_g > LABEL_DY) ? (D_t_g - LABEL_DY) : 12'd0;
            S_lx_b <= D_l_b;
            S_ly_b <= (D_t_b > LABEL_DY) ? (D_t_b - LABEL_DY) : 12'd0;
        end
    end

    function [4:0] F_logo_text_bits;
        input [3:0] I_char;
        input [2:0] I_row;
        begin
            case(I_char)
                4'd0: begin
                    case(I_row) // A
                        3'd0: F_logo_text_bits = 5'b01110;
                        3'd1: F_logo_text_bits = 5'b10001;
                        3'd2: F_logo_text_bits = 5'b10001;
                        3'd3: F_logo_text_bits = 5'b11111;
                        3'd4: F_logo_text_bits = 5'b10001;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b10001;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd1: begin
                    case(I_row) // N
                        3'd0: F_logo_text_bits = 5'b10001;
                        3'd1: F_logo_text_bits = 5'b11001;
                        3'd2: F_logo_text_bits = 5'b10101;
                        3'd3: F_logo_text_bits = 5'b10011;
                        3'd4: F_logo_text_bits = 5'b10001;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b10001;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd2: begin
                    case(I_row) // L
                        3'd0: F_logo_text_bits = 5'b10000;
                        3'd1: F_logo_text_bits = 5'b10000;
                        3'd2: F_logo_text_bits = 5'b10000;
                        3'd3: F_logo_text_bits = 5'b10000;
                        3'd4: F_logo_text_bits = 5'b10000;
                        3'd5: F_logo_text_bits = 5'b10000;
                        3'd6: F_logo_text_bits = 5'b11111;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd3: begin
                    case(I_row) // O
                        3'd0: F_logo_text_bits = 5'b01110;
                        3'd1: F_logo_text_bits = 5'b10001;
                        3'd2: F_logo_text_bits = 5'b10001;
                        3'd3: F_logo_text_bits = 5'b10001;
                        3'd4: F_logo_text_bits = 5'b10001;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b01110;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd4: begin
                    case(I_row) // G
                        3'd0: F_logo_text_bits = 5'b01110;
                        3'd1: F_logo_text_bits = 5'b10001;
                        3'd2: F_logo_text_bits = 5'b10000;
                        3'd3: F_logo_text_bits = 5'b10111;
                        3'd4: F_logo_text_bits = 5'b10001;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b01110;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd5: begin
                    case(I_row) // I
                        3'd0: F_logo_text_bits = 5'b11111;
                        3'd1: F_logo_text_bits = 5'b00100;
                        3'd2: F_logo_text_bits = 5'b00100;
                        3'd3: F_logo_text_bits = 5'b00100;
                        3'd4: F_logo_text_bits = 5'b00100;
                        3'd5: F_logo_text_bits = 5'b00100;
                        3'd6: F_logo_text_bits = 5'b11111;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd6: begin
                    case(I_row) // C
                        3'd0: F_logo_text_bits = 5'b01110;
                        3'd1: F_logo_text_bits = 5'b10001;
                        3'd2: F_logo_text_bits = 5'b10000;
                        3'd3: F_logo_text_bits = 5'b10000;
                        3'd4: F_logo_text_bits = 5'b10000;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b01110;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                default: F_logo_text_bits = 5'b00000;
            endcase
        end
    endfunction

    // 7-seg bit mapping: {a,b,c,d,e,f,g}
    function [6:0] F_hex7seg;
        input [3:0] I_hex;
        begin
            case(I_hex)
                4'h0: F_hex7seg = 7'b1111110;
                4'h1: F_hex7seg = 7'b0110000;
                4'h2: F_hex7seg = 7'b1101101;
                4'h3: F_hex7seg = 7'b1111001;
                4'h4: F_hex7seg = 7'b0110011;
                4'h5: F_hex7seg = 7'b1011011;
                4'h6: F_hex7seg = 7'b1011111;
                4'h7: F_hex7seg = 7'b1110000;
                4'h8: F_hex7seg = 7'b1111111;
                4'h9: F_hex7seg = 7'b1111011;
                4'ha: F_hex7seg = 7'b1110111;
                4'hb: F_hex7seg = 7'b0011111;
                4'hc: F_hex7seg = 7'b1001110;
                4'hd: F_hex7seg = 7'b0111101;
                4'he: F_hex7seg = 7'b1001111;
                4'hf: F_hex7seg = 7'b1000111;
                default: F_hex7seg = 7'b0000000;
            endcase
        end
    endfunction

    function [4:0] F_cnt_label_bits;
        input [1:0] I_idx;
        input [2:0] I_row;
        begin
            case(I_idx)
                2'd0: begin // C
                    case(I_row)
                        3'd0: F_cnt_label_bits = 5'b01110;
                        3'd1: F_cnt_label_bits = 5'b10001;
                        3'd2: F_cnt_label_bits = 5'b10000;
                        3'd3: F_cnt_label_bits = 5'b10000;
                        3'd4: F_cnt_label_bits = 5'b10000;
                        3'd5: F_cnt_label_bits = 5'b10001;
                        3'd6: F_cnt_label_bits = 5'b01110;
                        default: F_cnt_label_bits = 5'b00000;
                    endcase
                end
                2'd1: begin // N
                    case(I_row)
                        3'd0: F_cnt_label_bits = 5'b10001;
                        3'd1: F_cnt_label_bits = 5'b11001;
                        3'd2: F_cnt_label_bits = 5'b10101;
                        3'd3: F_cnt_label_bits = 5'b10011;
                        3'd4: F_cnt_label_bits = 5'b10001;
                        3'd5: F_cnt_label_bits = 5'b10001;
                        3'd6: F_cnt_label_bits = 5'b10001;
                        default: F_cnt_label_bits = 5'b00000;
                    endcase
                end
                2'd2: begin // T
                    case(I_row)
                        3'd0: F_cnt_label_bits = 5'b11111;
                        3'd1: F_cnt_label_bits = 5'b00100;
                        3'd2: F_cnt_label_bits = 5'b00100;
                        3'd3: F_cnt_label_bits = 5'b00100;
                        3'd4: F_cnt_label_bits = 5'b00100;
                        3'd5: F_cnt_label_bits = 5'b00100;
                        3'd6: F_cnt_label_bits = 5'b00100;
                        default: F_cnt_label_bits = 5'b00000;
                    endcase
                end
                default: begin // ':'
                    case(I_row)
                        3'd2: F_cnt_label_bits = 5'b00100;
                        3'd5: F_cnt_label_bits = 5'b00100;
                        default: F_cnt_label_bits = 5'b00000;
                    endcase
                end
            endcase
        end
    endfunction

    // Minimal 16x16 Chinese bitmap rows for "an" and "lu".
    function [15:0] F_cn16_row;
        input I_char; // 0: an, 1: lu
        input [3:0] I_row;
        begin
            if(!I_char) begin
                case(I_row)
                    4'd0:  F_cn16_row = 16'h0200;
                    4'd1:  F_cn16_row = 16'h7ff0;
                    4'd2:  F_cn16_row = 16'h4410;
                    4'd3:  F_cn16_row = 16'h0400;
                    4'd4:  F_cn16_row = 16'h7ff0;
                    4'd5:  F_cn16_row = 16'h0840;
                    4'd6:  F_cn16_row = 16'h1040;
                    4'd7:  F_cn16_row = 16'h1c80;
                    4'd8:  F_cn16_row = 16'h0300;
                    4'd9:  F_cn16_row = 16'h0cc0;
                    4'd10: F_cn16_row = 16'h7020;
                    4'd11: F_cn16_row = 16'h0000;
                    4'd12: F_cn16_row = 16'h0000;
                    4'd13: F_cn16_row = 16'h0000;
                    4'd14: F_cn16_row = 16'h0000;
                    4'd15: F_cn16_row = 16'h0000;
                    default: F_cn16_row = 16'h0000;
                endcase
            end
            else begin
                case(I_row)
                    4'd0:  F_cn16_row = 16'h79e0;
                    4'd1:  F_cn16_row = 16'h4a20;
                    4'd2:  F_cn16_row = 16'h4d40;
                    4'd3:  F_cn16_row = 16'h7880;
                    4'd4:  F_cn16_row = 16'h1140;
                    4'd5:  F_cn16_row = 16'h1630;
                    4'd6:  F_cn16_row = 16'h5be0;
                    4'd7:  F_cn16_row = 16'h5220;
                    4'd8:  F_cn16_row = 16'h5220;
                    4'd9:  F_cn16_row = 16'h5be0;
                    4'd10: F_cn16_row = 16'h6220;
                    4'd11: F_cn16_row = 16'h0000;
                    4'd12: F_cn16_row = 16'h0000;
                    4'd13: F_cn16_row = 16'h0000;
                    4'd14: F_cn16_row = 16'h0000;
                    4'd15: F_cn16_row = 16'h0000;
                    default: F_cn16_row = 16'h0000;
                endcase
            end
        end
    endfunction

    function [4:0] F_dyn_char_bits;
        input [3:0] I_char;
        input [2:0] I_row;
        begin
            case(I_char)
                4'h0: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10011; 3'd3:F_dyn_char_bits=5'b10101; 3'd4:F_dyn_char_bits=5'b11001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h1: begin case(I_row) 3'd0:F_dyn_char_bits=5'b00100; 3'd1:F_dyn_char_bits=5'b01100; 3'd2:F_dyn_char_bits=5'b00100; 3'd3:F_dyn_char_bits=5'b00100; 3'd4:F_dyn_char_bits=5'b00100; 3'd5:F_dyn_char_bits=5'b00100; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h2: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b00001; 3'd3:F_dyn_char_bits=5'b00110; 3'd4:F_dyn_char_bits=5'b01000; 3'd5:F_dyn_char_bits=5'b10000; 3'd6:F_dyn_char_bits=5'b11111; default:F_dyn_char_bits=5'b00000; endcase end
                4'h3: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11110; 3'd1:F_dyn_char_bits=5'b00001; 3'd2:F_dyn_char_bits=5'b00001; 3'd3:F_dyn_char_bits=5'b01110; 3'd4:F_dyn_char_bits=5'b00001; 3'd5:F_dyn_char_bits=5'b00001; 3'd6:F_dyn_char_bits=5'b11110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h4: begin case(I_row) 3'd0:F_dyn_char_bits=5'b00010; 3'd1:F_dyn_char_bits=5'b00110; 3'd2:F_dyn_char_bits=5'b01010; 3'd3:F_dyn_char_bits=5'b10010; 3'd4:F_dyn_char_bits=5'b11111; 3'd5:F_dyn_char_bits=5'b00010; 3'd6:F_dyn_char_bits=5'b00010; default:F_dyn_char_bits=5'b00000; endcase end
                4'h5: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11111; 3'd1:F_dyn_char_bits=5'b10000; 3'd2:F_dyn_char_bits=5'b11110; 3'd3:F_dyn_char_bits=5'b00001; 3'd4:F_dyn_char_bits=5'b00001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h6: begin case(I_row) 3'd0:F_dyn_char_bits=5'b00110; 3'd1:F_dyn_char_bits=5'b01000; 3'd2:F_dyn_char_bits=5'b10000; 3'd3:F_dyn_char_bits=5'b11110; 3'd4:F_dyn_char_bits=5'b10001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h7: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11111; 3'd1:F_dyn_char_bits=5'b00001; 3'd2:F_dyn_char_bits=5'b00010; 3'd3:F_dyn_char_bits=5'b00100; 3'd4:F_dyn_char_bits=5'b01000; 3'd5:F_dyn_char_bits=5'b01000; 3'd6:F_dyn_char_bits=5'b01000; default:F_dyn_char_bits=5'b00000; endcase end
                4'h8: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10001; 3'd3:F_dyn_char_bits=5'b01110; 3'd4:F_dyn_char_bits=5'b10001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h9: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10001; 3'd3:F_dyn_char_bits=5'b01111; 3'd4:F_dyn_char_bits=5'b00001; 3'd5:F_dyn_char_bits=5'b00010; 3'd6:F_dyn_char_bits=5'b11100; default:F_dyn_char_bits=5'b00000; endcase end
                4'ha: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10001; 3'd3:F_dyn_char_bits=5'b11111; 3'd4:F_dyn_char_bits=5'b10001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b10001; default:F_dyn_char_bits=5'b00000; endcase end
                4'hb: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10001; 3'd3:F_dyn_char_bits=5'b11110; 3'd4:F_dyn_char_bits=5'b10001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b11110; default:F_dyn_char_bits=5'b00000; endcase end
                4'hc: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10000; 3'd3:F_dyn_char_bits=5'b10000; 3'd4:F_dyn_char_bits=5'b10000; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'hd: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10001; 3'd3:F_dyn_char_bits=5'b10001; 3'd4:F_dyn_char_bits=5'b10001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b11110; default:F_dyn_char_bits=5'b00000; endcase end
                4'he: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11111; 3'd1:F_dyn_char_bits=5'b10000; 3'd2:F_dyn_char_bits=5'b10000; 3'd3:F_dyn_char_bits=5'b11110; 3'd4:F_dyn_char_bits=5'b10000; 3'd5:F_dyn_char_bits=5'b10000; 3'd6:F_dyn_char_bits=5'b11111; default:F_dyn_char_bits=5'b00000; endcase end
                4'hf: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11111; 3'd1:F_dyn_char_bits=5'b10000; 3'd2:F_dyn_char_bits=5'b10000; 3'd3:F_dyn_char_bits=5'b11110; 3'd4:F_dyn_char_bits=5'b10000; 3'd5:F_dyn_char_bits=5'b10000; 3'd6:F_dyn_char_bits=5'b10000; default:F_dyn_char_bits=5'b00000; endcase end
                default: F_dyn_char_bits = 5'b00000;
            endcase
        end
    endfunction

    // Unified prefix character library (16x16 rows): an/lu/C/N/T/:
    function [15:0] F_osd_char16_row;
        input [7:0] I_char;
        input [3:0] I_row;
        begin
            case(I_char)
                CHAR_AN: begin
                    case(I_row)
                        4'd0:  F_osd_char16_row = 16'h0200;
                        4'd1:  F_osd_char16_row = 16'h7ff0;
                        4'd2:  F_osd_char16_row = 16'h4410;
                        4'd3:  F_osd_char16_row = 16'h0400;
                        4'd4:  F_osd_char16_row = 16'h7ff0;
                        4'd5:  F_osd_char16_row = 16'h0840;
                        4'd6:  F_osd_char16_row = 16'h1040;
                        4'd7:  F_osd_char16_row = 16'h1c80;
                        4'd8:  F_osd_char16_row = 16'h0300;
                        4'd9:  F_osd_char16_row = 16'h0cc0;
                        4'd10: F_osd_char16_row = 16'h7020;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_LU: begin
                    case(I_row)
                        4'd0:  F_osd_char16_row = 16'h79e0;
                        4'd1:  F_osd_char16_row = 16'h4a20;
                        4'd2:  F_osd_char16_row = 16'h4d40;
                        4'd3:  F_osd_char16_row = 16'h7880;
                        4'd4:  F_osd_char16_row = 16'h1140;
                        4'd5:  F_osd_char16_row = 16'h1630;
                        4'd6:  F_osd_char16_row = 16'h5be0;
                        4'd7:  F_osd_char16_row = 16'h5220;
                        4'd8:  F_osd_char16_row = 16'h5220;
                        4'd9:  F_osd_char16_row = 16'h5be0;
                        4'd10: F_osd_char16_row = 16'h6220;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_C: begin
                    case(I_row)
                        4'd2:  F_osd_char16_row = 16'h03f0;
                        4'd3:  F_osd_char16_row = 16'h0c0c;
                        4'd4:  F_osd_char16_row = 16'h1800;
                        4'd5:  F_osd_char16_row = 16'h3000;
                        4'd6:  F_osd_char16_row = 16'h3000;
                        4'd7:  F_osd_char16_row = 16'h3000;
                        4'd8:  F_osd_char16_row = 16'h3000;
                        4'd9:  F_osd_char16_row = 16'h3000;
                        4'd10: F_osd_char16_row = 16'h1800;
                        4'd11: F_osd_char16_row = 16'h0c0c;
                        4'd12: F_osd_char16_row = 16'h03f0;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_N: begin
                    case(I_row)
                        4'd2:  F_osd_char16_row = 16'h300c;
                        4'd3:  F_osd_char16_row = 16'h380c;
                        4'd4:  F_osd_char16_row = 16'h3c0c;
                        4'd5:  F_osd_char16_row = 16'h360c;
                        4'd6:  F_osd_char16_row = 16'h330c;
                        4'd7:  F_osd_char16_row = 16'h318c;
                        4'd8:  F_osd_char16_row = 16'h30cc;
                        4'd9:  F_osd_char16_row = 16'h306c;
                        4'd10: F_osd_char16_row = 16'h303c;
                        4'd11: F_osd_char16_row = 16'h301c;
                        4'd12: F_osd_char16_row = 16'h300c;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_T: begin
                    case(I_row)
                        4'd2:  F_osd_char16_row = 16'h3ffc;
                        4'd3:  F_osd_char16_row = 16'h03c0;
                        4'd4:  F_osd_char16_row = 16'h03c0;
                        4'd5:  F_osd_char16_row = 16'h03c0;
                        4'd6:  F_osd_char16_row = 16'h03c0;
                        4'd7:  F_osd_char16_row = 16'h03c0;
                        4'd8:  F_osd_char16_row = 16'h03c0;
                        4'd9:  F_osd_char16_row = 16'h03c0;
                        4'd10: F_osd_char16_row = 16'h03c0;
                        4'd11: F_osd_char16_row = 16'h03c0;
                        4'd12: F_osd_char16_row = 16'h03c0;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_COLON: begin
                    case(I_row)
                        4'd6:  F_osd_char16_row = 16'h0180;
                        4'd7:  F_osd_char16_row = 16'h0180;
                        4'd10: F_osd_char16_row = 16'h0180;
                        4'd11: F_osd_char16_row = 16'h0180;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                default: F_osd_char16_row = 16'h0000;
            endcase
        end
    endfunction

    assign O_video_rd_en = I_video_de;

    // ========================================================================
    // Logo (安路图标) 的 ROM 读 —— 拆成两级寄存 (2026-10-11, 第二次改)
    //
    // ★ 为什么必须拆: 第一版把「比较 + 地址 + ROM 读出」整块挪到 1d 级, 结果
    //   瓶颈跟着挪过去了 —— 实测那条路径变成
    //       S_x_1d → 地址(2 级加法器) → Logo ROM 内部 mux 树 → S_logo_col_r
    //       12 级 / 12.96ns  (预算只有 13.333ns)
    //   也就是「地址计算 + 160x160 组合 ROM」本身就要 ~13ns。合成在一拍里,
    //   放哪一级都不够, 必须劈开。
    //
    // ★ 两级 + 使用:
    //   第 1 级 (由 S_x/S_y 算): 矩形比较 + 地址移位加法  -> 寄存
    //   第 2 级:                ROM 读出               -> 寄存成 S_logo_on_r
    //   2d 级:                  直接用 S_logo_on_r (一个 if)
    //
    // ★ 对齐 (关键): S_x_2d(M) = S_x(M-2)。从 **S_x** 出发打两拍, 得到
    //   S_logo_on_r(M) = f(S_x(M-2)) —— 与 S_x_2d(M) 同拍同像素 ✓
    //   和颜色名标签用的是同一套 0d→1d→2d 拆分, 无像素位移。
    //
    // ★ 地址用移位加法而不是乘法: LOGO_W=160=128+32 -> y*160 = (y<<7)+(y<<5)。
    //   原来写 "S_logo_y * LOGO_W" 时工具推断出了一个 DSP 乘法器 (2026-10-07 记录)。
    //   位宽: y 最大 159, 159*160 = 25440 -> 15 位够 (ROM 地址就是 15 位)。
    //   C_logo_in 为假时地址会溢出回绕, 但那时 R1_logo_in=0 -> S_logo_on_r 必为 0。
    // ========================================================================
    wire        C_logo_in   = (S_x >= LOGO_X) && (S_x < (LOGO_X + LOGO_W)) &&
                              (S_y >= LOGO_Y) && (S_y < (LOGO_Y + LOGO_H));
    wire [11:0] C_logo_x    = S_x - LOGO_X;
    wire [11:0] C_logo_y    = S_y - LOGO_Y;
    wire [14:0] C_logo_addr = (C_logo_y << 7) + (C_logo_y << 5) + C_logo_x;

    // ---- 第 1 级: 在不在 Logo 区内 + ROM 地址 ----
    reg        R1_logo_in;
    reg [14:0] R1_logo_addr;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            R1_logo_in   <= 1'b0;
            R1_logo_addr <= 15'd0;
        end else begin
            // I_logo_en 也在这里并进去 —— 按键"一键清屏"要图标和文字一起消失
            R1_logo_in   <= I_logo_en && C_logo_in;
            R1_logo_addr <= C_logo_addr;
        end
    end

    // ---- 第 2 级: ROM 读出 ----
    wire [24:0] C_logo_pixel;
    anlogic_logo_rom u_anlogic_logo_rom(
        .I_addr  ( R1_logo_addr  ),
        .O_pixel ( C_logo_pixel  )
    );

    reg        S_logo_on_r;      // 本像素要不要画 Logo
    reg [23:0] S_logo_col_r;     // Logo 像素颜色

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_logo_on_r  <= 1'b0;
            S_logo_col_r <= 24'd0;
        end else begin
            S_logo_on_r  <= R1_logo_in && C_logo_pixel[24];
            S_logo_col_r <= C_logo_pixel[23:0];
        end
    end

    osd_char_lib u_osd_char_lib(
        .I_char     ( S_pf_char     ),
        .I_row      ( S_pf_row      ),
        .O_row_bits ( S_pf_row_bits )
    );

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_x <= 12'd0;
            S_y <= 12'd0;
        end
        else if(I_video_user) begin
            S_x <= 12'd0;
            S_y <= 12'd0;
        end
        else if(I_video_de) begin
            if(I_video_last) begin
                S_x <= 12'd0;
                S_y <= S_y + 12'd1;
            end
            else begin
                S_x <= S_x + 12'd1;
            end
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_frame_cnt <= 32'd0;
            S_cnt_d0 <= 4'd0;
            S_cnt_d1 <= 4'd0;
            S_cnt_d2 <= 4'd0;
            S_cnt_d3 <= 4'd0;
            S_cnt_d4 <= 4'd0;
            S_cnt_d5 <= 4'd0;
        end
        else if(I_video_user) begin
            S_frame_cnt <= S_frame_cnt + 32'd1;
            if(S_cnt_d0 == 4'd9) begin
                S_cnt_d0 <= 4'd0;
                if(S_cnt_d1 == 4'd9) begin
                    S_cnt_d1 <= 4'd0;
                    if(S_cnt_d2 == 4'd9) begin
                        S_cnt_d2 <= 4'd0;
                        if(S_cnt_d3 == 4'd9) begin
                            S_cnt_d3 <= 4'd0;
                            if(S_cnt_d4 == 4'd9) begin
                                S_cnt_d4 <= 4'd0;
                                if(S_cnt_d5 == 4'd9)
                                    S_cnt_d5 <= 4'd0;
                                else
                                    S_cnt_d5 <= S_cnt_d5 + 4'd1;
                            end
                            else
                                S_cnt_d4 <= S_cnt_d4 + 4'd1;
                        end
                        else
                            S_cnt_d3 <= S_cnt_d3 + 4'd1;
                    end
                    else
                        S_cnt_d2 <= S_cnt_d2 + 4'd1;
                end
                else
                    S_cnt_d1 <= S_cnt_d1 + 4'd1;
            end
            else
                S_cnt_d0 <= S_cnt_d0 + 4'd1;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_x_1d <= 12'd0;
            S_x_2d <= 12'd0;
            S_y_1d <= 12'd0;
            S_y_2d <= 12'd0;
        end
        else begin
            S_x_1d <= S_x;
            S_x_2d <= S_x_1d;
            S_y_1d <= S_y;
            S_y_2d <= S_y_1d;
        end
    end

    always @(*) begin
        S_osd_hit   = 1'b0;
        S_osd_color = 24'd0;

        S_char_idx = 4'd0;
        S_char_row = 3'd0;
        S_char_col = 3'd0;
        S_char_bits = 5'd0;
        S_char_on = 1'b0;
        S_logo_blue_on = 1'b0;
        S_logo_red_on = 1'b0;
        S_logo_tmp_y = 12'd0;
        S_logo_red_band = 4'd0;
        S_logo_red_x_start = 12'd0;
        S_logo_red_x_end = 12'd0;
        S_dyn_x = 12'd0;
        S_dyn_y = 12'd0;
        S_dyn_char = 4'd0;
        S_dyn_col = 3'd0;
        S_dyn_row = 3'd0;
        S_dyn_bits = 5'd0;
        S_dyn_on = 1'b0;
        S_dyn_digit_idx = 4'd0;
        S_dyn_digit_x = 12'd0;
        S_dyn_seg = 7'd0;
        S_lbl_row = 3'd0;
        S_lbl_col = 3'd0;
        S_lbl_idx = 2'd0;
        S_lbl_bits = 5'd0;
        S_lbl_local_x = 7'd0;
        S_dyn_dec_digit = 4'd0;
        S_cn_local_x = 5'd0;
        S_cn_local_y = 5'd0;
        S_cn_col = 4'd0;
        S_cn_row = 4'd0;
        S_cn_row_bits = 16'd0;
        S_cn_on = 1'b0;
        S_cn_scale_x = 10'd0;
        S_cn_scale_y = 10'd0;
        S_pf_char = 8'd0;
        S_pf_local_x = 5'd0;
        S_pf_local_y = 5'd0;
        S_pf_col = 4'd0;
        S_pf_row = 4'd0;
        S_pf_on = 1'b0;
        S_pf_scale_x = 10'd0;
        S_pf_scale_y = 10'd0;

        if(S_video_de_2d) begin
            // ---- 质心十字 (2026-10-10) ------------------------------------
            // 优先级最高: 画在 Logo 和文字之上, 保证一定看得见。
            // S_cross_1d **是寄存过的**, 所以这里只是往 S_osd_hit 里或一项,
            // 不给临界路径加比较链。
            // ★ 2026-10-11: 加模式门控 —— 十字是"跟踪标识", 只在跟踪模式(3)出现。
            //   原来没有这个条件, 四种模式全都在画; 标签同理。用户实测反馈
            //   "除了 trace 其他情况不要出现框跟标签"。框本来就在 ISP 域的
            //   box_overlay 里被 I_bypass 挡住了, 只有这两个 HDMI 域的叠加物漏了。
            if((S_mode_r == 3'd3) && S_cross_1d) begin
                S_osd_hit   = 1'b1;
                S_osd_color = 24'hffffff;
            end

            // 2026-10-11: Logo ROM 已经挪到 1d 级并寄存 (见上面 u_anlogic_logo_rom
            // 那段)。这里只把寄存好的结果并进 OSD —— 不再做坐标比较、地址计算和
            // ROM 读, 所以这条不再是 O_hdmi_data 的锥 (原来它是 16 级里最尾的 4 级)。
            // I_logo_en 的门控也已经并进 S_logo_on_r 里了。
            if(S_logo_on_r) begin
                S_osd_hit   = 1'b1;
                S_osd_color = S_logo_col_r;
            end

            // 2026-10-10: DYN_OSD 文字也受 I_logo_en 门控 —— 按键要"一键清屏"
            // (图标和文字一起消失)。原来这里没有 I_logo_en, 所以按键只让图标消失、
            // 文字还留在画面上。
            if(I_logo_en && (!S_osd_hit) &&
               (S_x_2d >= DYN_OSD_X) && (S_x_2d < (DYN_OSD_X + DYN_OSD_W)) &&
               (S_y_2d >= DYN_OSD_Y) && (S_y_2d < (DYN_OSD_Y + DYN_OSD_H))) begin
                S_dyn_x = S_x_2d - DYN_OSD_X;
                S_dyn_y = S_y_2d - DYN_OSD_Y;

                // Unified prefix render using one character library.
                // an:[0..23], lu:[24..47], C:[52..67], N:[68..83], T:[84..99], :[100..107]
                // ★ 2026-10-10: 这个外层守卫原来写的是 x < 108 —— 那是"安路 + CNT:"
                //   那套内容的总宽度。改成模式名之后内容一直排到 x=212, 守卫没跟着
                //   改, 结果**只画出前 4 个字符 "MODE", 模式名整个被截掉**。
                //   守卫的 x 和 y 都必须 >= 里面所有分支的最右/最下边界 ——
                //   加了三行颜色名之后 y 也要放到 DYN_OSD_H(108)。
                // ★ 2026-10-10: 字符解码已经挪到 1d 级并寄存 (见 S_dosd_*_r 那段),
                //   这里只剩 ROM 读 + 选位。原来那一大块直接在本拍算
                //   (相对坐标 → 安路缩放/模式名字符 → ROM → 选位 → 合成),
                //   实测是 HDMI 域 **18 级 / 14.140ns** 的最差路径。
                //   下面用 `1'b0 &&` 把它关掉 —— 常量假, 综合会整块裁掉,
                //   留着只是为了对照, 将来要删可以删。
                if(S_dosd_hit_r) begin
                    S_pf_char = S_dosd_char_r;
                    S_pf_col  = S_dosd_col_r;
                    S_pf_row  = S_dosd_row_r;
                    if(F_bit16(S_pf_row_bits, S_pf_col)) S_dyn_on = 1'b1;
                end
                else if(1'b0 && (S_dyn_x < 12'd244) && (S_dyn_y < DYN_OSD_H)) begin
                    // ★ 2026-10-10: "安路"这一支**必须加显式 y 范围**。
                    //   它靠内部的 (S_pf_local_y < 24) 判断"在字形内", 而 OSD 高度
                    //   从 24 提到 108 之后 S_dyn_y 能到 107, 一旦 S_pf_local_y
                    //   溢出回绕就会在 y=34/66/98 附近重复画出"安路"。
                    //   (已经同时把 S_pf_local_y 从 4 位加宽到 7 位 —— 两道一起才有
                    //    保证: 加宽解决溢出, 这个范围解决"以后谁再调 DYN_OSD_H"。)
                    if( ((S_dyn_x < 12'd24) || ((S_dyn_x >= 12'd24) && (S_dyn_x < 12'd48))) &&
                        (S_dyn_y >= CN_Y_OFFSET) && (S_dyn_y < (CN_Y_OFFSET + 12'd24)) ) begin
                        if(S_dyn_y >= CN_Y_OFFSET)
                            S_pf_local_y = S_dyn_y - CN_Y_OFFSET;
                        else
                            S_pf_local_y = 5'd31;

                        if(S_dyn_x < 12'd24) begin
                            S_pf_char = CHAR_AN;
                            S_pf_local_x = S_dyn_x;
                        end
                        else begin
                            S_pf_char = CHAR_LU;
                            S_pf_local_x = S_dyn_x - 12'd24;
                        end

                        if((S_pf_local_x < 5'd24) && (S_pf_local_y < 5'd24)) begin
                            // ★ 2026-10-10: 原来是 "乘 16 再除以 24" —— 那个除法是
                            //   真的除法器, 组合深度不小。local_x/local_y 只有 0..23,
                            //   直接查表 (见 F_scale24to16 的说明)。
                            S_pf_col = F_scale24to16(S_pf_local_x);
                            S_pf_row = F_scale24to16(S_pf_local_y[4:0]);
                            case(S_pf_col)
                                4'd0:  S_pf_on = S_pf_row_bits[15];
                                4'd1:  S_pf_on = S_pf_row_bits[14];
                                4'd2:  S_pf_on = S_pf_row_bits[13];
                                4'd3:  S_pf_on = S_pf_row_bits[12];
                                4'd4:  S_pf_on = S_pf_row_bits[11];
                                4'd5:  S_pf_on = S_pf_row_bits[10];
                                4'd6:  S_pf_on = S_pf_row_bits[9];
                                4'd7:  S_pf_on = S_pf_row_bits[8];
                                4'd8:  S_pf_on = S_pf_row_bits[7];
                                4'd9:  S_pf_on = S_pf_row_bits[6];
                                4'd10: S_pf_on = S_pf_row_bits[5];
                                4'd11: S_pf_on = S_pf_row_bits[4];
                                4'd12: S_pf_on = S_pf_row_bits[3];
                                4'd13: S_pf_on = S_pf_row_bits[2];
                                4'd14: S_pf_on = S_pf_row_bits[1];
                                4'd15: S_pf_on = S_pf_row_bits[0];
                                default: S_pf_on = 1'b0;
                            endcase
                        end
                    end
                    // ---- 模式名 (2026-10-10) ------------------------------
                    // 这一段原来是 "CNT:" + 6 位帧计数 (x 52..200)。现在改成显示
                    // 当前模式 —— 进阶要求 2.5(1) 的"在画面中显示当前算法状态"。
                    // 10 个 16x16 字符, x 从 52 到 212。
                    // ★ 这一支在 if 链里排在前面, 覆盖了 x 52..212, 所以后面那两段
                    //   (":" 在 100..108、6 位数字在 110..200) 自动不可达 —— 不用删,
                    //   也不会再画出东西来。
                    else if((S_dyn_x >= 12'd52) && (S_dyn_x < 12'd244) &&
                            (S_dyn_y >= 12'd4) && (S_dyn_y < 12'd20)) begin
                        S_pf_char = F_mode_char((S_dyn_x - 12'd52) >> 4, S_mode_r);
                        S_pf_col  = (S_dyn_x - 12'd52) & 4'hf;
                        S_pf_row  = (S_dyn_y - 12'd4);      // 0..15, 收进 4 位正好
                        S_pf_on   = F_bit16(S_pf_row_bits, S_pf_col);
                    end
                    // ★ 2026-10-10: 原来这里有 RED/GREEN/BLUE 三行固定文字, 现在
                    //   改成**贴在各自检测框上**的标签了(见下面"颜色名标签"那段)。
                    //   OSD 这一块只留"安路 MODE xxx"一行, 不再占四行。
                    else if((S_dyn_x >= 12'd100) && (S_dyn_x < 12'd108) && (S_dyn_y >= 12'd4) && (S_dyn_y < 12'd20)) begin
                        S_pf_char = CHAR_COLON;
                        S_pf_local_x = S_dyn_x - 12'd100;
                        S_pf_local_y = S_dyn_y - 12'd4;
                        S_pf_scale_x = S_pf_local_x * 10'd16;
                        S_pf_col = S_pf_scale_x / 10'd8;
                        S_pf_row = S_pf_local_y[3:0];
                        case(S_pf_col)
                            4'd0:  S_pf_on = S_pf_row_bits[15];
                            4'd1:  S_pf_on = S_pf_row_bits[14];
                            4'd2:  S_pf_on = S_pf_row_bits[13];
                            4'd3:  S_pf_on = S_pf_row_bits[12];
                            4'd4:  S_pf_on = S_pf_row_bits[11];
                            4'd5:  S_pf_on = S_pf_row_bits[10];
                            4'd6:  S_pf_on = S_pf_row_bits[9];
                            4'd7:  S_pf_on = S_pf_row_bits[8];
                            4'd8:  S_pf_on = S_pf_row_bits[7];
                            4'd9:  S_pf_on = S_pf_row_bits[6];
                            4'd10: S_pf_on = S_pf_row_bits[5];
                            4'd11: S_pf_on = S_pf_row_bits[4];
                            4'd12: S_pf_on = S_pf_row_bits[3];
                            4'd13: S_pf_on = S_pf_row_bits[2];
                            4'd14: S_pf_on = S_pf_row_bits[1];
                            4'd15: S_pf_on = S_pf_row_bits[0];
                            default: S_pf_on = 1'b0;
                        endcase
                    end

                    if(S_pf_on)
                        S_dyn_on = 1'b1;
                end

                // 帧计数 6 位数 (x 110..200, 每位 15x24)。
                // ★ 2026-10-10: 那一行位置改用来显示模式名之后, 这块不再使用。
                //   注意它**不是**上面那条 else-if 链的一支, 而是独立的 if ——
                //   所以把上面那支的 x 范围写宽**挡不住它**, 必须在这里显式关掉,
                //   否则模式名和帧计数会叠在同一片区域上一起画。
                //   要恢复帧计数: 把 CNT_DIGITS_EN 改回 1'b1 (并注意别和模式名重叠)。
                if(CNT_DIGITS_EN && (S_dyn_x >= 12'd110) && (S_dyn_x < 12'd200)) begin
                    if(S_dyn_x < 12'd125) begin
                        S_dyn_digit_idx = 4'd0;
                        S_dyn_digit_x = S_dyn_x - 12'd110;
                        S_dyn_dec_digit = S_cnt_d5;
                    end
                    else if(S_dyn_x < 12'd140) begin
                        S_dyn_digit_idx = 4'd1;
                        S_dyn_digit_x = S_dyn_x - 12'd125;
                        S_dyn_dec_digit = S_cnt_d4;
                    end
                    else if(S_dyn_x < 12'd155) begin
                        S_dyn_digit_idx = 4'd2;
                        S_dyn_digit_x = S_dyn_x - 12'd140;
                        S_dyn_dec_digit = S_cnt_d3;
                    end
                    else if(S_dyn_x < 12'd170) begin
                        S_dyn_digit_idx = 4'd3;
                        S_dyn_digit_x = S_dyn_x - 12'd155;
                        S_dyn_dec_digit = S_cnt_d2;
                    end
                    else if(S_dyn_x < 12'd185) begin
                        S_dyn_digit_idx = 4'd4;
                        S_dyn_digit_x = S_dyn_x - 12'd170;
                        S_dyn_dec_digit = S_cnt_d1;
                    end
                    else begin
                        S_dyn_digit_idx = 4'd5;
                        S_dyn_digit_x = S_dyn_x - 12'd185;
                        S_dyn_dec_digit = S_cnt_d0;
                    end

                    // Render decimal digits through unified 16x16 character library.
                    // Keep enlarged 15x24 box for readability.
                    if((S_dyn_digit_x < 12'd15) && (S_dyn_y < 12'd24)) begin
                        S_pf_char = CHAR_0 + {4'd0, S_dyn_dec_digit};
                        S_pf_local_x = S_dyn_digit_x[4:0];
                        S_pf_local_y = S_dyn_y[4:0];
                        S_pf_scale_x = S_pf_local_x * 10'd16;
                        S_pf_scale_y = S_pf_local_y * 10'd16;
                        S_pf_col = S_pf_scale_x / 10'd15;
                        S_pf_row = S_pf_scale_y / 10'd24;
                        case(S_pf_col)
                            4'd0:  S_pf_on = S_pf_row_bits[15];
                            4'd1:  S_pf_on = S_pf_row_bits[14];
                            4'd2:  S_pf_on = S_pf_row_bits[13];
                            4'd3:  S_pf_on = S_pf_row_bits[12];
                            4'd4:  S_pf_on = S_pf_row_bits[11];
                            4'd5:  S_pf_on = S_pf_row_bits[10];
                            4'd6:  S_pf_on = S_pf_row_bits[9];
                            4'd7:  S_pf_on = S_pf_row_bits[8];
                            4'd8:  S_pf_on = S_pf_row_bits[7];
                            4'd9:  S_pf_on = S_pf_row_bits[6];
                            4'd10: S_pf_on = S_pf_row_bits[5];
                            4'd11: S_pf_on = S_pf_row_bits[4];
                            4'd12: S_pf_on = S_pf_row_bits[3];
                            4'd13: S_pf_on = S_pf_row_bits[2];
                            4'd14: S_pf_on = S_pf_row_bits[1];
                            4'd15: S_pf_on = S_pf_row_bits[0];
                            default: S_pf_on = 1'b0;
                        endcase
                        if(S_pf_on)
                            S_dyn_on = 1'b1;
                    end
                end

                if(S_dyn_on) begin
                    S_osd_hit = 1'b1;
                    S_osd_color = COLOR_DYN_TEXT;
                end
            end

            // ---- 颜色名标签, 贴在各自的检测框上 (2026-10-10, 2026-10-11 修) ----
            // ★★ 2026-10-11 修的 bug (板子上"红绿蓝全都没有标签"的根因):
            //   这一段原来放在**上面那个 DYN_OSD 矩形 if 的内部**(缩进 16 级)。
            //   后果: 标签只在"当前像素同时落在 DYN_OSD 那一小块
            //   (DYN_OSD_X..X+W = 375..639, DYN_OSD_Y..Y+H = 120..146)"时才会被
            //   求值 —— 而标签的坐标来自检测框, 在画面任何地方。两者几乎永不重合,
            //   所以三个颜色的标签一个都画不出来 (而 MODE 那行文字是好的, 因为
            //   它本来就该画在那块矩形里)。
            //   现在提到 if(S_video_de_2d) 这一级, 与十字/Logo/DYN_OSD 平级。
            //   标签自己的 x/y 判定在 1d 级 (见上面 S_lbl_*_r 那段) 已经做过了。
            //
            // 优先级: 十字 > Logo > MODE 文字 > 颜色名标签 (标签最低, 不盖任何东西)。
            //   !S_osd_hit 比原来的 !S_dyn_on 更严格: S_dyn_on 只在 DYN_OSD 矩形内
            //   才可能为 1, 而 S_osd_hit 把十字和 Logo 也算进去了。
            // 仍然保留 I_logo_en 门控 —— 按键要求"一键清屏", 图标和所有文字一起消失。
            //
            // 颜色: 用已经寄存好的 S_lbl_cid_r 选, 不置 S_dyn_on。
            //   置 S_dyn_on 会让上面的 `if(S_dyn_on) S_osd_color=COLOR_DYN_TEXT`
            //   把颜色盖成统一的黄色, 三个标签又分不出来了。
            // ★ 这里**不碰 S_pf_char/S_pf_col/S_pf_row, 也不读字形 ROM** —— 字形位
            //   S_lbl_on_r 在上一级就已经查好寄存了。这两条"不"正是这条路径从
            //   24 级 / 18.3ns 降下来的原因: 一旦碰 S_pf_*, 就会反过来驱动 ROM 的输入,
            //   和 Logo ROM 的输出串成一条深链 (详见上面 S_lbl_on_r 那段的说明)。
            // ★ 2026-10-11: 加模式门控 (I_mode == 2'd3) —— 颜色名标签是跟踪标识,
            //   只在跟踪模式出现。原来漏了这个条件, 其它三种模式下标签还在画,
            //   而没有框可贴, 就孤零零浮在画面里 —— 用户报的"其它模式也有框跟标签"。
            if((S_mode_r == 3'd3) && I_logo_en && (!S_osd_hit) && S_lbl_on_r) begin
                S_osd_hit   = 1'b1;
                S_osd_color = (S_lbl_cid_r == 2'd0) ? 24'hff4040 :   // RED
                              (S_lbl_cid_r == 2'd1) ? 24'h40ff40 :   // GREEN
                                                      24'h6080ff;    // BLUE
            end
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_video_vsync_1d <= 1'b0;
            S_video_vsync_2d <= 1'b0;
            S_video_hsync_1d <= 1'b0;
            S_video_hsync_2d <= 1'b0;
            S_video_de_1d    <= 1'b0;
            S_video_de_2d    <= 1'b0;
            O_hdmi_vsync     <= 1'b0;
            O_hdmi_hsync     <= 1'b0;
            O_hdmi_de        <= 1'b0;
            O_hdmi_data      <= 24'd0;
        end
        else begin
            S_video_vsync_1d <= I_video_vsync;
            S_video_vsync_2d <= S_video_vsync_1d;
            O_hdmi_vsync     <= S_video_vsync_2d;

            S_video_hsync_1d <= I_video_hsync;
            S_video_hsync_2d <= S_video_hsync_1d;
            O_hdmi_hsync     <= S_video_hsync_2d;

            S_video_de_1d    <= I_video_de;
            S_video_de_2d    <= S_video_de_1d;
            O_hdmi_de        <= S_video_de_2d;
            S_video_data_1d  <= I_video_rd_data;
            S_video_data_2d  <= S_video_data_1d;

            if(DEBUG_MODE == 1) begin
                if(S_video_de_2d) begin
                    if(S_x < 12'd128)
                        O_hdmi_data <= 24'hff0000;
                    else if(S_x < 12'd256)
                        O_hdmi_data <= 24'h00ff00;
                    else if(S_x < 12'd384)
                        O_hdmi_data <= 24'h0000ff;
                    else if(S_x < 12'd512)
                        O_hdmi_data <= 24'hffff00;
                    else if(S_x < 12'd640)
                        O_hdmi_data <= 24'h00ffff;
                    else if(S_x < 12'd768)
                        O_hdmi_data <= 24'hff00ff;
                    else if(S_x < 12'd896)
                        O_hdmi_data <= 24'hffffff;
                    else
                        O_hdmi_data <= 24'h202020;
                end
                else begin
                    O_hdmi_data <= 24'd0;
                end
            end
            else if(DEBUG_MODE == 2) begin
                if(S_video_de_2d) begin
                    case (I_debug_status)
                        4'b0000: O_hdmi_data <= 24'h000000;
                        4'b0001: O_hdmi_data <= 24'hff0000;
                        4'b0011: O_hdmi_data <= 24'hffff00;
                        4'b0111: O_hdmi_data <= 24'h00ff00;
                        4'b1111: O_hdmi_data <= I_video_rd_data;
                        default: O_hdmi_data <= 24'h0000ff;
                    endcase
                end
                else begin
                    O_hdmi_data <= 24'd0;
                end
            end
            else if(DEBUG_MODE == 3) begin
                if(S_video_de_2d) begin
                    if(S_x < 12'd256)
                        O_hdmi_data <= I_debug_status[0] ? 24'hff8000 : 24'h201000;
                    else if(S_x < 12'd512)
                        O_hdmi_data <= I_debug_status[1] ? 24'hffff00 : 24'h202000;
                    else if(S_x < 12'd768)
                        O_hdmi_data <= I_debug_status[2] ? 24'hff0000 : 24'h200000;
                    else
                        O_hdmi_data <= I_debug_status[3] ? 24'h00ffff : 24'h002020;
                end
                else begin
                    O_hdmi_data <= 24'd0;
                end
            end
            else begin
                if(S_osd_hit)
                    O_hdmi_data <= S_osd_color;
                else
                    O_hdmi_data <= S_video_data_2d;
            end
        end
    end

endmodule
