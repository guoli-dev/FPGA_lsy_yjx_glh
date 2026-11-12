module isp_top (
    input 			axi4s_video_aclk,
    input 			I_rst_n			,
    // 显示模式 (2026-10-12: 2 位 -> 3 位, 加了第 5 个模式)
    //   0=原图  1=边缘  2=卡通化  3=跟踪(框+标签+十字)  4=运动检测(帧差染色)
    // 由 design_top_wrapper 的按键驱动; 本模块在帧边界采样, 避免半帧切换造成撕裂。
    input [2:0] 	I_mode			,
    input 			I_tlast			,
    input 			I_tuser			,
    input [39:0] 	I_tdata			,
    input 			I_tvalid		,
    input [9:0] 	I_tdest			,
    input 			O_tready		,
    output [127:0] 	O_tdata			,
    output 			O_tlast			,
    output 			O_tuser			,
    output 			O_tvalid		,
    output 			I_tready		,
    // 三色检测结果导出给顶层 (2026-10-10), 用来在 HDMI 域画质心十字和颜色名。
    // 每色 64 位: [9:0]=bottom [19:10]=top [30:20]=right [41:31]=left [42]=valid
    //             [53:43]=质心x  [63:54]=质心y      红=[63:0] 绿=[127:64] 蓝=[191:128]
    // 它在 ISP 域, 顶层要过 CDC 才能给 HDMI 域的 OSD 用。
    output [191:0] 	O_det_boxes,
    output [14:0] 	O_mot_cnt		,
    output [15:0] 	O_mot_bcd		,
    output [63:0] 	O_mot_box,
    output 			O_ae_too_bright	,
    output 			O_ae_too_dark	,
    output 			O_ae_frame_toggle
);
 
wire         m_aixs_tvalid;  //synthesis keep 
  wire [127:0] m_aixs_tdata;  //synthesis keep 
  wire         m_aixs_tuser;  //synthesis keep 
  wire         m_aixs_tlast;  //synthesis keep 
  wire         m_aixs_tready;  //synthesis keep 
  
  wire [ 95:0] m_aixs_tdata_96;  //synthesis keep 


  wire         awb_O_tlast;  //synthesis keep 
  wire         awb_O_tuser;  //synthesis keep 
  wire [ 95:0] awb_O_tdata;  //synthesis keep 
  wire [ 95:0] awb_raw_tdata;
  reg [2:0] S_mode;
  wire         awb_O_tvalid;  //synthesis keep 
  wire         awb_O_tready;  //synthesis keep 

  wire         awb_O_tuser_128;  //synthesis keep 
  wire         awb_O_tvalid_128;  //synthesis keep 
  wire [127:0] awb_O_tdata_128;  //synthesis keep 

  assign awb_O_tready = O_tready;
  assign O_tdata  = awb_O_tdata_128;
  assign O_tlast  = gam_tlast      ;
  assign O_tuser  = awb_O_tuser_128    ;
  assign O_tvalid = awb_O_tvalid_128   ;
  
  //assign m_aixs_tready = O_tready;
  //assign O_tdata  = m_aixs_tdata;
  //assign O_tlast  = m_aixs_tlast    ;
  //assign O_tuser  = m_aixs_tuser    ;
  //assign O_tvalid = m_aixs_tvalid   ;
 
 
demosaic #(
    .IMG_HEIGHT          (720 ), // 图像高度
    .IMG_WIDTH           (1280), // 图像宽度
    .data_complete_delay (50  ),
    .BAYER_MODE          ("BGGR")
)
u_demosaic
(
    .I_clk   			(axi4s_video_aclk)	,   // 时钟信号
    .I_rst_n 			(I_rst_n)	,   // 复位信号，低有效
    .axi4s_video_tdata 	(I_tdata)	,  // AXI4-Stream视频数据
    .axi4s_video_tdest 	(I_tdest)	,
    .axi4s_video_tlast 	(I_tlast)	,  // 行结束信号
    .axi4s_video_tvalid	(I_tvalid)	,  // 数据有效信号
    .axi4s_video_tuser 	(I_tuser)	,  // 帧开始信号
    .axi4s_video_tready	(I_tready)	,  // 从模块准备好接受数据
    .O_tlast  			(m_aixs_tlast)	,  // 输出行结束信号
    .O_tuser  			(m_aixs_tuser)	,  // 输出帧开始信号
    .O_tdata  			(m_aixs_tdata)	,  // 输出数据
    .O_tvalid 			(m_aixs_tvalid)	,  // 输出数据有效信号
    .O_tready   		(m_aixs_tready)	   // 输出数据准备好信号
);
 
data128_96 u_data128_96 (
    .I_tdata(m_aixs_tdata),
    .O_tdata(m_aixs_tdata_96)
);

// AE observes pre-AWB, pre-gamma pixels without modifying the video stream.
aec_stats_96 u_aec_stats (
    .I_clk          (axi4s_video_aclk),
    .I_rst_n        (I_rst_n),
    .I_tuser        (m_aixs_tuser),
    .I_tvalid       (m_aixs_tvalid),
    .I_tdata        (m_aixs_tdata_96),
    .O_too_bright   (O_ae_too_bright),
    .O_too_dark     (O_ae_too_dark),
    .O_frame_toggle (O_ae_frame_toggle)
);

// ---- 2026-10-12: AWB 换成 One 工程那版改良实现 (awb.v 已整体替换) ----------
// 原厂那版有两个问题, 都直接命中用户实测的现象:
//   1) 白平衡统计取**全画面**灰世界平均, 所以画面里一出现大块红/绿物体,
//      增益就被那片颜色拉偏 -> 画面**其余部分整体串色偏蓝** -> 背景冒出蓝框。
//      ("有时候出现蓝色的误识别, 就是在拿出来红色 or 绿色")
//   2) 增益施加处三个通道**各自独立削顶**到 255, 而 R/B 增益远大于 G、
//      亮的中性表面变成 (255,G,255), 比例被改掉 -> 亮面/天花板被误判成蓝/红。
// 改良版: 白点筛选(只统计接近白/灰的像素, 彩色物体不参与) + 空间均匀采样
// (每 32x16 取一个样本, 防亮区主导) + 上电快收敛后转极慢跟随 + 削顶修正
// (任一通道溢出时三通道一起置成最大值, 高光冲向白)。
//
// ★ 它多了 4 个端口, 在 One 里全部由按钮/常量驱动。这里没有那套东西, 全部接
//   中性常量(Q16, 1.0 = 20'h10000) —— 等于"增益完全交给 AWB 自己算", 与 One 的
//   默认行为一致 (One 的 design_top_wrapper 复位值也是全 20'h10000)。
//
// ★ 代价 (必须知道): 这是**全局显色改动**。现在的绿色余量 18.75% 是在**原厂 AWB**
//   下量出来的 —— 当时传感器原生偏绿被压着, 所以要放宽到 3g/16 才识别得到。
//   换完之后绿色不再被压, 这个余量很可能要调回 25% (COLOR_MARGIN_SHIFT=2)。
//   先只换 AWB 这一个变量, 上板看绿色还灵不灵, 再决定要不要动余量。
awb #(
    .IMG_HEIGHT(720 ),
    .IMG_WIDTH (1280)
) u_awb (
    .I_clk   (axi4s_video_aclk),
    .I_rst_n (I_rst_n),
    .I_global_gain(20'h10000),   // 1.0 (Q16)
    .I_wb_r_trim  (20'h10000),   // 1.0 —— 三个 trim 全中性, 交给 AWB 自己定增益
    .I_wb_g_trim  (20'h10000),
    .I_wb_b_trim  (20'h10000),
    .I_tlast (m_aixs_tlast),
    .I_tuser (m_aixs_tuser),
    .I_tdata (m_aixs_tdata_96),
    .I_tvalid(m_aixs_tvalid),
    .I_tready(m_aixs_tready),
    .O_tlast (awb_O_tlast ),
    .O_tuser (awb_O_tuser ),
    .O_tdata (awb_O_tdata ),
    .O_raw_tdata(awb_raw_tdata),
    .O_tvalid(awb_O_tvalid),
    .O_tready(awb_O_tready)
);

// ---- Gamma 提亮 (2026-10-07) ------------------------------------------------
// 插在 AWB 之后 (标准 ISP 顺序: AWB -> Gamma -> 输出)。原厂这套画面偏暗, 加一级
// gamma 提亮中间调。模块定义在本文件末尾。
// 带一级流水, tlast/tuser/tvalid 和数据一起延, 保证对齐。
wire        gam_tlast, gam_tuser, gam_tvalid;
wire [95:0] gam_tdata;
reg [8:0] awb_beat_x;
reg [95:0] gamma_bypass_d;
reg gamma_left_d;
wire [95:0] awb_demo_tdata = (S_mode == 3'd5 && awb_beat_x < 9'd160)
                               ? awb_raw_tdata : awb_O_tdata;
wire [95:0] demo_tdata = (S_mode == 3'd6 && gamma_left_d)
                            ? gamma_bypass_d : gam_tdata;

// Four pixels per valid beat; reset during the line gap (tlast is a
// falling-valid pulse in this legacy AWB). No frame buffer or pixel drop.
always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        awb_beat_x <= 9'd0;
        gamma_bypass_d <= 96'd0;
        gamma_left_d <= 1'b0;
    end else begin
        if (awb_O_tlast) awb_beat_x <= 9'd0;
        else if (awb_O_tvalid) awb_beat_x <= awb_beat_x + 9'd1;
        gamma_bypass_d <= awb_demo_tdata;
        gamma_left_d <= (awb_beat_x < 9'd160);
    end
end

gamma_96 #(
    .BLACK_LEVEL (4)        // 传感器黑阶(10位约15, >>2 之后约4), 必须先减掉
) u_gamma_96 (
    .I_clk   (axi4s_video_aclk),
    .I_rst_n (I_rst_n),
    .I_tlast (awb_O_tlast ),
    .I_tuser (awb_O_tuser ),
    .I_tdata (awb_demo_tdata ),
    .I_tvalid(awb_O_tvalid),
    .I_bypass(1'b0),        // gamma 打开 —— 实测它对亮度有贡献, 而且不是时序的元凶(无 gamma 的工程时序同样紧)
    .O_tlast (gam_tlast ),
    .O_tuser (gam_tuser ),
    .O_tdata (gam_tdata ),
    .O_tvalid(gam_tvalid)
);

// ---- 色块识别 + 画框 (2026-10-07) -------------------------------------------
// 分两块, 都放在 ISP 域:
//   color_detect_96  从 gamma 输出上取数, 只统计, 不改数据通路
//   box_overlay_96   用上一帧的框坐标, 在当前帧上画矩形
//
// 为什么画在 ISP 域而不是 HDMI 域 (重要)
// -------------------------------------
// HDMI 域 (75MHz / 13.333ns) 的最差路径终点就是 u_hdmi_mixer/O_hdmi_data_reg,
// 往那里加画框 = 往那条只剩 111ps 裕量的路径终点再塞一级 mux, 必炸。
// ISP 域 (60MHz / 16.668ns) 有 4.475ns 裕量, 是它的 40 倍。
//
// 染色诊断版 (classify_overlay_96) 的定义还留在本文件末尾, 想回退就把 u_tint
// 那个实例恢复回来、把 u_box 去掉即可。
// 每色 4 个连通域框 (连通域版, 2026-10-11)。
//   det_boxes       = 每色的 rank1 (面积最大的那个) —— 也是送 HDMI 画标签/十字的那一份
//   det_boxes2/3/4  = 每色的 rank2~4 —— 只给 ISP 域的 box_overlay_96 画框
// 拆成 4 根 192 位总线而不是一根 768 位: rank1 那根正好就是原来那根总线,
// 所以送 HDMI 的跨时钟域部分**一行都不用改** (标签只贴最大的框)。
wire [191:0] det_boxes_raw;
wire [191:0] det_boxes, det_boxes2, det_boxes3, det_boxes4;
wire         box_tuser, box_tvalid;
wire [ 95:0] box_tdata;

// 把三色检测结果导出给顶层 (顶层做 CDC 送进 HDMI 域画十字/颜色名) —— 只送 rank1
assign O_det_boxes = det_boxes;

color_detect_96 #(
    .IMG_WIDTH         (1280),
    .IMG_HEIGHT        (720 ),
    .COLOR_MARGIN_SHIFT(2   ),   // 主导通道需高出其他 25%
    .GREEN_MIN_RUN     (3   ),   // 绿色每个 4 像素组至少这么多命中才算"活跃"。
                                 // ★ 连通域版里这个门只决定"这个组要不要进轨迹",
                                 //   不再是包围盒的硬门 —— 零散点会变成像素数极少的
                                 //   轨迹, 帧末被 AREA_TH 直接淘汰。所以它可以从 4
                                 //   退回 3/2, 不会再把远处的绿目标整帧门掉。
    .MIN_BRIGHT        (95  ),   // 2026-11-12: 70 -> 95，暗棕/暗红在亮度上先挡一道
    .AREA_TH           (300 ),   // **单个连通域**小于 300 像素不报
    .MIN_RUN           (3   ),   // 2026-10-19: 2->3, horizontal erosion for the bbox only
    .EDGE_MASK_X       (80  ),
    .EDGE_MASK_Y       (45  ),
    .NTRK              (4   ),   // 每色同时跟踪的连通域条数 = 每色最多几个框
    // ---- 2026-10-11: "一个物体出来好多框" 的修复 (只改这两个常数) ----------
    // 匹配里只有两个"容差"常数, 它们就是物体被判成"断链了"的阈值:
    //   纵向: (T_row[i] >= y_pos - GAPY)     -- y_pos 是**像素行号** (0..719)
    //   横向: (grp_lox <= T_x1) && (grp_hix >= T_x0),  grp_lox = base_x - GAPX*4
    // 断链之后**轨迹永不合并、永不关闭** (T_on 只在帧末清), 于是同一个物体被
    // 永久劈成多条轨迹, 每条单独都过 AREA_TH=300 -> 叠好几个框。
    //
    // ★ 单位: y_pos 是像素行, 所以 GAPY=2 只容忍 **1 个像素行**的空白 (不是 2)。
    //   原来写 2 是想"容忍 2 行", 实际只有 1 行 —— 物体上只要有一条连续 2 像素行
    //   的空白带 (过曝高光 / 遮挡 / 非彩色横条) 就断链。
    //   16 => 容忍 15 像素行, 覆盖绝大多数高光带。
    // GAPX: 2 -> 4 (8px -> 16px)。作用在物体**最上面几行** —— 那时包围盒还没铺满
    //   物体宽度, 一条 >8px 宽的竖条(竖高光/折痕/印刷图案)就能把左右撕成两条轨迹,
    //   而且往下永不合并。16px 的横向容差跨得过去。
    //   代价: 纵向相距 <15px / 横向相距 <16px 且相互重叠的两个**同色**物体会并成
    //   一个框。演示场景里物体之间隔得远, 不构成问题; 真撞上就把对应那个数字回收。
    .GAPX              (4   ),
    .GAPY              (16  )
) u_detect (
    .I_clk       (axi4s_video_aclk),
    .I_rst_n     (I_rst_n),
    .I_tuser     (gam_tuser),
    .I_tvalid    (gam_tvalid),
    .I_tdata     (gam_tdata),
    .O_det_boxes (det_boxes_raw ),
    .O_det_boxes2(det_boxes2),
    .O_det_boxes3(det_boxes3),
    .O_det_boxes4(det_boxes4)
);

// 帧间滞回：只作用于送显示/送下位的 rank1，不动检测内核。
// 连续 2 帧命中才点亮；丢失后保持 8 帧（约 133 ms），期间框冻结在最后位置。
color_box_hold_96 #(
    .ON_N  (2'd2),
    .HOLD_N(4'd8)
) u_boxhold (
    .I_clk  (axi4s_video_aclk),
    .I_rst_n(I_rst_n),
    .I_tuser(gam_tuser),
    .I_boxes(det_boxes_raw),
    .O_boxes(det_boxes    )
);

// ---- 显示模式 (2026-10-10) -------------------------------------------------
// 四种模式, 用按键循环切换 (按键在 design_top_wrapper 里, 用 I_button[0]=N2):
//     0 = 原图   (摄像头画面 + 安路 Logo, Logo 在 hdmi_mixer 里)
//     1 = 边缘   (Sobel 边缘图, 白边黑底)
//     2 = 分割   (颜色判据的二值结果)      -- 下一步做
//     3 = 跟踪   (原图 + 检测框 + 文字)    -- 下一步做
// 3 和 2 暂时回落到原图, 不影响前面两种。
//
// 模式寄存器在**帧边界**采样 (见下面 S_mode 的 always), 免得半帧切换造成撕裂。
//
// 链路:
//     gamma ─┬─→ edge_detect_96 ──→ edge ──┐
//            ├─→ [延一拍] ────────────────┤→ 三选一 → [打一拍] → box_overlay → 输出
//            └─→ color_detect_96 (永远读原图, 不受模式影响)
// 原图分支必须延一拍, 因为 edge_detect_96 有一拍延迟, 两支要步调一致。
// 三选一后面再打一拍是**为了保时序** —— box_overlay 里那个 paint() 组合很深,
// 不让 mux 直接串上去 (ISP 域余量本来就紧)。
reg  [95:0] raw_tdata_d;
reg         raw_tuser_d, raw_tvalid_d, raw_tlast_d;
wire        edge_tlast, edge_tuser, edge_tvalid, edge_tready;
wire [95:0] edge_tdata;
wire [3:0]  edge_strong;
// sel_* 必须是 reg —— 它们在下面的 always 里被赋值 (wire 不能过程赋值, 会报 HDL-8007)
reg         sel_tuser, sel_tvalid, sel_tlast;
reg  [95:0] sel_tdata;

always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        S_mode       <= 3'd0;
        raw_tdata_d  <= 96'd0;
        raw_tuser_d  <= 1'b0;
        raw_tvalid_d <= 1'b0;
        raw_tlast_d  <= 1'b0;
    end else begin
        // 原图分支延一拍, 与 edge_detect_96 的一拍延迟对齐
        raw_tdata_d  <= demo_tdata;
        raw_tuser_d  <= gam_tuser;
        raw_tvalid_d <= gam_tvalid;
        raw_tlast_d  <= gam_tlast;
        // 只在帧边界换模式 —— 上游 awb 的 O_tuser 是组合直通、O_tvalid 延两拍,
        // 所以这里只认 gam_tuser, 绝不要求它与 tvalid 同拍。
        if (gam_tuser) S_mode <= I_mode;
    end
end

edge_detect_96 #(
    .IMG_WIDTH (1280),
    .IMG_HEIGHT(720 )
) u_edge (
    .I_clk   (axi4s_video_aclk),
    .I_rst_n (I_rst_n),
    // 边缘图使用门限 80，卡通描边使用门限 60。
    // 门限 60（2026-11-12 上板照片复核后从 45 提上来，两个模式共用）。
    // 45 时墙面/木纹这类天然纹理的梯度全被放行，画面满是密集噪点；
    // 家具轮廓的梯度明显更强，60 能把纹理挡在外面。
    // 现场若还嫌噪点多 → 提到 70；嫌轮廓丢 → 降到 55。只改这一个数。
    .I_edge_th(11'd60),
    .I_tlast (gam_tlast ),
    .I_tuser (gam_tuser ),
    .I_tdata (gam_tdata ),
    .I_tvalid(gam_tvalid),
    .I_tready(O_tready  ),
    .O_tlast (edge_tlast ),
    .O_tuser (edge_tuser ),
    .O_tdata (edge_tdata ),
    .O_strong(edge_strong),
    .O_tvalid(edge_tvalid),
    .O_tready(edge_tready)
);

// ---- 卡通化: 区域填充 + 边缘描边 (2026-10-10) -----------------------------
// 对应**基础扩展要求(1)「边缘提取与区域填充」**。纯组合, 0 寄存器 / 0 BRAM / 0 DSP。
// I_color 用原图(raw_tdata_d), I_strong 用 edge_detect_96 的强边输出 —— 两者本来就同拍
// (都在 gamma+1), 所以不需要任何额外对齐逻辑。
wire [95:0] cartoon_tdata;
cartoon_effect_96 #(
    .QUANT_BITS(3)              // 每通道 8 级，共 512 色，保留色块辨识所需的颜色层次。
) u_cartoon (
    .I_clk    (axi4s_video_aclk),
    .I_rst_n  (I_rst_n),
    .I_color  (raw_tdata_d),    // 原图 (已延一拍)
    .I_strong (edge_strong),    // 强边标志 (同拍)
    .O_cartoon(cartoon_tdata)
);

// 显示模式选择: 0=原图  1=边缘  2=卡通化  3=跟踪(原图+画框)
// (2 原来是 SEG 分割模式的占位, 一直回落到原图; 2026-10-10 改成卡通化,
//  直接补上基础扩展要求(1) 的"区域填充"。)
wire [95:0] S_mux_tdata = (S_mode == 2'd1) ? edge_tdata    :
                          (S_mode == 2'd2) ? cartoon_tdata : raw_tdata_d;

always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        sel_tdata  <= 96'd0;
        sel_tuser  <= 1'b0;
        sel_tvalid <= 1'b0;
        sel_tlast  <= 1'b0;
    end else begin
        sel_tdata  <= S_mux_tdata;
        sel_tuser  <= raw_tuser_d;
        sel_tvalid <= raw_tvalid_d;
        sel_tlast  <= raw_tlast_d;
    end
end

wire        mot_tuser, mot_tvalid;
wire [95:0] mot_tdata;
wire [14:0] mot_cnt;
wire [15:0] mot_bcd;
wire [63:0] mot_box;

motion_detect_96 #(
    .IMG_WIDTH (1280),
    .IMG_HEIGHT(720 ),
    .DIFF_TH   (12  )
) u_motion (
    .I_clk    (axi4s_video_aclk),
    .I_rst_n  (I_rst_n),
    .I_bypass (S_mode != 3'd4),
    .I_tuser  (sel_tuser),
    .I_tvalid (sel_tvalid),
    .I_tdata  (sel_tdata),
    .O_tuser  (mot_tuser),
    .O_tvalid (mot_tvalid),
    .O_tdata  (mot_tdata),
    .O_mot_cnt(mot_cnt),
    .O_mot_bcd(mot_bcd),
    .O_mot_box(mot_box)
);

assign O_mot_cnt = mot_cnt;
assign O_mot_bcd = mot_bcd;
assign O_mot_box = mot_box;

box_overlay_96 #(
    .IMG_WIDTH (1280),
    .IMG_HEIGHT(720 ),
    .THICK     (3   )            // 线宽 = 2*3+1 = 7 像素
) u_box (
    .I_clk      (axi4s_video_aclk),
    .I_rst_n    (I_rst_n),
    // 只有"跟踪模式"(3) 才画框; 其余模式直通。原来硬接 1'b0。
    .I_bypass   ((S_mode != 3'd3) && (S_mode != 3'd4)),
    .I_tuser    (mot_tuser),
    .I_tvalid   (mot_tvalid),
    .I_tdata    (mot_tdata),
    .I_det_boxes((S_mode == 3'd4) ? {64'd0, 64'd0, mot_box} : det_boxes),
    .I_det_boxes2(det_boxes2),
    .I_det_boxes3(det_boxes3),
    .I_det_boxes4(det_boxes4),
    .O_tuser    (box_tuser),
    .O_tvalid   (box_tvalid),
    .O_tdata    (box_tdata)
);

    data_96bit_to_128bit u_data_96bit_to_128bit(
        .I_clk              ( axi4s_video_aclk  ),
        .I_rst_n            ( I_rst_n           ),

        .I_96b_frame_start  ( box_tuser	    ),
        .I_96b_valid        ( box_tvalid 		),
        .I_96b_data         ( box_tdata		),
	
        .O_128b_frame_start ( awb_O_tuser_128  	),
        .O_128b_valid       ( awb_O_tvalid_128 	),
        .O_128b_data        ( awb_O_tdata_128  	)
    );



//data96_128 u_data96_128 (
//    .I_tdata(awb_O_tdata),
//    .O_tdata(awb_O_tdata_128)
//);
	
endmodule

// ============================================================================
// gamma_96 —— Gamma 提亮 (分段线性近似, 逐像素三通道)
//
// 用途: 原厂例程画面偏暗(曝光已在传感器上限、模拟增益是原厂默认值), 加一级 gamma
// 提亮中间调。属于赛题里的"图像增强"。
//
// ★ 两个关键设计点 ★
//
// 1) **必须先减黑电平。**
//    传感器有约 4 个码值的黑阶(10 位 RAW 约 15, 经 raw10_unpacket 的 >>2 之后约 4;
//    那个模块的 I_camera_black_level 是悬空的, 所以这一级没被减掉)。不减掉它就直接
//    套 gamma, 黑阶会被一起抬高 —— 表现是整幅发灰、对比度垮掉。**这正是之前加
//    gamma 失败的根因**, 所以这里做成 BLACK_LEVEL 参数。
//
// 2) **斜率只用移位和加减, 不引乘法器。**
//    DSP 预算很紧, 乘法器写几个就占几个。四段斜率取成 1.50 / 1.00 / 0.75, 可以用
//    (v>>1)、(v-64)、((v-128)*3>>2) 实现 —— *3 会被综合成移位加法, 不占 DSP。
//
// 曲线(减完黑电平之后, 输入 0..251):
//      0 ->  64 :   0 ->  96     v + (v>>1)             等效 x1.50
//     64 -> 128 :  96 -> 160     96 + (v-64)            等效 x1.00
//    128 -> 192 : 160 -> 208     160 + ((v-128)*3>>2)   等效 x0.75
//    192 -> 251 : 208 -> 252     208 + ((v-192)*3>>2)   等效 x0.75
//    整体等效 gamma 约 0.7: **中间调提亮 25~50%, 高光基本不动** —— 提亮而不冲掉高光。
//
// 处理 96 位 = 4 个 RGB888 像素, 每像素三通道各过一遍曲线。带一级流水,
// tlast/tuser/tvalid 与数据同延, 保证对齐。
// ============================================================================
module gamma_96 #(
    parameter BLACK_LEVEL = 4      // 传感器黑阶(8位域); 输出先减掉它再上曲线
)(
    input             I_clk,
    input             I_rst_n,
    input             I_tlast,
    input             I_tuser,
    input      [95:0] I_tdata,
    input             I_tvalid,
    input             I_bypass,    // 1 = 直通, 不加 gamma
    output reg        O_tlast,
    output reg        O_tuser,
    output reg [95:0] O_tdata,
    output reg        O_tvalid
);

    function [7:0] gam8;
        input [7:0] vin;
        reg   [8:0] v;
        reg   [9:0] t;
        begin
            // 先减黑电平 —— 不减掉黑阶, 曲线会把黑阶一起抬起来, 整幅发灰
            v = (vin <= BLACK_LEVEL) ? 9'd0 : ({1'b0, vin} - BLACK_LEVEL);

            if      (v < 9'd64)  t = {1'b0,v} + (v >> 1);                 // x1.50
            else if (v < 9'd128) t = 10'd96  + (v - 9'd64);               // x1.00
            else if (v < 9'd192) t = 10'd160 + (((v - 9'd128) * 3) >> 2); // x0.75
            else                 t = 10'd208 + (((v - 9'd192) * 3) >> 2); // x0.75

            gam8 = (t > 10'd255) ? 8'hff : t[7:0];
        end
    endfunction

    wire [95:0] S_gam = {
        gam8(I_tdata[95:88]), gam8(I_tdata[87:80]), gam8(I_tdata[79:72]),
        gam8(I_tdata[71:64]), gam8(I_tdata[63:56]), gam8(I_tdata[55:48]),
        gam8(I_tdata[47:40]), gam8(I_tdata[39:32]), gam8(I_tdata[31:24]),
        gam8(I_tdata[23:16]), gam8(I_tdata[15:8]),  gam8(I_tdata[7:0])
    };

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tlast  <= 1'b0;
            O_tuser  <= 1'b0;
            O_tvalid <= 1'b0;
            O_tdata  <= 96'd0;
        end else begin
            O_tlast  <= I_tlast;
            O_tuser  <= I_tuser;
            O_tvalid <= I_tvalid;
            O_tdata  <= I_bypass ? I_tdata : S_gam;
        end
    end

endmodule

// Frame-level exposure statistics. One green sample is taken every 256 valid
// beats (about 900 samples/frame); the video stream is observed, never stalled.
module aec_stats_96 (
    input             I_clk,
    input             I_rst_n,
    input             I_tuser,
    input             I_tvalid,
    input      [95:0] I_tdata,
    output reg        O_too_bright,
    output reg        O_too_dark,
    output reg        O_frame_toggle
);

    localparam [9:0]  CLIP_ENTER = 10'd29;    // > 900/32
    localparam [9:0]  CLIP_EXIT  = 10'd14;    // < 900/64
    localparam [15:0] DARK_ENTER = 16'd10800; // mean green < 48
    localparam [15:0] DARK_EXIT  = 16'd14400; // mean green > 64

    reg [7:0]  S_phase;
    reg [9:0]  S_clip;
    reg [15:0] S_sum_g6;
    reg        S_frame_ready;

    wire [7:0] S_green    = I_tdata[15:8];
    wire       S_take     = I_tvalid && (S_phase == 8'd0);
    wire       S_clip_pix = (S_green >= 8'd250);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_phase       <= 8'd0;
            S_clip        <= 10'd0;
            S_sum_g6      <= 16'd0;
            S_frame_ready <= 1'b0;
        end else if (I_tuser) begin
            S_phase       <= 8'd0;
            S_clip        <= 10'd0;
            S_sum_g6      <= 16'd0;
            S_frame_ready <= 1'b1;
        end else if (I_tvalid) begin
            S_phase <= S_phase + 8'd1;
            if (S_take) begin
                S_sum_g6 <= S_sum_g6 + {10'd0, S_green[7:2]};
                if (S_clip_pix)
                    S_clip <= S_clip + 10'd1;
            end
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_too_bright   <= 1'b0;
            O_too_dark     <= 1'b0;
            O_frame_toggle <= 1'b0;
        end else if (I_tuser) begin
            if (S_frame_ready) begin
                if (S_clip >= CLIP_ENTER)
                    O_too_bright <= 1'b1;
                else if (S_clip <= CLIP_EXIT)
                    O_too_bright <= 1'b0;

                if (S_sum_g6 < DARK_ENTER)
                    O_too_dark <= 1'b1;
                else if (S_sum_g6 > DARK_EXIT)
                    O_too_dark <= 1'b0;

                O_frame_toggle <= ~O_frame_toggle;
            end
        end
    end

endmodule

// ============================================================================
// 以下两个模块从 One 工程搬来 (2026-10-07): 色块识别 + 判据染色叠加。
// 放在本文件内部而不建新文件 —— Tang Dynasty 重写 .al 会丢掉手工加入的源文件。
// ============================================================================

// ============================================================================
// 扩展(2) 目标检测与识别 —— 颜色目标检测 (红/绿/蓝 三色各自出框 + 质心)
//
// 在 96bit(4 像素/拍) 的原图流上做红/绿/蓝三色分类, 每种颜色独立跟踪一个目标。
//
// ---- 为什么不是简单的全画面 min/max (2026-10-05 重构) ----
// 原来取的是"全画面该色像素的 min/max"。这有三个毛病:
//   * 画面里有两个同色物体 -> 一个框把两个一起圈进去
//   * 画面角落一颗噪点     -> 框被撑到整个屏幕
//   * 命中总数在 AREA_TH 上下浮动 -> 框忽隐忽现
// 根因是它给的从来就不是"一个目标", 而是"所有该色像素的范围"。
//
// 现在改成两趟分块引导:
//   第 1 趟  把画面切成 NBX x NBY 个块, 统计每块命中数, 取命中最多的块
//   第 2 趟  下一帧只在那个块 ±WIN 个块的窗口内累计包围盒和质心
// 效果: 两个物体只取最密集的那个; 角落噪点进不了窗口; 窗口内命中数远高于门限,
// 框不再临界闪动。顺带得到质心(Σx/n, Σy/n) —— 这是 OSD 显示和小车追踪要用的
// "目标中心", 包围盒中心给不出这个。
//
// 代价: 目标如果比窗口还大(默认 ±1 块 = 480x360)会被裁; 响应慢一帧(可忽略)。
// 这不是完整的连通域标记(CCL), 是它的一个便宜替代; 真要处理任意形状/任意数量
// 的目标, 需要上 CCL(带并查集和标签表), 那是另一个量级的工作。
//
// ---- 抗噪三道门 (沿用) ----
//   1) 单像素颜色判据: 主导通道需比其余高出自身值的 1/2^COLOR_MARGIN_SHIFT
//   2) 实心度 MIN_RUN: 一个 4 像素组里至少这么多像素命中
//   3) 横向连续性 RUN_GROUPS: 连续这么多组合格才算成串
// 外加边缘屏蔽 EDGE_MASK: 四角的镜头色阴影不采信(详见参数说明)。
//
// 三个色块的逻辑完全相同, 抽成 color_box_96 子模块实例化三次。它故意和本模块
// 放在同一个文件里: Tang Dynasty 每次 GUI 保存都会重写工程文件(.al), 手工加进去
// 的独立源文件会被丢掉。
// ============================================================================
module color_detect_96 #(
    parameter IMG_WIDTH     = 1280,
    parameter IMG_HEIGHT    = 720,
    parameter COLOR_MARGIN_SHIFT = 2, // dominant channel must beat the others by 1/2^N of its own value (N=2 -> 25%)
    // ---- 绿色单独的包围盒实心度门 (2026-10-10) ----------------------------
    // 放宽绿色余量(上面那条)之后出现的新问题: 背景里"略偏绿"的散点也通过了
    // 判据, 而这些散点散布在窗口各处, 会把包围盒的 min/max 撑开 —— 表现就是
    // **绿框明显比物体大, 贴不住**。红蓝没这个问题(它们的余量还是 25%, 够紧)。
    //
    // 关键: MIN_RUN 在 color_box_96 里**只门控包围盒**, 不门控检测 ——
    //     grp_qual = (hit_cnt >= MIN_RUN) && ...   -> 只喂给 grp_ok -> 只喂 min/max
    //     块直方图用 hit_cnt != 0, 面积/质心用 grp_cnt != 0, 都不看 MIN_RUN
    // 所以提高它 = **只收紧框, 灵敏度一点都不损失**。这正是我们要的:
    // 保留放宽余量带来的"识别距离变宽", 同时把散点挡在包围盒之外。
    //
    // 2 -> 3 的含义: 一个 4 像素组里要有 3 个命中才算"实心"(原来 2 个)。
    // 真实物体的内部是 4/4, 照样过; 背景散点很难凑够 3/4。
    // 只作用于绿色; 红蓝仍用 MIN_RUN。
    parameter GREEN_MIN_RUN = 2,
    parameter MIN_BRIGHT    = 80,   // 亮度下限, 滤除暗噪声
    parameter AREA_TH       = 300,  // **单个连通域**面积(像素数)小于该值不报
    parameter MIN_RUN       = 2,    // 每个 4 像素组内至少这么多像素命中才算"活跃"
    // ---- 边缘屏蔽 ----------------------------------------------------------
    // 四角有镜头色阴影(偏红), 会触发红色误检。真正的修法是 LSC(分区增益),
    // 但那个还没做成; 在那之前先不采信画面最外圈的像素。
    parameter EDGE_MASK_X   = 80,   // 左右各屏蔽的像素数 (1280 的 6.25%)
    parameter EDGE_MASK_Y   = 45,   // 上下各屏蔽的像素数 (720 的 6.25%)
    // ---- 连通域跟踪参数 (2026-10-11 起真正生效) ---------------------------
    // 2026-10-07 曾退回"分块引导窗口"版 (color_box_96), BLK_W/BLK_H/WIN 和
    // RUN_GROUPS 都是那一版的参数, 现在不用了 —— 连通域不需要"窗口"和
    // "横向连续性硬门": 零散点会变成像素数极少的轨迹, 帧末被 AREA_TH 淘汰。
    parameter NTRK          = 4,    // 同时跟踪的连通域条数 = 每色最多几个框
    parameter GAPX          = 4,    // 横向容差 = GAPX*4 像素 (实例化传 4 = 16px)
    // ★ 语义: 匹配写的是 (T_row[i] >= y_pos - GAPY), 而 **y_pos 是像素行号**
    //   (0..719, 一拍 = 一行里的 4 个像素组, 组号在 x_grp 里)。所以 GAPY 的值不是
    //   "容忍几行", 而是"容忍 GAPY-1 个像素行的空白"。原来写 2 实际只容忍 1 行 ——
    //   物体上一条连续 2 像素行的空白带(过曝高光/遮挡/非彩色横条)就断链, 而断链后
    //   轨迹**永不合并**(T_on 只在帧末清), 同一个物体就永久劈成多个框。
    //   实例化处传 16 (容忍 15 像素行)。
    parameter GAPY          = 16    // 纵向容差 (实为"容忍 GAPY-1 个像素行")
)(
    input            I_clk,
    input            I_rst_n,
    input            I_tuser,     // 帧开始
    input            I_tvalid,
    input  [95:0]    I_tdata,     // 4 x RGB888, pix0=[95:72] 在最左

    // 三色结果, 每种 64 位:
    //   [42:0]  包围盒 = {valid, left[10:0], right[10:0], top[9:0], bottom[9:0]}
    //   [53:43] 质心 x  (0..1279)   rank2~4 的 cx/cy 用框中心填
    //   [63:54] 质心 y  (0..719)    rank1 是真质心
    //   红 = [63:0], 绿 = [127:64], 蓝 = [191:128]
    // 2026-10-11: 每色从 1 个框扩成 4 个 (连通域版)。4 根总线各 192 位, 每根
    // 装的是"每色的一个 rank" —— O_det_boxes 就是 rank1, 也是送 HDMI 画标签/十字
    // 的那一份, 所以跨时钟域那一侧完全不用改。
    output [191:0]   O_det_boxes,   // rank1 (面积最大)
    output [191:0]   O_det_boxes2,  // rank2
    output [191:0]   O_det_boxes3,  // rank3
    output [191:0]   O_det_boxes4   // rank4
);

    // Single-pixel colour test.
    //
    // The dominance threshold is RELATIVE: the leading channel must beat the
    // others by 1/2^COLOR_MARGIN_SHIFT of its own value (25% at the default).
    // A fixed count, such as ">= 15", is tied to one exposure and gain setting:
    // raising the analog gain from 4x to 8x doubles every channel difference as
    // well, so the same fixed margin suddenly fires on ordinary background
    // pixels. Deriving the margin from the pixel's own value keeps the test
    // valid at any gain or exposure without retuning.
    //
    // 2026-10-19: red margin raised from 25% (r>>2) to 31.25% (5r/16).
    // Skin sits at r-g ~= 25% of r, i.e. exactly on the old threshold, so
    // hands were being boxed as red. 31.25% clears skin and still catches
    // saturated red objects. Shift-add only, no DSP.
    //
    // 2026-11-12 上板照片：31.25% 仍然会把**深棕/暗红**的物件框成红色
    // （桌上一根深棕色腕带、以及暗红色书皮）。棕色本质就是"饱和度和亮度
    // 都不够的红"：
    //     棕色 (110,70,60)  -> (r-b)/r = 45%
    //     饱和红 (220,60,50) -> (r-b)/r = 77%
    // 两者差 3 倍多，而 31.25% 的门限只卡在中间偏下，所以棕色照样过。
    // 提高饱和门限到 50%（r>>1，比原来的 5r/16 还省一个加法器），
    // 棕色被挡在外面，饱和红仍有余量。配合把 MIN_BRIGHT 提到 95 一起用。
    function [7:0] f_rmar;
        input [7:0] r;
        begin
            f_rmar = r >> 1;                                // 50% 饱和度门限
        end
    endfunction
    function is_red;
        input [7:0] r, g, b;
        reg [7:0] m;
        begin
            m = f_rmar(r);
            is_red = (r >= MIN_BRIGHT) && (r >= g) && (r >= b) &&
                     ((r - g) >= m) && ((r - b) >= m);
        end
    endfunction
    function is_green;
        input [7:0] r, g, b;
        // 绿的余量 = 3g/16 = 18.75%
        // 为什么是这个中间档 (2026-10-10 拿两档诊断染色在板子上实测定的):
        //   12.5% (g>>3) -> 画面中心的固定绿偏(约 5~10%)也能过判据 -> 假检,
        //                   天花板/灯光都被判成绿, 绿框被这些散点撑大
        //   25%   (g>>2) -> 画面中心被正确挡住 ✓, 但真绿物体只有核心过、边缘不过
        //                   (诊断染色上呈"橙黄混杂")
        //   18.75%        -> 实测: 真绿物体以亮黄为主(核心和边缘都过), 中心仍被挡住 ✓
        // 只用移位加法: 3g = (g<<1) + g, 再 >>4。不占乘法器。
        // (原来这里是参数 GREEN_MARGIN_SHIFT, 写法是 g>>N, 只能取 2 或 3 两档,
        //  取不到中间档 —— 而 12.5% 和 25% 两边都不对。)
        reg [9:0] gm;
        begin
            gm = ({2'b0, g} + {1'b0, g, 1'b0}) >> 4;
            is_green = (g >= MIN_BRIGHT) && (g >= r) && (g >= b) &&
                       ((g - r) >= gm) && ((g - b) >= gm);
        end
    endfunction
    function is_blue;
        input [7:0] r, g, b;
        begin
            is_blue = (b >= MIN_BRIGHT) && (b >= r) && (b >= g) &&
                      ((b - r) >= (b >> COLOR_MARGIN_SHIFT)) &&
                      ((b - g) >= (b >> COLOR_MARGIN_SHIFT));
        end
    endfunction

    // 4 个像素的通道
    wire [7:0] r0 = I_tdata[95:88], g0 = I_tdata[87:80], b0 = I_tdata[79:72];
    wire [7:0] r1 = I_tdata[71:64], g1 = I_tdata[63:56], b1 = I_tdata[55:48];
    wire [7:0] r2 = I_tdata[47:40], g2 = I_tdata[39:32], b2 = I_tdata[31:24];
    wire [7:0] r3 = I_tdata[23:16], g3 = I_tdata[15:8],  b3 = I_tdata[7:0];

    wire hr0 = is_red  (r0,g0,b0), hg0 = is_green(r0,g0,b0), hb0 = is_blue(r0,g0,b0);
    wire hr1 = is_red  (r1,g1,b1), hg1 = is_green(r1,g1,b1), hb1 = is_blue(r1,g1,b1);
    wire hr2 = is_red  (r2,g2,b2), hg2 = is_green(r2,g2,b2), hb2 = is_blue(r2,g2,b2);
    wire hr3 = is_red  (r3,g3,b3), hg3 = is_green(r3,g3,b3), hb3 = is_blue(r3,g3,b3);

    // I_hit[3] = 组内第 0 个像素(最左), I_hit[0] = 第 3 个像素
    wire [3:0] hit_r = {hr0,hr1,hr2,hr3};
    wire [3:0] hit_g = {hg0,hg1,hg2,hg3};
    wire [3:0] hit_b = {hb0,hb1,hb2,hb3};

    // ---- 判色 -> 跟踪 之间插一级流水 (2026-10-09) --------------------------
    // 原来判色函数 (is_red/is_green/is_blue, 每像素 5 个条件 x 4 像素 x 3 色) 和
    // 跟踪器的入口逻辑串在同一拍里, 实测出来的路径是:
    //     u_gamma_96/O_tdata_reg -> u_detect/u_box_g/S_best_y_reg.ceb
    //     16.093ns (cell 4.146ns + net 11.947ns), Logic Level 13
    // 跨了 gamma -> detect 两个模块, 逻辑又深又长。
    // 打完这一拍后, 那 13 级被劈成「判色」和「跟踪入口」两段, 各自只有一半。
    //
    // 关键: hit 和 tuser/tvalid **必须一起延同样的一拍**, 对齐关系才不变 ——
    // 包括上游 awb 那个 O_tuser 组合直通 / O_tvalid 延两拍的错拍条件,
    // 两个信号同延一拍后, 相对关系原样保持, 跟踪器里那句
    // `I_tuser && !I_tvalid` 照旧成立。
    reg [3:0] hit_r_r, hit_g_r, hit_b_r;
    reg       tuser_r,  tvalid_r;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            hit_r_r <= 4'd0; hit_g_r <= 4'd0; hit_b_r <= 4'd0;
            tuser_r <= 1'b0; tvalid_r <= 1'b0;
        end else begin
            hit_r_r <= hit_r; hit_g_r <= hit_g; hit_b_r <= hit_b;
            tuser_r <= I_tuser; tvalid_r <= I_tvalid;
        end
    end

    // 2026-10-11: 换成**连通域版**, 每色最多 4 个框。
    //
    // 为什么这次能过时序(2026-10-07 那次过不了):
    //   1) NTRK 从 8 减到 4 —— 最差路径全在"对轨迹表的组合扫描"上(变址读 +
    //      每次迭代 5 个比较)。8 选 1 变 4 选 1, 变址只剩 2 位, 深度大约减半。
    //   2) NTRK 取成和"每色报几个框"同一个数之后, 帧末"取前 4 大"就退化成
    //      **一个 4 元素排序网络**(5 个比较器、深度 3), 不需要状态机。
    //   3) 原来那些紧的硬门(MIN_RUN 硬门 / RUN_GROUPS 横向连续性)可以放松:
    //      零散点会形成像素数极少的轨迹, 帧末被 AREA_TH 淘汰。
    //
    // 输出: 每色 4 个 rank。rank1 = 面积最大的连通域(cx/cy 是真质心),
    //       rank2~4 的 cx/cy 用框中心填。4 根总线各 192 位, 每根是"每色一个 rank"。
    wire [255:0] Ob_r, Ob_g, Ob_b;

    color_box_ccl_96 #(
        .IMG_WIDTH (IMG_WIDTH ), .IMG_HEIGHT(IMG_HEIGHT),
        .AREA_TH   (AREA_TH   ), .MIN_RUN   (MIN_RUN   ),
        .EDGE_MASK_X(EDGE_MASK_X), .EDGE_MASK_Y(EDGE_MASK_Y),
        .NTRK(NTRK), .GAPX(GAPX), .GAPY(GAPY)
    ) u_box_r (
        .I_clk(I_clk), .I_rst_n(I_rst_n), .I_tuser(tuser_r), .I_tvalid(tvalid_r),
        .I_hit(hit_r_r), .O_boxes(Ob_r)
    );

    color_box_ccl_96 #(
        .IMG_WIDTH (IMG_WIDTH ), .IMG_HEIGHT(IMG_HEIGHT),
        .AREA_TH   (AREA_TH   ), .MIN_RUN   (GREEN_MIN_RUN),
        .EDGE_MASK_X(EDGE_MASK_X), .EDGE_MASK_Y(EDGE_MASK_Y),
        .NTRK(NTRK), .GAPX(GAPX), .GAPY(GAPY)
    ) u_box_g (
        .I_clk(I_clk), .I_rst_n(I_rst_n), .I_tuser(tuser_r), .I_tvalid(tvalid_r),
        .I_hit(hit_g_r), .O_boxes(Ob_g)
    );

    color_box_ccl_96 #(
        .IMG_WIDTH (IMG_WIDTH ), .IMG_HEIGHT(IMG_HEIGHT),
        .AREA_TH   (AREA_TH   ), .MIN_RUN   (2       ),
        .EDGE_MASK_X(EDGE_MASK_X), .EDGE_MASK_Y(EDGE_MASK_Y),
        .NTRK(NTRK), .GAPX(GAPX), .GAPY(GAPY)
    ) u_box_b (
        .I_clk(I_clk), .I_rst_n(I_rst_n), .I_tuser(tuser_r), .I_tvalid(tvalid_r),
        .I_hit(hit_b_r), .O_boxes(Ob_b)
    );

    // 每色取一个 rank, 按原来的 {蓝, 绿, 红} 顺序拼成 192 位
    assign O_det_boxes  = { Ob_b[ 63:  0], Ob_g[ 63:  0], Ob_r[ 63:  0] };  // rank1
    assign O_det_boxes2 = { Ob_b[127: 64], Ob_g[127: 64], Ob_r[127: 64] };  // rank2
    assign O_det_boxes3 = { Ob_b[191:128], Ob_g[191:128], Ob_r[191:128] };  // rank3
    assign O_det_boxes4 = { Ob_b[255:192], Ob_g[255:192], Ob_r[255:192] };  // rank4

endmodule


// ============================================================================
// color_box_96 —— 单色目标跟踪 (分块引导的包围盒 + 质心)
//
// 帧复位 (重要)
// ------------
// 只看 I_tuser, 绝不要求它与 I_tvalid 同拍。
// 上游 awb.v 里 O_tuser 是组合直通 (assign O_tuser = I_tuser), 而 O_tvalid 被延迟
// 了两拍。所以到本模块输入时, 一帧的 I_tuser 比该帧第一拍 I_tvalid 早两个周期。
// 原代码把复位写在 "I_tvalid && I_tuser" 里, 那一支永远进不去: 累计器从不复位 ->
// 框面积逐帧累加永不归零 -> 框有效性恒为 1, 而 min/max 也永不复位、收敛到整个
// 画面 —— 于是框被画在屏幕最外圈那几个像素上, 看上去就像"完全没有识别"。
//
// 位置计数器 x_grp/y_pos 只在 I_tuser 与 I_tvalid 不同拍时复位。本设计正是这种
// 情况; 若哪天两者同拍就不复位, 免得与递增赋值冲突 —— 每帧恰好 GRP_W x
// IMG_HEIGHT 拍, 它们自己会绕回对齐。
//
// 两趟结构
// --------
//   第 1 趟: 每帧统计各块命中数, 顺便用流式比较器找出命中最多的块 (S_best_blk)。
//            流式比全并行省得多: 只在写计数器时比一次, 一个比较器就够。
//   第 2 趟: 下一帧只在 S_best_blk ± WIN 的窗口内累计 min/max 和 Σx/Σy/count。
// 窗口外的像素不参与任何统计 —— 这就是"两个物体不会合框、角落噪点进不来"的原因。
//
// 质心用 Σx/count, Σy/count。除法在帧末做, 顺序移位减法, 每帧几十拍, 不占资源。
// ============================================================================
module color_box_96 #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,
    parameter AREA_TH    = 300,
    parameter MIN_RUN    = 2,
    parameter RUN_GROUPS = 2,
    parameter EDGE_MASK_X = 80,
    parameter EDGE_MASK_Y = 45,
    parameter BLK_W      = 160,
    parameter BLK_H      = 120,
    parameter WIN        = 1
)(
    input             I_clk,
    input             I_rst_n,
    input             I_tuser,
    input             I_tvalid,
    input      [3:0]  I_hit,       // I_hit[3]=组内第 0 个像素(最左)
    output reg [63:0] O_box
);

    localparam GRP_W = IMG_WIDTH / 4;              // 320 组/行
    localparam NBX   = IMG_WIDTH  / BLK_W;         // 8  块/行
    localparam NBY   = IMG_HEIGHT / BLK_H;         // 6  块/列
    localparam NBLK  = NBX * NBY;                  // 48
    localparam GRP_PER_BLK_W = BLK_W / 4;          // 40 组/块宽
    localparam CNT_W = 28;                         // Σx/Σy 位宽 (窗口最多 480x360 x 1280 -> 28 位)

    // 三值中值 (sum - max - min 即中值)
    function [10:0] med3_11;
        input [10:0] a, b, c;
        reg [10:0] hi, lo;
        reg [12:0] sum;
        begin
            hi  = (a > b) ? ((a > c) ? a : c) : ((b > c) ? b : c);
            lo  = (a < b) ? ((a < c) ? a : c) : ((b < c) ? b : c);
            sum = {2'b0,a} + {2'b0,b} + {2'b0,c};
            med3_11 = sum - {2'b0,hi} - {2'b0,lo};
        end
    endfunction
    function [9:0] med3_10;
        input [9:0] a, b, c;
        reg [9:0] hi, lo;
        reg [11:0] sum;
        begin
            hi  = (a > b) ? ((a > c) ? a : c) : ((b > c) ? b : c);
            lo  = (a < b) ? ((a < c) ? a : c) : ((b < c) ? b : c);
            sum = {2'b0,a} + {2'b0,b} + {2'b0,c};
            med3_10 = sum - {2'b0,hi} - {2'b0,lo};
        end
    endfunction

    // ---- 位置计数 (全部靠递增维护, 不做除法) ----
    reg [8:0]  x_grp;    // 0..GRP_W-1
    reg [9:0]  y_pos;    // 0..IMG_HEIGHT-1
    reg [5:0]  S_cxb;    // 块内组序号 0..GRP_PER_BLK_W-1
    reg [2:0]  S_blk_x;  // 0..NBX-1
    reg [7:0]  S_cyb;    // 块内行序号 0..BLK_H-1
    reg [2:0]  S_blk_y;  // 0..NBY-1

    // ---- 第 1 趟: 每块命中数 + 流式 argmax --------------------------------
    // 2026-10-09 重构: 48 个块计数器 -> 8 个列计数器。
    //
    // 为什么 (这是本工程 ISP 域时序的真根因, 前面绕了两圈才找对)
    // ------------------------------------------------------
    // 原来写的是 `reg [15:0] S_blk_cnt [0:47]`, 用变量索引**组合读**
    // (`S_blk_cnt[S_blk_y*8+S_blk_x]` 同拍就要拿去比较), 所以它只能是 LUT
    // 分布式 RAM —— 组合读的数组永远进不了 BRAM (BRAM 是同步读)。实测代价:
    //     48 项地址译码 x 16 位宽 x 2 个读口 ≈ 1536 个负载
    //   挂在一个索引网上, 报告里 Max Fanout 1567、net 延迟占 80~89%、
    //   Logic Level 只有 6~9。**不是逻辑深, 是一根线拉了 1500 多个负载。**
    // 而且加 (* ram_style="block" *) 也没用 —— 工具直接忽略 (syn 日志里
    // BRAM 只报了 awb 延迟线和 demosaic 行缓存三条)。
    //
    // 关键观察: 行扫描是逐行的, 一个**块行**(8 个块, 高 BLK_H 行)在扫完之前,
    // 下一个块行根本不会被碰到。所以根本不需要同时存 48 个计数 —— 只要
    // 当前块行的 8 个列计数就够, 块行末尾把 8 个比一次、记下赢家、清零。
    //     8 项 x 16 位 x 2 口 = 256 个负载 (6 倍下降)
    //     索引 = S_blk_x (纯 3 位, 不再有 S_blk_y*NBX 乘法)
    //     存储 768 bit -> 128 bit
    // 跑出来的语义与原来逐位等价: S_best_val 仍是全帧 48 个块里的最大值,
    // 因为每个块行的最大值都会与跨块行的 running max 比较。
    reg [15:0] S_col_cnt [0:NBX-1];    // 当前块行的 8 个列计数
    reg [2:0]  S_best_x, S_best_y;
    reg [15:0] S_best_val;
    // 8 选最大树的结果缓冲 (2026-10-10): 块行末尾锁存, 下一拍再和 S_best_val 比。
    // 目的是把"8 选最大树"的组合深度和比较器隔开一拍 —— 那两个串在一起是
    // ISP 域原最差路径 (17.033ns / 13 级)。
    reg        S_bmax_en;
    reg [16:0] S_bmax_val;      // [15:0]=计数, [16:14]=列号
    reg [2:0]  S_bmax_row;
    reg [2:0]  S_win_x,  S_win_y;      // 本帧使用的窗口中心 (上一帧的 argmax)
    // 窗口中心块本帧的命中数, 在该块行扫完时顺手记下。
    // 迟滞比较需要「当前窗口中心块的计数」, 而列计数在块行末尾就清零了,
    // 所以必须在那一刻把它取出来。8 选 1 mux, 很便宜。
    reg [15:0] S_win_cnt_r;

    // ---- 第 2 趟: 窗口内的包围盒与质心 ----
    reg [10:0] S_min_x, S_max_x;
    reg [9:0]  S_min_y, S_max_y;
    reg [CNT_W-1:0] S_sum_x, S_sum_y;
    reg [17:0] S_cnt;

    // 横向连续性
    reg [7:0]  S_run_len;

    // 时域中值历史
    reg [10:0] H_l0, H_l1, H_r0, H_r1;
    reg [9:0]  H_t0, H_t1, H_b0, H_b1;
    reg [10:0] H_cx0, H_cx1;
    reg [9:0]  H_cy0, H_cy1;

    // 除法 (帧末算质心, 两个除法共用)
    localparam DIV_STEPS = CNT_W;       // 移位次数
    reg [CNT_W-1:0] S_div_rem;
    reg [CNT_W-1:0] S_div_quo;
    reg [5:0]  S_div_i;
    reg        S_div_2nd;      // 0=算 cx, 1=算 cy
    reg [10:0] S_cx;
    reg [9:0]  S_cy;
    // ---- 2026-10-11: 除法的被除数/除数必须在帧首就锁存 ----------------------
    // 除法是在 I_tuser 之后才开始跑的, 但 S_sum_y 和 S_cnt 在 I_tuser 那一拍
    // 就被清 0、紧接着开始累加**新帧**了。原来直接读它们, 于是:
    //   · 除数用 S_cnt —— 除法第 1 拍它已经是 0, S_div_ge 恒 1, 商一路变全 1
    //   · Σy 在第 28 拍才装载 —— 拿到的是"新帧前 28 拍的零星和", 基本是 0
    // 两个都错, 所以 (cx,cy) 根本不是质心: cx/y 都跑到 2047/1023, 十字画在
    // 有效画面之外 —— 板上从来没见过白色十字, 就是这个原因。
    // 做法: 帧首把"上一帧的最终 Σy 和命中总数"锁进这两个寄存器, 除法全程用它们。
    // (上一条注释里"读的是上一帧的最终值"对 Σx 成立, 对 Σy/S_cnt 不成立。)
    reg [CNT_W-1:0] S_div_cnt_lat;     // 除数: 上一帧命中总数
    reg [CNT_W-1:0] S_div_y_lat;       // 第二个被除数: 上一帧 Σy

    // 经典移位减法用到的两个组合量
    wire [CNT_W-1:0] S_div_sh = {S_div_rem[CNT_W-2:0], S_div_quo[CNT_W-1]};
    wire             S_div_ge = (S_div_sh >= S_div_cnt_lat);

    // ---- 本组统计 ----
    wire [10:0] base_x   = {x_grp, 2'b00};
    wire [2:0]  hit_cnt  = I_hit[0] + I_hit[1] + I_hit[2] + I_hit[3];

    // 边缘屏蔽 —— 2026-10-10 改成「只屏蔽四角」
    // 原来是个矩形环: 只要在横边距**或**纵边距里就整片不采信, 屏蔽掉
    //     1 - (1120*630)/(1280*720) = 23.4%  的画面
    // 而它要治的是四角镜头色阴影, 那实际只涉及
    //     4*80*45 / (1280*720) = 1.56%
    // 代价被放大了 15 倍。而且 in_field 同时门控组命中 —— 完全落在边缘环里的
    // 目标是**永久性盲区**, 不是漏几帧。
    // 改成只有同时在横边距和纵边距里才算四角: 四条边的中点(镜头色阴影很轻)
    // 重新参与检测, 四角仍然屏蔽。屏蔽面积精确等于 1.56%。
    // 实测: 贴边的色块不再丢框。
    wire in_h_margin = (base_x <  EDGE_MASK_X) || (base_x >= (IMG_WIDTH  - EDGE_MASK_X));
    wire in_v_margin = (y_pos  <  EDGE_MASK_Y) || (y_pos  >= (IMG_HEIGHT - EDGE_MASK_Y));
    wire in_field    = !(in_h_margin && in_v_margin);

    // 窗口判定: 当前块是否落在 S_win_x/y ± WIN 之内
    wire [2:0] dxb = (S_blk_x > S_win_x) ? (S_blk_x - S_win_x) : (S_win_x - S_blk_x);
    wire [2:0] dyb = (S_blk_y > S_win_y) ? (S_blk_y - S_win_y) : (S_win_y - S_blk_y);
    wire in_win = (dxb <= WIN) && (dyb <= WIN);

    wire grp_qual = (hit_cnt >= MIN_RUN) && in_field && in_win;   // 实心度+边缘+窗口
    wire grp_ok   = grp_qual && (S_run_len >= (RUN_GROUPS - 1));

    wire [10:0] grp_min_x = base_x + (I_hit[3] ? 11'd0 :
                                      I_hit[2] ? 11'd1 :
                                      I_hit[1] ? 11'd2 : 11'd3);
    wire [10:0] grp_max_x = base_x + (I_hit[0] ? 11'd3 :
                                      I_hit[1] ? 11'd2 :
                                      I_hit[2] ? 11'd1 : 11'd0);

    // 窗口内的像素级 Σx / count (质心用)
    // 组内 4 个像素的 x 依次是 base_x .. base_x+3; I_hit[3] 对应最左
    wire [13:0] grp_sum_x = (I_hit[3] ? {3'b0,base_x}       : 14'd0) +
                            (I_hit[2] ? {3'b0,base_x} + 14'd1 : 14'd0) +
                            (I_hit[1] ? {3'b0,base_x} + 14'd2 : 14'd0) +
                            (I_hit[0] ? {3'b0,base_x} + 14'd3 : 14'd0);
    wire [12:0] grp_sum_y = {10'b0, hit_cnt} * {3'b0, y_pos};   // hit_cnt * y_pos
    wire [2:0]  grp_cnt   = hit_cnt;

    // ---- 列计数累加 + 块行末尾的 8 选最大 --------------------------------
    // 索引就是 S_blk_x —— 不再有 S_blk_y * NBX, 索引网上也就没有乘法了。
    wire [15:0] S_col_new = S_col_cnt[S_blk_x] + {13'd0, hit_cnt};
    // 2026-10-11: 从 (hit_cnt >= MIN_RUN) **回退**到 (hit_cnt != 3'd0)。
    // 上一版想只统计"实心命中"来把窗口钉在物体上, 但代价是 S_best_val /
    // S_win_cnt_r 都变小、相邻块容易打平 -> 25% 迟滞频繁换窗口 -> **框漂移**。
    // 用户实测报"静止物体框在漂", 这条是嫌疑之一, 和 GREEN_MIN_RUN 一起回退,
    // 让检测回到 10-10 用户确认过的状态。
    // 窗口被背景抢走的问题, 改由批次 B 的连通域解决(按整块面积淘汰散点)。
    wire        S_blk_upd = I_tvalid && in_field && (hit_cnt != 3'd0);   // 有命中才更新

    // 块行末尾: 一行扫到头, 且本块行内的行计数走到 BLK_H-1
    wire blk_row_end = I_tvalid && (x_grp == GRP_W - 1) && (S_cyb == BLK_H - 1);

    // 8 选最大 + 列号, 树形 (深度 3 而不是 8 级链)。
    // 把 {计数[15:0], 列号[2:0]} 打包成 17 位一起比较、一起搬运。
    // 平局取列号小的 (max2 用 >=, 左操作数优先)。
    // 注意: 这里写死 8 列, 和 NBX = IMG_WIDTH/BLK_W = 8 绑定。改 BLK_W 的话
    // 这棵树要跟着改 (S_blk_x 是 3 位, 本来就假设了 8 列)。
    function [16:0] max2;
        input [16:0] a, b;
        begin
            max2 = (a[15:0] >= b[15:0]) ? a : b;
        end
    endfunction
    wire [16:0] S_m01 = max2({S_col_cnt[0],3'd0}, {S_col_cnt[1],3'd1});
    wire [16:0] S_m23 = max2({S_col_cnt[2],3'd2}, {S_col_cnt[3],3'd3});
    wire [16:0] S_m45 = max2({S_col_cnt[4],3'd4}, {S_col_cnt[5],3'd5});
    wire [16:0] S_m67 = max2({S_col_cnt[6],3'd6}, {S_col_cnt[7],3'd7});
    wire [16:0] S_m03 = max2(S_m01, S_m23);
    wire [16:0] S_m47 = max2(S_m45, S_m67);
    wire [16:0] S_col_max = max2(S_m03, S_m47);   // [16:14]=列号, [15:0]=计数

    // ---- valid 的迟滞 (2026-10-09) ----------------------------------------
    // 原来 valid 是硬阈值 (S_cnt >= AREA_TH)。目标命中总数在 300 上下浮动时,
    // 这一帧过、下一帧不过 —— 框整个一闪一闪(用户报的"忽有忽无")。
    // 加迟滞: 一旦亮起, 要掉到 AREA_OFF 以下才熄灭。
    // 亮/灭用的是同一个本帧末计数 S_cnt; 它在 I_tuser 那一拍被清零前读出
    // (非阻塞赋值), 所以取到的正是本帧最终值。
    localparam AREA_OFF = (AREA_TH * 7) / 10;    // 300 -> 210
    reg  S_box_on;
    wire S_box_on_nx = (S_cnt >= AREA_TH) ? 1'b1 :
                       (S_box_on && (S_cnt >= AREA_OFF));

    // ---- 本帧是否真的产出了包围盒 (2026-10-09) ----------------------------
    // S_cnt 和 S_min_x/S_max_x 用的**不是同一个门**:
    //   S_cnt    只要"有命中像素"(in_field && in_win && hit_cnt!=0) 就累加
    //   包围盒   还要过 grp_ok —— 即 MIN_RUN + 连续 RUN_GROUPS 组合格
    // 于是会出现这样的帧: 散点命中够多(≥AREA_TH, valid=1) 但一个实心组都没有。
    // 那帧里 S_min_x 还是复位值 2047、S_max_x 还是 0。中值滤波能吸收单帧坏值
    // (med3(2047,100,110)=110), 但**连着两帧坏就失效** (med3(2047,2047,100)=2047)
    // —— 框坐标变成 left=2047/right=0, 画框时 x_in=(x>=2047)&&(x<=0) 恒假,
    // 框直接消失。这正是"框整个闪没"的机制。
    // 判据: S_max_x 只在 grp_ok 命中时被抬高, 且 EDGE_MASK_X=80 保证真实目标的
    // max_x 远大于 0 —— 所以 S_max_x==0 唯一地表示"本帧一个实心组都没有"。
    wire S_have_bbox = (S_max_x != 11'd0);

    // ---- box deadband (2026-10-19) ---------------------------------------
    // Background pixels of a similar colour drift in and out of the bbox, so
    // even the median-filtered edges wobble a few pixels every frame. Ignore
    // changes of <= 4 px: a static object gives a rock-steady box, while real
    // motion (anything larger) updates immediately.
    localparam [4:0] BOX_DB = 5'd4;
    reg  [10:0] D_l, D_r, D_cx;
    reg  [ 9:0] D_t, D_b, D_cy;
    wire [10:0] M_l  = med3_11(S_min_x, H_l0, H_l1);
    wire [10:0] M_r  = med3_11(S_max_x, H_r0, H_r1);
    wire [ 9:0] M_t  = med3_10(S_min_y, H_t0, H_t1);
    wire [ 9:0] M_b  = med3_10(S_max_y, H_b0, H_b1);
    wire [10:0] M_cx = med3_11(S_cx, H_cx0, H_cx1);
    wire [ 9:0] M_cy = med3_10(S_cy, H_cy0, H_cy1);
    wire [10:0] dL = (M_l  > D_l ) ? (M_l  - D_l ) : (D_l  - M_l );
    wire [10:0] dR = (M_r  > D_r ) ? (M_r  - D_r ) : (D_r  - M_r );
    wire [ 9:0] dT = (M_t  > D_t ) ? (M_t  - D_t ) : (D_t  - M_t );
    wire [ 9:0] dB = (M_b  > D_b ) ? (M_b  - D_b ) : (D_b  - M_b );
    wire [10:0] dX = (M_cx > D_cx) ? (M_cx - D_cx) : (D_cx - M_cx);
    wire [ 9:0] dY = (M_cy > D_cy) ? (M_cy - D_cy) : (D_cy - M_cy);
    wire [10:0] O_l  = (dL > {6'd0, BOX_DB}) ? M_l  : D_l ;
    wire [10:0] O_r  = (dR > {6'd0, BOX_DB}) ? M_r  : D_r ;
    wire [ 9:0] O_t  = (dT > BOX_DB[3:0]   ) ? M_t  : D_t ;
    wire [ 9:0] O_b  = (dB > BOX_DB[3:0]   ) ? M_b  : D_b ;
    wire [10:0] O_cx = (dX > {6'd0, BOX_DB}) ? M_cx : D_cx;
    wire [ 9:0] O_cy = (dY > BOX_DB[3:0]   ) ? M_cy : D_cy;

    integer k;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_box <= 64'd0;
            D_l <= 11'd0; D_r <= 11'd0; D_t <= 10'd0; D_b <= 10'd0;
            D_cx <= 11'd0; D_cy <= 10'd0;
            x_grp <= 9'd0; y_pos <= 10'd0;
            S_cxb <= 6'd0; S_blk_x <= 3'd0;
            S_cyb <= 8'd0; S_blk_y <= 3'd0;
            S_best_x <= 3'd0; S_best_y <= 3'd0; S_best_val <= 16'd0;
            S_bmax_en <= 1'b0; S_bmax_val <= 17'd0; S_bmax_row <= 3'd0;
            S_win_x <= 3'd0; S_win_y <= 3'd0; S_win_cnt_r <= 16'd0;
            S_min_x <= 11'h7ff; S_max_x <= 11'd0;
            S_min_y <= 10'h3ff; S_max_y <= 10'd0;
            S_sum_x <= {CNT_W{1'b0}}; S_sum_y <= {CNT_W{1'b0}}; S_cnt <= 18'd0;
            S_run_len <= 8'd0;
            H_l0 <= 11'd0; H_l1 <= 11'd0; H_r0 <= 11'd0; H_r1 <= 11'd0;
            H_t0 <= 10'd0; H_t1 <= 10'd0; H_b0 <= 10'd0; H_b1 <= 10'd0;
            H_cx0 <= 11'd0; H_cx1 <= 11'd0; H_cy0 <= 10'd0; H_cy1 <= 10'd0;
            S_div_rem <= {CNT_W{1'b0}}; S_div_quo <= {CNT_W{1'b0}};
            S_div_i <= 6'd0; S_div_2nd <= 1'b0;
            S_div_cnt_lat <= {CNT_W{1'b0}}; S_div_y_lat <= {CNT_W{1'b0}};
            S_cx <= 11'd0; S_cy <= 10'd0;
            S_box_on <= 1'b0;
            for (k = 0; k < NBX; k = k + 1) S_col_cnt[k] <= 16'd0;
        end else begin
            // ---- 帧开始: 输出结果 + 换窗口 + 复位累计器 --------------------
            if (I_tuser) begin
                // 包围盒用时域中值; 质心直接用本帧算好的值
                // centroid gets the same 3-frame temporal median as the bbox
                O_box <= { O_cy, O_cx,
                           S_box_on_nx && S_have_bbox,   // 迟滞 valid, 且本帧真出了框
                           O_l,
                           O_r,
                           O_t,
                           O_b };
                S_box_on <= S_box_on_nx;

                // 只有本帧真出了包围盒才推进时域历史 —— 别把复位值 2047/0 塞进
                // 中值滤波器。这样连续掉几帧也不会污染历史。见 S_have_bbox 的说明。
                if (S_have_bbox) begin
                    D_cx <= O_cx; D_cy <= O_cy;
                    D_l <= O_l; D_r <= O_r; D_t <= O_t; D_b <= O_b;
                    H_cx1 <= H_cx0; H_cx0 <= S_cx;
                    H_cy1 <= H_cy0; H_cy0 <= S_cy;
                    H_l1 <= H_l0;  H_l0 <= S_min_x;
                    H_r1 <= H_r0;  H_r0 <= S_max_x;
                    H_t1 <= H_t0;  H_t0 <= S_min_y;
                    H_b1 <= H_b0;  H_b0 <= S_max_y;
                end

                // 本帧的窗口 = 上一帧找到的最密集块, 但要加迟滞:
                // 相邻两块的命中数接近时, 逐帧的 argmax 会在它们之间来回跳,
                // 窗口跟着跳, 框就抖 —— 这是分块引导引入的新抖动源。
                // 只有新块明显更密集(超出 25%)才换窗口, 否则保持不动。
                // 2026-10-09: 比较用 S_win_cnt_r (扫描时锁存的窗口中心计数),
                // 不再从数组变址读。见上面 S_win_cnt_r 的说明。
                if (S_best_val > (S_win_cnt_r + (S_win_cnt_r >> 2))) begin
                    S_win_x <= S_best_x;
                    S_win_y <= S_best_y;
                end
                // 清零要在上面那个比较**之后**写: 非阻塞赋值, 比较读到的仍是上一帧
                // 锁存的最终值; 清零从本帧开始累积。
                // 这一步是为了和原版语义完全一致 —— 原版直接读数组, 窗口中心块整帧
                // 零命中时读到 0, 下帧立刻换窗口。锁存版若不在这里清零, 零命中时会
                // 保留旧值, 换窗口变慢, 快速移动的目标会滞后。
                S_win_cnt_r <= 16'd0;

                // 复位第 1 趟
                for (k = 0; k < NBX; k = k + 1) S_col_cnt[k] <= 16'd0;
                S_best_x <= 3'd0; S_best_y <= 3'd0; S_best_val <= 16'd0;

                // 复位第 2 趟
                S_min_x <= 11'h7ff; S_max_x <= 11'd0;
                S_min_y <= 10'h3ff; S_max_y <= 10'd0;
                S_sum_x <= {CNT_W{1'b0}}; S_sum_y <= {CNT_W{1'b0}}; S_cnt <= 18'd0;
                S_run_len <= 8'd0;

                // 启动帧末除法: 先算 cx, 再算 cy。
                // 非阻塞赋值 -> 本拍读到的 S_sum_x / S_sum_y / S_cnt 都还是**上一帧
                // 的最终值** (本拍写的复位要到下一拍才生效)。
                // Σx 可以直接当被除数; Σy 和 S_cnt 必须额外锁存 —— Σy 要等第 28 拍
                // 才装载、S_cnt 下一拍起就要给新帧累加, 那时它们已经不是上一帧的值了。
                S_div_2nd     <= 1'b0;
                S_div_i       <= 6'd1;
                S_div_rem     <= {CNT_W{1'b0}};
                S_div_quo     <= S_sum_x;
                S_div_cnt_lat <= S_cnt;      // 除数: 上一帧命中总数
                S_div_y_lat   <= S_sum_y;    // 第二个被除数: 上一帧 Σy
            end

            // ---- 帧末除法: 顺序移位减法 ------------------------------------
            // 装载在 I_tuser 那一拍完成 (S_div_i=1, quo=Σx)。之后每拍移位一次,
            // DIV_STEPS 拍后商在 S_div_quo 里 —— 先得 cx, 接着装载 Σy 算 cy。
            // 2026-10-11: 除数改用帧首锁存的 S_div_cnt_lat (原来用 S_cnt, 但它在
            // I_tuser 那一拍就被清 0 了, 除法第 1 拍除数为 0 -> 商一路全 1)。
            if (!I_tuser && (S_div_i != 6'd0)) begin
                S_div_rem <= S_div_ge ? (S_div_sh - S_div_cnt_lat) : S_div_sh;
                S_div_quo <= {S_div_quo[CNT_W-2:0], S_div_ge};

                if (S_div_i == DIV_STEPS) begin
                    if (S_div_2nd == 1'b0) begin
                        // ★ 第 28 次移位的结果就是本拍被丢弃的那一位 (S_div_ge)。
                        //   原来写 S_div_quo[10:0], 读到的是**第 27 次移位之后**的
                        //   寄存器 —— 那里面商的低位还没算出来, 取 [10:0] 得到的
                        //   正好是 真商 >> 1。手算 13/4 验证过: 4 位时寄存器是
                        //   4'b1001, 取低 2 位 = 01 = 1, 而真商是 3。
                        //   质心 x 因此被减半 —— 现在把第 28 位拼回最低位。
                        S_cx          <= {S_div_quo[9:0], S_div_ge};
                        S_div_2nd     <= 1'b1;
                        S_div_rem     <= {CNT_W{1'b0}};
                        S_div_quo     <= S_div_y_lat;   // 接着算 cy (帧首锁存的 Σy)
                        S_div_i       <= 6'd1;
                    end else begin
                        S_cy    <= {S_div_quo[8:0], S_div_ge};
                        S_div_i <= 6'd0;                // 两个都算完, 停
                    end
                end else
                    S_div_i <= S_div_i + 6'd1;
            end

            // ---- 逐拍推进 --------------------------------------------------
            if (I_tvalid) begin
                // 第 1 趟: 列计数累加 (索引就是 S_blk_x)
                if (S_blk_upd)
                    S_col_cnt[S_blk_x] <= S_col_new;

                // 块行末尾: 8 个列计数出赢家, 与跨块行的 running max 比较, 然后清零。
                // 非阻塞赋值 —— 下面读到的 S_col_cnt / S_col_max 都还是清零前的
                // 本块行最终值, 正是要的。
                if (blk_row_end) begin
                    // ★ 2026-10-10: 比较**挪到下一拍**做 (见下面 S_bmax_en 那段)。
                    //   原来是 (S_col_max > S_best_val) 组合比较, 而 S_col_max 来自
                    //   一棵 8 选最大树 —— 实测那条路径 17.033ns / Logic Level 13 /
                    //   net 占 70%, 是整个 ISP 域的最差路径。
                    //   这里只负责把树的结果锁下来, 比较器被一拍隔开。
                    // 迟滞要的「窗口中心块本帧计数」只能在这一刻取 —— 列计数马上
                    // 就清零了。S_win_y 整帧不变, 所以只在该块行取得到, 且 8 选 1
                    // 的 mux 很便宜 (原来那版是 48 选 1 的第二个变址读口)。
                    if (S_blk_y == S_win_y)
                        S_win_cnt_r <= S_col_cnt[S_win_x];

                    for (k = 0; k < NBX; k = k + 1) S_col_cnt[k] <= 16'd0;
                end

                // 第 2 趟: 窗口内累计包围盒与质心
                if (grp_ok) begin
                    if (grp_min_x < S_min_x) S_min_x <= grp_min_x;
                    if (grp_max_x > S_max_x) S_max_x <= grp_max_x;
                    if (y_pos     < S_min_y) S_min_y <= y_pos;
                    if (y_pos     > S_max_y) S_max_y <= y_pos;
                end
                if (in_field && in_win && (grp_cnt != 3'd0)) begin
                    S_sum_x <= S_sum_x + grp_sum_x;
                    S_sum_y <= S_sum_y + grp_sum_y;
                    S_cnt   <= S_cnt + grp_cnt;
                end

                // 连续性
                if (grp_qual)
                    S_run_len <= (S_run_len == 8'hff) ? 8'hff : S_run_len + 8'd1;
                else
                    S_run_len <= 8'd0;

                // 横向推进
                if (S_cxb == GRP_PER_BLK_W - 1) begin
                    S_cxb <= 6'd0;
                    if (S_blk_x != NBX - 1) S_blk_x <= S_blk_x + 3'd1;
                end else
                    S_cxb <= S_cxb + 6'd1;

                if (x_grp == GRP_W - 1) begin
                    x_grp <= 9'd0;
                    S_run_len <= 8'd0;                 // 行与行之间不算连续
                    if (S_cyb == BLK_H - 1) begin
                        S_cyb <= 8'd0;
                        if (S_blk_y != NBY - 1) S_blk_y <= S_blk_y + 3'd1;
                    end else
                        S_cyb <= S_cyb + 8'd1;
                    y_pos <= (y_pos == IMG_HEIGHT - 1) ? 10'd0 : y_pos + 10'd1;
                end else
                    x_grp <= x_grp + 9'd1;
            end

            // ---- 8 选最大树的结果, 打一拍再比较 (2026-10-10) ----------------
            // 见上面 blk_row_end 那段的说明: 原来树和比较器串在同一拍, 实测那条
            // 路径 17.033ns / Logic Level 13 / net 占 70%, 是 ISP 域的最差路径。
            // 现在树的结果在块行末尾锁进 S_bmax_*, **下一拍**才和 S_best_val 比。
            // 时间上完全宽裕 —— blk_row_end 每 120 行才来一次, 延迟一拍毫无影响。
            //
            // ★ 必须放在 if(I_tvalid) **外面**: 最后一个块行的 blk_row_end 之后紧接
            //   着就是帧末, I_tvalid 可能已经拉低, 放在里面会漏掉最后一个块行。
            S_bmax_en <= blk_row_end;
            if (blk_row_end) begin
                S_bmax_val <= S_col_max;    // 此刻列计数还没清零(非阻塞), 读到的是最终值
                S_bmax_row <= S_blk_y;      // 块行号也要一起锁 —— S_blk_y 下一拍就变了
            end
            if (S_bmax_en) begin
                if (S_bmax_val[15:0] > S_best_val) begin
                    S_best_val <= S_bmax_val[15:0];
                    S_best_x   <= S_bmax_val[16:14];
                    S_best_y   <= S_bmax_row;
                end
            end
        end
    end

endmodule

module classify_overlay_96 #(
    parameter COLOR_MARGIN_SHIFT = 2,
    parameter MIN_BRIGHT = 30
)(
    input             I_clk,
    input             I_rst_n,
    input             I_bypass,
    input             I_tuser,
    input             I_tvalid,
    input      [95:0] I_tdata,
    output reg        O_tuser,
    output reg        O_tvalid,
    output reg [95:0] O_tdata
);

    function is_red;
        input [7:0] r, g, b;
        begin
            is_red = (r >= MIN_BRIGHT) && (r >= g) && (r >= b) &&
                     ((r - g) >= (r >> COLOR_MARGIN_SHIFT)) &&
                     ((r - b) >= (r >> COLOR_MARGIN_SHIFT));
        end
    endfunction
    function is_green;
        input [7:0] r, g, b;
        begin
            is_green = (g >= MIN_BRIGHT) && (g >= r) && (g >= b) &&
                       ((g - r) >= (g >> COLOR_MARGIN_SHIFT)) &&
                       ((g - b) >= (g >> COLOR_MARGIN_SHIFT));
        end
    endfunction
    function is_blue;
        input [7:0] r, g, b;
        begin
            is_blue = (b >= MIN_BRIGHT) && (b >= r) && (b >= g) &&
                      ((b - r) >= (b >> COLOR_MARGIN_SHIFT)) &&
                      ((b - g) >= (b >> COLOR_MARGIN_SHIFT));
        end
    endfunction

    // 命中的换成醒目色, 没命中的原样输出
    function [23:0] tint;
        input [7:0] r, g, b;
        begin
            if      (is_blue (r,g,b)) tint = 24'hff00ff;   // 品红 = 判蓝
            else if (is_green(r,g,b)) tint = 24'hffff00;   // 黄   = 判绿
            else if (is_red  (r,g,b)) tint = 24'h00ffff;   // 青   = 判红
            else                      tint = {r,g,b};
        end
    endfunction

    wire [95:0] S_tinted = {
        tint(I_tdata[95:88], I_tdata[87:80], I_tdata[79:72]),
        tint(I_tdata[71:64], I_tdata[63:56], I_tdata[55:48]),
        tint(I_tdata[47:40], I_tdata[39:32], I_tdata[31:24]),
        tint(I_tdata[23:16], I_tdata[15:8],  I_tdata[7:0])
    };

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tuser  <= 1'b0;
            O_tvalid <= 1'b0;
            O_tdata  <= 96'd0;
        end else begin
            O_tuser  <= I_tuser;
            O_tvalid <= I_tvalid;
            O_tdata  <= I_bypass ? I_tdata : S_tinted;
        end
    end

endmodule


// ============================================================================
// box_overlay_96 —— 用检测结果在画面上画矩形框
//
// 为什么画在 ISP 域
// ----------------
// HDMI 域 (75MHz / 13.333ns) 的最差路径终点是 u_hdmi_mixer/O_hdmi_data_reg。
// 在那里加画框 = 往那条只剩 111ps 裕量的路径终点再塞一级 mux。ISP 域有 4.475ns。
//
// 用哪一帧的框
// ------------
// color_box_96 在 I_tuser 那一拍把上一帧算好的结果写进 O_box。所以在第 N+1 帧
// 期间 I_det_boxes 上稳定放着第 N 帧的结果 —— 直接组合使用即可, 只滞后一帧
// (16ms, 看不出来)。不要再在本模块里锁存一拍, 那会变成滞后两帧。
//
// 位置计数
// --------
// 同 color_box_96: 只在 I_tuser 那一拍复位, 且只在 tuser 与 tvalid 不同拍时复位。
// 上游 awb 的 O_tuser 是组合直通、O_tvalid 延两拍, 本设计正是这种错拍情况。
// 若哪天两者同拍就不复位, 免得与递增赋值冲突 —— 每帧恰好 320x720 拍, 计数器
// 自己会绕回对齐。
//
// 框色与目标同色: 红物体画红框, 绿画绿, 蓝画蓝。
// ============================================================================
module box_overlay_96 #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,
    parameter THICK      = 3     // 框线半宽, 实际线宽 = 2*THICK+1 像素
)(
    input             I_clk,
    input             I_rst_n,
    input             I_bypass,
    input             I_tuser,
    input             I_tvalid,
    input      [ 95:0] I_tdata,
    input      [191:0] I_det_boxes,     // 每色 rank1 (也是送 HDMI 画标签/十字的那一份)
    input      [191:0] I_det_boxes2,    // 每色 rank2
    input      [191:0] I_det_boxes3,    // 每色 rank3
    input      [191:0] I_det_boxes4,    // 每色 rank4
    output reg        O_tuser,
    output reg        O_tvalid,
    output reg [ 95:0] O_tdata
);

    localparam GRP_W          = IMG_WIDTH / 4;      // 320 组/行
    localparam [8:0] GRP_LAST = GRP_W - 1;
    localparam [11:0] TK      = THICK;

    // ---- 2026-10-11: 每色最多 4 个框 (连通域版) ---------------------------
    // 4 路 192 位总线, 每路由 3 个颜色的 64 位记录组成。布局同 color_box_96:
    //   {cy[9:0], cx[10:0], valid, left[10:0], right[10:0], top[9:0], bottom[9:0]}
    //   即 [9:0]=bottom  [19:10]=top  [30:20]=right  [41:31]=left  [42]=valid
    // 左迁到函数 rect_hit 里的原因是: 原来这里预先把每色的 L/R/T/B 展开成 12 位
    // 是"只算一次"的优化, 但现在有 4 路 × 3 色 = 12 个框, 展开本身也要 12 份,
    // 放进函数里逐像素算反而更好写; 这些量只依赖 det_boxes (整帧不变),
    // 综合工具会把公共子表达式提出来。

    // ---- 像素 (x,y) 是否落在某个空心矩形的框线上 --------------------------
    function draw_rect;
        input [11:0] x, y;
        input        v;
        input [11:0] L, R2, T, B2;
        reg x_in, y_in, x_bar, y_bar;
        begin
            x_in  = (x >= L)  && (x <= R2);                     // 水平在跨度内
            y_in  = (y >= T)  && (y <= B2);                     // 垂直在跨度内
            x_bar = ((x >= L)         && (x <= (L  + TK))) ||   // 贴左边
                    ((x >= (R2 - TK)) && (x <= R2));            // 贴右边
            y_bar = ((y >= T)         && (y <= (T  + TK))) ||   // 贴上边
                    ((y >= (B2 - TK)) && (y <= B2));            // 贴下边
            // 上下横条 = 贴上下边 且 水平在跨度内
            // 左右竖条 = 贴左右边 且 垂直在跨度内
            draw_rect = v && ((y_bar && x_in) || (x_bar && y_in));
        end
    endfunction

    // 一个 64 位的 rank 记录 -> 这个像素在不在它的框线上 (框向外扩 THICK 像素)
    function rect_hit;
        input [11:0] x, y;
        input [63:0] bx;
        begin
            rect_hit = draw_rect(x, y, bx[42],
                                 (bx[41:31] > TK) ? ({1'b0,bx[41:31]} - TK) : 12'd0,
                                 {1'b0,bx[30:20]} + TK,
                                 (bx[19:10] > TK) ? ({2'b0,bx[19:10]} - TK) : 12'd0,
                                 {2'b0,bx[ 9: 0]} + TK);
        end
    endfunction

    // ---- 三色依次判定, 先中先画 (重叠时红优先) ----------------------------
    // 返回 {命中, 颜色}。框色与目标同色 —— 红物体画红框、绿画绿、蓝画蓝。
    //
    // ★ 2026-10-12: **每色只画一个框** —— 只用 rank1 (面积最大的那个连通域)。
    //   上一版把同色 4 个 rank **或**起来画, 本意是"多目标", 但跟踪器一旦因为
    //   物体内部的高光/遮挡死带把一条轨迹断成几条(见 color_box_ccl_96 里 GAPY 的
    //   说明), 就会在**同一个物体**上叠出 2~4 个框 —— 用户实测报"一个物体出来
    //   好多框"。改成只画最大的那个之后, 即使还有残余断裂也只看到一个框。
    //   GAPX/GAPY 那两个容差常数仍然保留 (它们让断链本身变少, 框更完整)。
    //
    //   rank2~4 的端口 (I_det_boxes2/3/4) 保留着但不用 —— 综合会把 ccl 里对应的
    //   输出寄存器和排序网络的多余分支一起裁掉, 顺带省回一些资源。
    //   要恢复"每色多个框", 把这个函数改回 4 路或起来即可。
    function [24:0] pick;
        input [11:0] x, y;
        begin
            if      (rect_hit(x, y, I_det_boxes[ 63:  0])) pick = {1'b1, 24'hff0000}; // 检出红 -> 红框
            else if (rect_hit(x, y, I_det_boxes[127: 64])) pick = {1'b1, 24'h00ff00}; // 检出绿 -> 绿框
            else if (rect_hit(x, y, I_det_boxes[191:128])) pick = {1'b1, 24'h0000ff}; // 检出蓝 -> 蓝框
            else                                           pick = {1'b0, 24'h000000};
        end
    endfunction

    // 命中就盖成框色, 没命中原样透传
    function [23:0] paint;
        input [11:0] x, y;
        input [ 7:0] r, g, b;
        reg [24:0] p;
        begin
            p = pick(x, y);
            paint = p[24] ? p[23:0] : {r, g, b};
        end
    endfunction

    // ---- 位置计数 (靠递增维护, 不做除法) ----------------------------------
    reg [8:0] x_grp;    // 0..319
    reg [9:0] y_pos;    // 0..719

    wire [11:0] base_x = {1'b0, x_grp, 2'b00};   // 本组第 0 个像素的 x
    wire [11:0] yy     = {2'b0, y_pos};

    // 组内 4 个像素的 x; I_tdata[95:72] 是最左那个
    wire [11:0] px0 = base_x;
    wire [11:0] px1 = base_x + 12'd1;
    wire [11:0] px2 = base_x + 12'd2;
    wire [11:0] px3 = base_x + 12'd3;

    wire [95:0] S_painted = {
        paint(px0, yy, I_tdata[95:88], I_tdata[87:80], I_tdata[79:72]),
        paint(px1, yy, I_tdata[71:64], I_tdata[63:56], I_tdata[55:48]),
        paint(px2, yy, I_tdata[47:40], I_tdata[39:32], I_tdata[31:24]),
        paint(px3, yy, I_tdata[23:16], I_tdata[15:8],  I_tdata[7:0])
    };

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tuser  <= 1'b0;
            O_tvalid <= 1'b0;
            O_tdata  <= 96'd0;
        end else begin
            O_tuser  <= I_tuser;
            O_tvalid <= I_tvalid;
            O_tdata  <= I_bypass ? I_tdata : S_painted;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            x_grp <= 9'd0;
            y_pos <= 10'd0;
        end else begin
            // 帧复位: 只看 I_tuser。上游 O_tuser 组合直通、O_tvalid 延两拍, 两者
            // 不同拍, 所以这里只在 !I_tvalid 时清计数器, 不与下面的递增冲突。
            if (I_tuser && !I_tvalid) begin
                x_grp <= 9'd0;
                y_pos <= 10'd0;
            end

            if (I_tvalid) begin
                if (x_grp == GRP_LAST) begin
                    x_grp <= 9'd0;
                    y_pos <= (y_pos == IMG_HEIGHT - 1) ? 10'd0 : (y_pos + 10'd1);
                end else
                    x_grp <= x_grp + 9'd1;
            end
        end
    end

endmodule


// ============================================================================
// color_box_ccl_96 —— 单色跟踪 (行程连通域版)
//
// 为什么重写
// ----------
// 旧的 color_box_96 用的是「分块引导窗口」: 找最密集的 160x120 块, 然后只在该块
// ±1 块 (480x360) 的窗口内累计 min/max 包围盒。那**不是连通域** —— 窗口内所有
// 合格像素的极值, 不管它们连不连通。三个后果:
//   (1) 同色两个物体若都落在窗口内 -> 被合成一个框
//   (2) 物体大于 480x360 -> 包围盒被窗口截断, 框比物体小
//   (3) 散布的噪点 -> 参与 min/max, 把框撑大
//
// 本模块做**真正的连通域**, 但**不用像素级**——命中本来就是按 4 像素组给的
// (I_hit[3:0]), 所以按**组**做就够了, 每行 320 个组, 比像素级便宜 4 倍。
//
// 做法: 轨迹表 (track table)
// --------------------------
// 维护 NTRK 条轨迹。每个活跃的组 (hit_cnt >= MIN_RUN 且在场内) 去找一条
// 「上一行刚更新过、且 x 范围与它相邻」的轨迹延续; 找不到就开一条新轨迹。
// 帧末取像素数最多的那条 —— 那就是最大连通域。
//
// 「上一行刚更新过」这个条件是关键, 它同时解决了纵向分离:
// 同一 x 位置、不同 y 的两个物体不会合并 (下面那条上一行没被更新)。
//
// 顺带干掉了 RUN_GROUPS
// --------------------
// 旧设计要「连续 2 组合格」当横向连续性门。连通域里不需要 —— 孤立的一两组
// 会变成一条像素数极少的轨迹, 帧末被 AREA_TH 直接淘汰。而那道硬门会掐掉
// 正当目标的边缘组 (用户报过「绿色识别不稳」, 这是嫌疑之一)。
//
// 帧复位: 同 color_box_96, 只看 I_tuser, 且只在它与 I_tvalid 不同拍时清位置
// 计数器 (上游 awb 的 O_tuser 组合直通、O_tvalid 延两拍)。
//
// 输出格式与 color_box_96 完全一致, 可以直接对换。
// ============================================================================
module color_box_ccl_96 #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,
    parameter AREA_TH    = 300,   // **单个连通域**小于这么多像素就不报
    parameter MIN_RUN    = 2,     // 每个 4 像素组至少这么多命中才算活跃
    parameter EDGE_MASK_X = 80,
    parameter EDGE_MASK_Y = 45,
    // 2026-10-11: 8 -> 4。这是当初(2026-10-07)回退的直接原因 —— 组合深度 23 级,
    // ISP 域 16.668ns 装不下。深度全在"对轨迹表的组合扫描"上(变址读 + 每次迭代
    // 5 个比较), 从 8 条减到 4 条, 变址只剩 2 位、4 选 1 mux, 深度大约减半。
    // 而且 NTRK 取成和"每色报几个框"同一个数之后, 帧末"取前 4 大"就退化成
    // **一个 4 元素排序网络**, 不需要状态机也不需要影子表。
    parameter NTRK       = 4,
    parameter GAPX       = 4,     // 横向容差 = GAPX*4 像素 (4 -> 16px)
    // ★ y_pos 是**像素行号**(0..719)。匹配写的是 (T_row[i] >= y_pos - GAPY),
    //   所以 GAPY 的值 = "容忍 GAPY-1 个像素行的空白"。写 2 实际只容忍 1 行 ——
    //   这就是"一个物体裂成好多框"的根因。实例化处传 16。
    parameter GAPY       = 16     // 纵向容差 (实为"容忍 GAPY-1 个像素行")
)(
    input             I_clk,
    input             I_rst_n,
    input             I_tuser,
    input             I_tvalid,
    input      [3:0]  I_hit,      // I_hit[3]=组内第 0 个像素(最左)
    // 2026-10-11: 单框 -> 4 个框。{rank4, rank3, rank2, rank1}, 每 rank 64 位,
    // 格式与 color_box_96 完全一致:
    //   {cy[9:0], cx[10:0], valid, left[10:0], right[10:0], top[9:0], bottom[9:0]}
    // valid = 该 rank 启用 且 面积 >= AREA_TH。
    // rank1 = 面积最大的连通域, cx/cy 是**真质心** (帧末移位减法除法)。
    // rank2~4 的 cx/cy 用**框中心**填 —— 它们只用来画框, 不需要真质心,
    // 这样省掉 3 个除法器和 3 组 Σx/Σy 累加器。
    output reg [255:0] O_boxes
);

    localparam GRP_W = IMG_WIDTH / 4;      // 320 组/行
    localparam [8:0] GRP_LAST = GRP_W - 1;
    localparam CNT_W = 28;

    // ---- 三值中值 (时域滤波用; sum - max - min 即中值) --------------------
    function [10:0] med3_11;
        input [10:0] a, b, c;
        reg [10:0] hi, lo;
        reg [12:0] sum;
        begin
            hi  = (a > b) ? ((a > c) ? a : c) : ((b > c) ? b : c);
            lo  = (a < b) ? ((a < c) ? a : c) : ((b < c) ? b : c);
            sum = {2'b0,a} + {2'b0,b} + {2'b0,c};
            med3_11 = sum - {2'b0,hi} - {2'b0,lo};
        end
    endfunction
    function [9:0] med3_10;
        input [9:0] a, b, c;
        reg [9:0] hi, lo;
        reg [11:0] sum;
        begin
            hi  = (a > b) ? ((a > c) ? a : c) : ((b > c) ? b : c);
            lo  = (a < b) ? ((a < c) ? a : c) : ((b < c) ? b : c);
            sum = {2'b0,a} + {2'b0,b} + {2'b0,c};
            med3_10 = sum - {2'b0,hi} - {2'b0,lo};
        end
    endfunction

    // ---- 位置计数 ---------------------------------------------------------
    reg [8:0] x_grp;    // 0..GRP_W-1
    reg [9:0] y_pos;    // 0..IMG_HEIGHT-1

    // ---- 轨迹表 -----------------------------------------------------------
    reg        T_on  [0:NTRK-1];
    reg [10:0] T_x0  [0:NTRK-1], T_x1  [0:NTRK-1];
    reg [9:0]  T_y0  [0:NTRK-1], T_y1  [0:NTRK-1];
    reg [17:0] T_cnt [0:NTRK-1];
    reg [CNT_W-1:0] T_sx [0:NTRK-1], T_sy [0:NTRK-1];
    reg [9:0]  T_row [0:NTRK-1];       // 该轨迹最后一次被更新的行号

    // ---- 本组统计 ---------------------------------------------------------
    wire [10:0] base_x  = {x_grp, 2'b00};
    wire [2:0]  hit_cnt = I_hit[0] + I_hit[1] + I_hit[2] + I_hit[3];

    // 边缘屏蔽 —— 只屏蔽四角，不是整圈（2026-11-12 从 color_box_96 回填）
    //
    // CCL 重写时这里退回了"整圈屏蔽"：只要落在横向或纵向边距里就整片不采信，
    // 屏蔽掉 1 - (1120*630)/(1280*720) = 23.4% 的画面。
    // 而它要治的只是四角镜头色阴影，实际只涉及 4*80*45/(1280*720) = 1.56%，
    // 代价被放大了 15 倍；而且 in_field 同时门控组命中，完全落在边距环里的目标
    // 就是**永久性盲区**。
    // 改成只有同时在横向边距和纵向边距里才算四角，四条边的中点重新参与检测；
    // 实测（color_box_96 时期）贴边色块不再丢框。零额外 LUT。
    wire in_h_margin = (base_x <  EDGE_MASK_X) || (base_x >= (IMG_WIDTH  - EDGE_MASK_X));
    wire in_v_margin = (y_pos  <  EDGE_MASK_Y) || (y_pos  >= (IMG_HEIGHT - EDGE_MASK_Y));
    wire in_field    = !(in_h_margin && in_v_margin);

    wire grp_act = I_tvalid && (hit_cnt >= MIN_RUN) && in_field;

    wire [10:0] grp_min_x = base_x + (I_hit[3] ? 11'd0 :
                                      I_hit[2] ? 11'd1 :
                                      I_hit[1] ? 11'd2 : 11'd3);
    wire [10:0] grp_max_x = base_x + (I_hit[0] ? 11'd3 :
                                      I_hit[1] ? 11'd2 :
                                      I_hit[2] ? 11'd1 : 11'd0);

    wire [13:0] grp_sum_x = (I_hit[3] ? {3'b0,base_x}       : 14'd0) +
                            (I_hit[2] ? {3'b0,base_x} + 14'd1 : 14'd0) +
                            (I_hit[1] ? {3'b0,base_x} + 14'd2 : 14'd0) +
                            (I_hit[0] ? {3'b0,base_x} + 14'd3 : 14'd0);
    wire [12:0] grp_sum_y = {10'b0, hit_cnt} * {3'b0, y_pos};
    wire [2:0]  grp_cnt   = hit_cnt;

    wire [10:0] grp_lox = (base_x > (GAPX*4)) ? (base_x - (GAPX*4)) : 11'd0;
    wire [10:0] grp_hix = base_x + 11'd3 + (GAPX*4);

    // ---- 组合: 找可延续的轨迹 ---------------------------------------------
    // 从高索引往低索引扫, 低索引后写 -> 优先选低索引, 结果确定。
    //
    // 2026-10-07 修了一处 bug: 这里的上界原来写的是 (T_row[i] < y_pos)。
    // 但 T_row[m_idx] <= y_pos 是**非阻塞**赋值, 在本拍结束就把 T_row 刷成了 y_pos,
    // 于是同一行里第一个组更新完轨迹之后, 后面所有组算 (T_row < y_pos) 都是假
    // (y_pos < y_pos), 匹配不上 -> 只能再开新轨迹。
    // 后果: 一行里横向连续的色块被拆成一条条竖窄条, 8 条轨迹几行就塞满, 最大的
    // 那条只有一个组宽却贯穿整个高度 —— 框出来是竖条。
    // 改成 <= : 允许"本行已经更新过的轨迹继续被本行后续的组延续", 这正是横向
    // 连通性需要的。纵向分离不受影响 —— 上界仍是 (T_row >= y_pos - GAPY),
    // 隔了 3 行以上的老轨迹照样匹配不上。
    integer i;
    reg [3:0]  m_idx;
    reg        m_hit;
    always @(*) begin
        m_hit = 1'b0;
        m_idx = 4'd0;
        for (i = NTRK-1; i >= 0; i = i - 1) begin
            if (T_on[i] &&
                (y_pos > 10'd0) && (T_row[i] >= (y_pos - GAPY)) && (T_row[i] <= y_pos) &&
                (grp_lox <= T_x1[i]) && (grp_hix >= T_x0[i])) begin
                m_hit = 1'b1;
                m_idx = i[3:0];
            end
        end
    end

    // ---- 组合: 找一条空轨迹 (同样低索引优先) ------------------------------
    reg [3:0]  f_idx;
    reg        f_hit;
    always @(*) begin
        f_hit = 1'b0;
        f_idx = 4'd0;
        for (i = NTRK-1; i >= 0; i = i - 1) begin
            if (!T_on[i]) begin
                f_hit = 1'b1;
                f_idx = i[3:0];
            end
        end
    end

    // ---- 帧末: 把 4 条轨迹按 T_cnt 降序**排序** --------------------------
    // 2026-10-11: NTRK=4 时的一个巧合 —— "取前 4 大"就是"把 4 个元素排序"。
    // 一个 4 元素排序网络就够 (5 个比较器, 深度 3), 在 I_tuser 那一拍组合完成,
    // **不需要状态机、不需要影子表**。若 NTRK > K 就得做多趟选择, 复杂得多。
    //
    // 每个元素打包成 {cnt[17:0], on, idx[3:0]} = 23 位一起搬运; 平局保持原顺序。
    // 未启用的轨迹 on=0、cnt=0, 会被排到最后, 但它的框坐标还是上一帧的残留值,
    // 所以输出时还要用 on 门控 valid 位 (见 mkbox)。
    function [45:0] csort;          // 返回 {大的, 小的}
        input [22:0] a, b;
        begin
            csort = (a[22:5] >= b[22:5]) ? {a, b} : {b, a};
        end
    endfunction

    wire [45:0] C01 = csort({T_cnt[0], T_on[0], 4'd0}, {T_cnt[1], T_on[1], 4'd1});
    wire [45:0] C23 = csort({T_cnt[2], T_on[2], 4'd2}, {T_cnt[3], T_on[3], 4'd3});
    wire [45:0] CA  = csort(C01[45:23], C23[45:23]);
    wire [45:0] CB  = csort(C01[22: 0], C23[22: 0]);
    wire [45:0] CC  = csort(CA [22: 0], CB [45:23]);

    wire [22:0] SRT1 = CA[45:23];   // 最大
    wire [22:0] SRT2 = CC[45:23];   // 第二大
    wire [22:0] SRT3 = CC[22: 0];   // 第三
    wire [22:0] SRT4 = CB[22: 0];   // 最小

    // ---- 帧末锁存的 4 个 rank ---------------------------------------------
    // 每个 rank 一组框坐标 + 启用位 + 计数。rank1 额外要 Σx/Σy 来算真质心。
    // (原来这里还有一组 3 帧时域中值 H_*; 连通域版先去掉 —— 连通域的框本来就是
    //  整块的真实外接矩形, 且 AREA_TH 已经挡住了零星噪声块。若板上发现边界仍抖,
    //  再按 rank 各加一组 H_* 回来。)
    reg [10:0] W1_x0, W1_x1, W2_x0, W2_x1, W3_x0, W3_x1, W4_x0, W4_x1;
    reg [ 9:0] W1_y0, W1_y1, W2_y0, W2_y1, W3_y0, W3_y1, W4_y0, W4_y1;
    reg [17:0] W1_cnt, W2_cnt, W3_cnt, W4_cnt;
    reg        W1_on,  W2_on,  W3_on,  W4_on;
    reg [CNT_W-1:0] W_sx, W_sy, W_cnt;

    // rank2~4 的 cx/cy 用框中心
    wire [10:0] W2_cx = (W2_x0 + W2_x1) >> 1;
    wire [ 9:0] W2_cy = (W2_y0 + W2_y1) >> 1;
    wire [10:0] W3_cx = (W3_x0 + W3_x1) >> 1;
    wire [ 9:0] W3_cy = (W3_y0 + W3_y1) >> 1;
    wire [10:0] W4_cx = (W4_x0 + W4_x1) >> 1;
    wire [ 9:0] W4_cy = (W4_y0 + W4_y1) >> 1;

    // ---- 帧末轨迹合并（2026-11-12）----------------------------------------
    // 高光带把物体上下撕开后，两半变成两条独立轨迹，各自面积减半；
    // AREA_TH=300 一卡，两条都不报框 —— 表现就是"物体突然消失"。
    // CCL 的匹配每拍只认一条轨迹（低索引优先），所以永不合并。
    //
    // 这里在**帧末**把 rank1 与 rank2 在「纵向靠近 + 横向重叠」时合并：
    // 面积相加、bbox 取并集、valid 用合并后的面积去比 AREA_TH。
    // 纯组合、只在 tuser 那一拍求值，完全不碰像素通路，也不加存储。
    wire [10:0] w12_gap   = (W2_y0 > W1_y1) ? ({1'b0,W2_y0} - {1'b0,W1_y1}) :
                            (W1_y0 > W2_y1) ? ({1'b0,W1_y0} - {1'b0,W2_y1}) : 11'd0;
    wire        w12_ovl   = !(W1_x1 < W2_x0) && !(W2_x1 < W1_x0);
    wire        w12_merge = W1_on && W2_on &&
                            (W1_cnt >= 18'd32) && (W2_cnt >= 18'd32) &&
                            w12_ovl && (w12_gap <= 11'd32);
    wire [17:0] w12_cnt   = W1_cnt + W2_cnt;
    wire [10:0] w12_x0    = (W1_x0 < W2_x0) ? W1_x0 : W2_x0;
    wire [10:0] w12_x1    = (W1_x1 > W2_x1) ? W1_x1 : W2_x1;
    wire [ 9:0] w12_y0    = (W1_y0 < W2_y0) ? W1_y0 : W2_y0;
    wire [ 9:0] w12_y1    = (W1_y1 > W2_y1) ? W1_y1 : W2_y1;
    wire [11:0] w12_cxs   = {1'b0,w12_x0} + {1'b0,w12_x1};
    wire [10:0] w12_cx    = w12_cxs[11:1];
    wire [10:0] w12_cys   = {1'b0,w12_y0} + {1'b0,w12_y1};
    wire [ 9:0] w12_cy    = w12_cys[10:1];

    // ---- rank1 output deadband (2026-10-19) --------------------------------
    // Background pixels of a similar colour drift in and out of the blob, so
    // the connected-component box edges still wobble a few pixels per frame.
    // Ignore changes of <= 4 px on rank1 (the only rank that is drawn); real
    // motion is larger and updates immediately.
    // ---- 2026-11-12: 从"死区"改成"限速跟随" ------------------------------
    // 原来的做法是：变化 <= 4px 就保持旧值，**超过 4px 就直接跳到新值** ——
    // 背景像素一进一出把 bbox 撑开 20 像素时，框会立刻跳过去，上板表现就是
    // "框抖得厉害"。死区只压得住小幅抖动，压不住单帧异常跳变。
    //
    // 改成每帧最多移动 SLEW 像素：
    //   · 目标没动 → 框不动（等价死区）
    //   · 有微小抖动 → 每帧挪 8px 就收敛回来，不会来回跳
    //   · 真实运动 → 平滑跟随，最快 8px/帧 ≈ 480px/s
    localparam [10:0] SLEW   = 11'd8;
    localparam [ 9:0] SLEW_Y = 10'd8;
    reg [10:0] D_x0, D_x1;
    reg [ 9:0] D_y0, D_y1;

    wire [10:0] O_bx0 = (W1_x0 > (D_x0 + SLEW  )) ? (D_x0 + SLEW  ) :
                        (W1_x0 + SLEW   < D_x0  ) ? (D_x0 - SLEW  ) : W1_x0;
    wire [10:0] O_bx1 = (W1_x1 > (D_x1 + SLEW  )) ? (D_x1 + SLEW  ) :
                        (W1_x1 + SLEW   < D_x1  ) ? (D_x1 - SLEW  ) : W1_x1;
    wire [ 9:0] O_by0 = (W1_y0 > (D_y0 + SLEW_Y)) ? (D_y0 + SLEW_Y) :
                        (W1_y0 + SLEW_Y < D_y0  ) ? (D_y0 - SLEW_Y) : W1_y0;
    wire [ 9:0] O_by1 = (W1_y1 > (D_y1 + SLEW_Y)) ? (D_y1 + SLEW_Y) :
                        (W1_y1 + SLEW_Y < D_y1  ) ? (D_y1 - SLEW_Y) : W1_y1;
    // 质心直接用平滑后的框中心，和 rank2~4 的口径一致
    wire [10:0] O_bcx = (O_bx0 + O_bx1) >> 1;
    wire [ 9:0] O_bcy = (O_by0 + O_by1) >> 1;

    // 拼一个 64 位的 rank 记录, 格式与 color_box_96 完全一致
    function [63:0] mkbox;
        input        on;
        input [17:0] cnt;
        input [10:0] x0, x1, cx;
        input [ 9:0] y0, y1, cy;
        reg [11:0] bw, bh;
        begin
            // 2026-11-12: 加 bbox 形状合理性判据。
            // 纯颜色判据之下，一条细长的高光带、一片纹理噪点都能积到 AREA_TH
            // 以上并被当成目标。真色块是**近似正方形、有最小尺寸**的，
            // 所以这里补两道纯比较器的检查（0 乘法、0 存储）：
            //   1) 宽高都 >= 8 像素 —— 排除细碎
            //   2) 宽高比在 1:4 ~ 4:1 之间 —— 排除细长条
            // 注意这只收紧"报不报框"，不影响 CCL 的轨迹跟踪。
            bw = {1'b0,x1} - {1'b0,x0} + 12'd1;
            bh = {2'b0,y1} - {2'b0,y0} + 12'd1;
            mkbox = { cy, cx,
                      (on && (cnt >= AREA_TH)
                          && (bw >= 12'd8) && (bh >= 12'd8)
                          && (bw <= (bh << 2)) && (bh <= (bw << 2))),
                      x0, x1, y0, y1 };
        end
    endfunction

    // 帧末除法 (算 rank1 的真质心, 移位减法, 每帧几十拍, 不占资源)
    localparam DIV_STEPS = CNT_W;
    reg [CNT_W-1:0] S_div_rem, S_div_quo;
    reg [5:0]  S_div_i;
    reg        S_div_2nd;
    reg        S_div_pend;      // tuser 后一拍才装载除法 (等 W_sx/W_cnt 锁存生效)
    reg [10:0] S_cx;
    reg [9:0]  S_cy;

    // ★ 除数用**锁存后的** W_cnt, 不用活的 T_* —— 除法在 I_tuser 之后才跑,
    //   那时轨迹表已经被清空、准备收新一帧了。原来的 color_box_96 就是栽在
    //   这个"除数是活值"上 (见那边的注释)。
    wire [CNT_W-1:0] S_div_sh = {S_div_rem[CNT_W-2:0], S_div_quo[CNT_W-1]};
    wire             S_div_ge = (S_div_sh >= W_cnt);

    integer k;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_boxes <= {4{64'd0}};
            x_grp <= 9'd0;
            y_pos <= 10'd0;
            for (k = 0; k < NTRK; k = k + 1) begin
                T_on[k]  <= 1'b0;
                T_x0[k]  <= 11'd0; T_x1[k] <= 11'd0;
                T_y0[k]  <= 10'd0; T_y1[k] <= 10'd0;
                T_cnt[k] <= 18'd0;
                T_sx[k]  <= {CNT_W{1'b0}}; T_sy[k] <= {CNT_W{1'b0}};
                T_row[k] <= 10'd0;
            end
            W1_x0 <= 11'd0; W1_x1 <= 11'd0; W1_y0 <= 10'd0; W1_y1 <= 10'd0;
            W2_x0 <= 11'd0; W2_x1 <= 11'd0; W2_y0 <= 10'd0; W2_y1 <= 10'd0;
            W3_x0 <= 11'd0; W3_x1 <= 11'd0; W3_y0 <= 10'd0; W3_y1 <= 10'd0;
            W4_x0 <= 11'd0; W4_x1 <= 11'd0; W4_y0 <= 10'd0; W4_y1 <= 10'd0;
            W1_cnt <= 18'd0; W2_cnt <= 18'd0; W3_cnt <= 18'd0; W4_cnt <= 18'd0;
            W1_on <= 1'b0;  W2_on <= 1'b0;  W3_on <= 1'b0;  W4_on <= 1'b0;
            W_cnt <= 18'd0; W_sx <= {CNT_W{1'b0}}; W_sy <= {CNT_W{1'b0}};
            S_div_rem <= {CNT_W{1'b0}}; S_div_quo <= {CNT_W{1'b0}};
            S_div_i <= 6'd0; S_div_2nd <= 1'b0; S_div_pend <= 1'b0;
            S_cx <= 11'd0; S_cy <= 10'd0;
            D_x0 <= 11'd0; D_x1 <= 11'd0; D_y0 <= 10'd0; D_y1 <= 10'd0;
        end else begin
            // ---- 帧开始: 输出上一帧排好的 4 个 rank + 锁存本帧 -----------------
            if (I_tuser) begin
                // (1) 输出 —— 用上一拍锁存的 W1..W4, 和上一帧算好的 rank1 真质心。
                //     非阻塞赋值, 所以下面"锁存本帧"那一段不会影响这里读到的值。
                // rank1/rank2 判定为同一物体时：rank1 输出合并框，rank2 置空，
                // 这样不会出现"一个物体两个框"，也不会因为各自面积不足而一起消失。
                O_boxes <= {
                    mkbox(W4_on, W4_cnt, W4_x0, W4_x1, W4_cx, W4_y0, W4_y1, W4_cy),
                    mkbox(W3_on, W3_cnt, W3_x0, W3_x1, W3_cx, W3_y0, W3_y1, W3_cy),
                    w12_merge ? 64'd0
                              : mkbox(W2_on, W2_cnt, W2_x0, W2_x1, W2_cx, W2_y0, W2_y1, W2_cy),
                    w12_merge ? mkbox(1'b1, w12_cnt, w12_x0, w12_x1, w12_cx, w12_y0, w12_y1, w12_cy)
                              : mkbox(W1_on, W1_cnt, O_bx0, O_bx1, O_bcx, O_by0, O_by1, O_bcy) };

                // (2) 锁存本帧排好序的 4 个 rank —— 此刻轨迹表里还是刚跑完那一帧的结果
                W1_on  <= SRT1[4];  W1_cnt <= SRT1[22:5];
                if (W1_on && (W1_cnt >= AREA_TH)) begin
                    D_x0 <= O_bx0; D_x1 <= O_bx1; D_y0 <= O_by0; D_y1 <= O_by1;
                end
                W1_x0  <= T_x0[SRT1[3:0]];  W1_x1 <= T_x1[SRT1[3:0]];
                W1_y0  <= T_y0[SRT1[3:0]];  W1_y1 <= T_y1[SRT1[3:0]];
                W2_on  <= SRT2[4];  W2_cnt <= SRT2[22:5];
                W2_x0  <= T_x0[SRT2[3:0]];  W2_x1 <= T_x1[SRT2[3:0]];
                W2_y0  <= T_y0[SRT2[3:0]];  W2_y1 <= T_y1[SRT2[3:0]];
                W3_on  <= SRT3[4];  W3_cnt <= SRT3[22:5];
                W3_x0  <= T_x0[SRT3[3:0]];  W3_x1 <= T_x1[SRT3[3:0]];
                W3_y0  <= T_y0[SRT3[3:0]];  W3_y1 <= T_y1[SRT3[3:0]];
                W4_on  <= SRT4[4];  W4_cnt <= SRT4[22:5];
                W4_x0  <= T_x0[SRT4[3:0]];  W4_x1 <= T_x1[SRT4[3:0]];
                W4_y0  <= T_y0[SRT4[3:0]];  W4_y1 <= T_y1[SRT4[3:0]];
                // rank1 的 Σx/Σy/总面积 (只有它算真质心)
                W_sx   <= T_sx[SRT1[3:0]];  W_sy  <= T_sy[SRT1[3:0]];
                W_cnt  <= SRT1[22:5];

                // 清轨迹表
                for (k = 0; k < NTRK; k = k + 1) begin
                    T_on[k]  <= 1'b0;
                    T_cnt[k] <= 18'd0;
                    T_sx[k]  <= {CNT_W{1'b0}};
                    T_sy[k]  <= {CNT_W{1'b0}};
                end

                // 除法**推到下一拍再装载** —— 因为被除数和除数是本拍刚锁存的
                // W_sx/W_sy/W_cnt (非阻塞赋值, 下一拍才生效)。晚一拍装载, 除法
                // 全程用的都是这几个稳定的锁存值, 不受上游新一帧的影响。
                S_div_pend <= 1'b1;
                S_div_i    <= 6'd0;

                if (!I_tvalid) begin
                    x_grp <= 9'd0;
                    y_pos <= 10'd0;
                end
            end

            // ---- 帧末除法: 装载一拍, 然后顺序移位减法 -----------------------
            if (!I_tuser && S_div_pend) begin
                S_div_pend <= 1'b0;
                S_div_2nd  <= 1'b0;
                S_div_i    <= 6'd1;
                S_div_rem  <= {CNT_W{1'b0}};
                S_div_quo  <= W_sx;              // 此刻 W_sx 已经是本帧锁存好的
            end
            else if (!I_tuser && (S_div_i != 6'd0)) begin
                S_div_rem <= S_div_ge ? (S_div_sh - W_cnt) : S_div_sh;
                S_div_quo <= {S_div_quo[CNT_W-2:0], S_div_ge};

                if (S_div_i == DIV_STEPS) begin
                    if (S_div_2nd == 1'b0) begin
                        // ★ 第 28 次移位的结果就是本拍被丢弃的那一位 (S_div_ge)。
                        //   原来写 S_div_quo[10:0], 读到的是**第 27 次移位之后**的
                        //   寄存器 —— 取到的正好是 真商 >> 1, 质心被减半。
                        S_cx      <= {S_div_quo[9:0], S_div_ge};
                        S_div_2nd <= 1'b1;
                        S_div_rem <= {CNT_W{1'b0}};
                        S_div_quo <= W_sy;
                        S_div_i   <= 6'd1;
                    end else begin
                        S_cy    <= {S_div_quo[8:0], S_div_ge};
                        S_div_i <= 6'd0;
                    end
                end else
                    S_div_i <= S_div_i + 6'd1;
            end

            // ---- 逐拍推进: 更新轨迹 ----------------------------------------
            if (grp_act) begin
                if (m_hit) begin
                    if (grp_min_x < T_x0[m_idx]) T_x0[m_idx] <= grp_min_x;
                    if (grp_max_x > T_x1[m_idx]) T_x1[m_idx] <= grp_max_x;
                    if (y_pos     < T_y0[m_idx]) T_y0[m_idx] <= y_pos;
                    T_y1[m_idx]  <= y_pos;
                    T_cnt[m_idx] <= T_cnt[m_idx] + {15'd0, grp_cnt};
                    T_sx[m_idx]  <= T_sx[m_idx] + {14'd0, grp_sum_x};
                    T_sy[m_idx]  <= T_sy[m_idx] + {15'd0, grp_sum_y};
                    T_row[m_idx] <= y_pos;
                end else if (f_hit) begin
                    // 没有可延续的 -> 开一条新轨迹 (表满就丢掉这个组)
                    T_on[f_idx]  <= 1'b1;
                    T_x0[f_idx]  <= grp_min_x;
                    T_x1[f_idx]  <= grp_max_x;
                    T_y0[f_idx]  <= y_pos;
                    T_y1[f_idx]  <= y_pos;
                    T_cnt[f_idx] <= {15'd0, grp_cnt};
                    T_sx[f_idx]  <= {14'd0, grp_sum_x};
                    T_sy[f_idx]  <= {15'd0, grp_sum_y};
                    T_row[f_idx] <= y_pos;
                end
            end

            // ---- 位置推进 --------------------------------------------------
            if (I_tvalid) begin
                if (x_grp == GRP_LAST) begin
                    x_grp <= 9'd0;
                    y_pos <= (y_pos == IMG_HEIGHT - 1) ? 10'd0 : (y_pos + 10'd1);
                end else
                    x_grp <= x_grp + 9'd1;
            end
        end
    end

endmodule

// ============================================================================
// color_box_hold_96 —— 色块结果的帧间滞回（2026-11-12）
//
// 为什么需要它
// ------------
// color_box_ccl_96 每帧独立判定 valid = on && (cnt >= AREA_TH)。面积在门限
// 附近抖动时，框会逐帧闪烁；某帧偶尔丢检时，框直接消失。上板表现就是
// "特别不稳定"。
//
// 参考同器件的公开实现，结果通路普遍带三样东西：
//   - 新鲜度 result_fresh / ready（结果是否可信、多久以前的）
//   - dwell（连续停留若干帧才确认）
//   - gain_change（增益变化直接作废）
// 这里取其前两条，做一级**帧间滞回 + 保持**：
//   · 连续 ON_N 帧检测到才点亮（滤掉单帧噪点）
//   · 丢失后保持 HOLD_N 帧，期间输出**最后一次的好框**（框冻结而不是消失）
// 只作用于送显示的那一路 rank1，不动跟踪内核，所以最坏情况是"框多停一会"。
//
// 64 位框布局与 color_box_ccl_96 一致：
//   {cy[9:0], cx[10:0], valid, left[10:0], right[10:0], top[9:0], bottom[9:0]}
//   bit42 = valid
// ============================================================================
module color_box_hold_96 #(
    parameter [1:0] ON_N   = 2'd2,   // 连续多少帧才点亮
    parameter [3:0] HOLD_N = 4'd8    // 丢失后保持多少帧
)(
    input              I_clk,
    input              I_rst_n,
    input              I_tuser,       // 帧边界（gam_tuser）
    input      [191:0] I_boxes,       // 3 色 x 64bit rank1
    output wire[191:0] O_boxes
);

    genvar gi;
    generate for (gi = 0; gi < 3; gi = gi + 1) begin : g_hold
        wire [63:0] bin = I_boxes[gi*64 +: 64];
        wire        inv = bin[42];

        reg [63:0] keep;     // 最后一次检测到的好框
        reg [1:0]  onc;      // 连续有效帧数（饱和 ON_N）
        reg [3:0]  msc;      // 连续丢失帧数（饱和 HOLD_N）
        reg        ok;       // 当前是否对外有效

        always @(posedge I_clk or negedge I_rst_n) begin
            if (!I_rst_n) begin
                keep <= 64'd0;
                onc  <= 2'd0;
                msc  <= HOLD_N;
                ok   <= 1'b0;
            end else if (I_tuser) begin
                if (inv) begin
                    keep <= bin;
                    if (onc != ON_N) onc <= onc + 2'd1;
                    msc  <= 4'd0;
                    ok   <= (onc >= (ON_N - 2'd1)) ? 1'b1 : ok;
                end else begin
                    onc <= 2'd0;
                    if (msc != HOLD_N) msc <= msc + 4'd1;
                    ok  <= (msc >= (HOLD_N - 4'd1)) ? 1'b0 : ok;
                end
            end
        end

        // 坐标保持 keep，只有 valid 位跟着滞回状态走。
        // 用组合输出而不是再打一拍 —— keep 本身就是寄存器，输出已经稳定，
        // 多一级只会白花 192 个 FF（上一版实测 u_boxhold 花了 395 个 seq）。
        assign O_boxes[gi*64 +: 64] = {keep[63:43], ok, keep[41:0]};
    end endgenerate

endmodule

// ============================================================================
// edge_detect_96 —— Sobel 边缘检测（2026-11-11 全分辨率重写）
//
// 为什么写在这个文件里: TD 每次 GUI 保存会重写工程文件(.al), 手工加进去的
// 独立源文件会被丢掉 (denoise_96 就这么丢过, 报 HDL-8007: black box)。
// 所以新模块必须塞进已在 .al 列表里的文件 —— isp_top.v 就在列表里。
//
// 为什么重写
// ----------
// 旧版先把相邻两个像素平均成一个 pair（水平 2:1 降采样），再在 pair 网格上做
// Sobel。1 px 细线的梯度响应只剩全分辨率的一半，实测文字笔画会糊成实心块。
// 用 numpy 位精确模型量化（工具见 fpga/tools/edge_compare.py）：
//     text 图边缘像素  旧 76.6 个/行 → 新 61.4 个/行，笔画之间重新分开。
// 现在改成**全分辨率 3x3 Sobel**，一拍直接算 4 个像素。
//
// 三个实现要点
// ------------
// 1) 行缓存改成 320 x 32 bit（一拍 4 个灰度像素一个 word），并且**同步读**才能
//    推断成 ERAM。旧版是异步读，ram_style="block" 根本没生效——实测 u_edge
//    ERAM=0、DRAM=256，那 256 个 LUT 比 2 块 ERAM 贵得多。
// 2) 同步读天然晚一拍，所以本模块变成**两拍延迟**（旧版一拍）。isp_top 里的
//    原图分支必须跟着多延一拍，否则卡通模式的描边会和色块错位。
// 3) Sobel 窗口用**后向**（中心落在第 i-1 个像素），这样一个 6 列窗口就能把 4 个
//    像素全算完，不用等下一组的第一个像素。代价是边缘整体右移 1 px
//    （旧版是右移 2 px，反而更偏）。
//
// 资源: 2 块 ERAM + 纯移位加减，0 DSP。
// 输出: 白边黑底（边缘=0xffffff，非边缘=0x000000），门限由 I_edge_th 给。
// ============================================================================
module edge_detect_96 #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,
    parameter EDGE_TH    = 11'd80    // 缺省门，实际门限仍由上层 I_edge_th 输入
)(
    input               I_clk,
    input               I_rst_n,
    input               I_tlast,
    input               I_tuser,
    input      [95:0]   I_tdata,
    input               I_tvalid,
    input               I_tready,
    // 门限由上层传入：边缘显示使用 80，卡通描边使用 60。
    input      [10:0]   I_edge_th,
    output reg          O_tlast,
    output reg          O_tuser,
    output reg [95:0]   O_tdata,
    output reg [3:0]    O_strong,
    output reg          O_tvalid,
    output              O_tready
);

assign O_tready = I_tready;

localparam GRP_W = IMG_WIDTH  >> 2;      // 320 组/行
localparam LAST  = GRP_W - 1;

// ---------------------------------------------------------------- 灰度
wire [23:0] pix0 = I_tdata[95:72];
wire [23:0] pix1 = I_tdata[71:48];
wire [23:0] pix2 = I_tdata[47:24];
wire [23:0] pix3 = I_tdata[23: 0];

// R/4 + G/2 + B/4：最大值 253，不会溢出 8 bit，纯移位加减，与旧版一致。
wire [7:0] gray0 = {2'b0,pix0[23:18]} + {1'b0,pix0[15:9]} + {2'b0,pix0[7:2]};
wire [7:0] gray1 = {2'b0,pix1[23:18]} + {1'b0,pix1[15:9]} + {2'b0,pix1[7:2]};
wire [7:0] gray2 = {2'b0,pix2[23:18]} + {1'b0,pix2[15:9]} + {2'b0,pix2[7:2]};
wire [7:0] gray3 = {2'b0,pix3[23:18]} + {1'b0,pix3[15:9]} + {2'b0,pix3[7:2]};

wire [31:0] bot_word = {gray0, gray1, gray2, gray3};

// ---------------------------------------------------------------- 行缓存
// 两块 320x32 的缓冲：mem0 = 第 y-1 行，mem1 = 第 y-2 行。
//
// 同步读天生晚一拍，这里用「预取下一拍才会用到的地址」把它补回来：
// 这一拍给地址，下一拍读出的数据正好对应当前像素，主通路**零额外延迟**，
// 模块总延迟仍是 1 拍（不需要外部再补一条延迟链）。
// 回绕时预取地址可能撞上写地址，用写转发旁路，不依赖 RAM 的 read-during-write 模式。
//
// ★ 属性值：TD 只认 ram_style = "bram"，不认 "block"（TD 自带 IP 的写法）。
//   写 "block" 会被静默忽略，两块缓冲摊成 512 个 DRAM LUT。
//
// ★ 2026-11-12 实测：**就算写 "bram"，TD 也不会把 320 深的 RAM 映射到 ERAM**
//   （构建报告 u_edge：eram=0、dram lut=512）。TD 是按**声明深度**做资源决策的，
//   320x32 = 10240 bit 太小，它就给了分布式 RAM。
//   对策：把声明深度拉到 1024（实际只用 0..319）。1024x32 = 32768 bit，用分布式
//   RAM 实现要 ~800 个 LUT，综合器只能走 ERAM；每块占 2 个 ERAM，两块共 4 块
//   （当前 ERAM 80/108，放得下）。地址只用低 9 位，高 2 位恒 0。
//
// ★ 2026-11-12 起字宽 32 -> 36：多存 4 个"强边位"（每像素 1 bit），
//   供双门限滞回判断上一行的邻域支撑。1024x36 仍然只占 2 个 ERAM 块。
(* ram_style = "bram" *) reg [35:0] mem0 [0:1023];   // {强边位[3:0], 第 y-1 行灰度}
(* ram_style = "bram" *) reg [35:0] mem1 [0:1023];   // {强边位[3:0], 第 y-2 行灰度}

reg [10:0] x_grp;        // 组号 0..319
reg [9:0]  y_pos;        // 行号 0..719

reg [35:0] r0, r1;       // 同步读输出
reg [35:0] fwd0, fwd1;   // 写转发值
reg        col_l;        // 上一拍是否发生预取/写地址冲突

// 强边位（本组的 4 个像素），后面才赋值，这里先声明给写端口用
wire e0, e1, e2, e3;

wire        de       = I_tvalid;
wire        tuser_v  = I_tuser && I_tvalid;
wire [10:0] cur_addr = tuser_v ? 11'd0 : x_grp;
// 预取：这一拍给出「下一拍才会用到」的组号
wire [10:0] pf_addr  = (!de || cur_addr == LAST) ? 11'd0 : (cur_addr + 11'd1);
wire        col_hit  = de && (pf_addr == cur_addr);
wire [35:0] mid_word = col_l ? fwd0 : r0;   // 第 y-1 行（本组）
wire [35:0] top_word = col_l ? fwd1 : r1;   // 第 y-2 行（本组）
wire [31:0] mid_gray = mid_word[31:0];      // 第 y-1 行灰度
wire [31:0] top_gray = top_word[31:0];      // 第 y-2 行灰度
wire [3:0]  mid_sb   = mid_word[35:32];     // 第 y-1 行强边位，bit3 = 最左像素

always @(posedge I_clk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        x_grp <= 11'd0;
        y_pos <= 10'd0;
        r0    <= 36'd0;
        r1    <= 36'd0;
        fwd0  <= 36'd0;
        fwd1  <= 36'd0;
        col_l <= 1'b0;
    end else begin
        // ---- 预取读：地址是下一拍要用的组号 ----
        r0 <= mem0[pf_addr];
        r1 <= mem1[pf_addr];

        // ---- 写转发：万一回绕撞地址，用写数据旁路 ----
        col_l <= col_hit;
        fwd0  <= {e0,e1,e2,e3, bot_word};
        fwd1  <= mid_word;

        // ---- 写：本行（灰度 + 强边位）进 mem0，第 y-1 行滚动进 mem1 ----
        if (de) begin
            mem0[cur_addr] <= {e0,e1,e2,e3, bot_word};
            mem1[cur_addr] <= mid_word;
        end

        if (de) begin
            if (I_tuser) begin
                x_grp <= 11'd1;
                y_pos <= 10'd0;
            end else if (cur_addr == LAST) begin
                x_grp <= 11'd0;
                y_pos <= (y_pos == IMG_HEIGHT - 1) ? 10'd0 : (y_pos + 10'd1);
            end else begin
                x_grp <= x_grp + 11'd1;
            end
        end
    end
end

// ------------------------------------------------- 上一组的最后两个像素
// 后向窗口要拿左边两个邻居，它们来自上一组的 pixel2/pixel3。
reg [7:0] t_c2, t_c1, m_c2, m_c1, b_c2, b_c1;

always @(posedge I_clk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        t_c2 <= 8'd0; t_c1 <= 8'd0;
        m_c2 <= 8'd0; m_c1 <= 8'd0;
        b_c2 <= 8'd0; b_c1 <= 8'd0;
    end else if (I_tvalid) begin
        t_c2 <= top_gray[15: 8]; t_c1 <= top_gray[ 7: 0];
        m_c2 <= mid_gray[15: 8]; m_c1 <= mid_gray[ 7: 0];
        b_c2 <= bot_word[15: 8]; b_c1 <= bot_word[ 7: 0];
    end
end

// ------------------------------------------------- 6 列 x 3 行窗口
wire [7:0] t0 = t_c2, t1 = t_c1;
wire [7:0] t2 = top_gray[31:24], t3 = top_gray[23:16];
wire [7:0] t4 = top_gray[15: 8], t5 = top_gray[ 7: 0];

wire [7:0] m0 = m_c2, m1 = m_c1;
wire [7:0] m2 = mid_gray[31:24], m3 = mid_gray[23:16];
wire [7:0] m4 = mid_gray[15: 8], m5 = mid_gray[ 7: 0];

wire [7:0] b0 = b_c2, b1 = b_c1;
wire [7:0] b2 = bot_word[31:24], b3 = bot_word[23:16];
wire [7:0] b4 = bot_word[15: 8], b5 = bot_word[ 7: 0];

// 纵向 1-2-1 加权和：V[j] = top[j] + 2*mid[j] + bot[j]
// 4 个像素共用这 6 个 V，不用各算一遍。
wire [9:0] V0 = {2'b0,t0} + {1'b0,m0,1'b0} + {2'b0,b0};
wire [9:0] V1 = {2'b0,t1} + {1'b0,m1,1'b0} + {2'b0,b1};
wire [9:0] V2 = {2'b0,t2} + {1'b0,m2,1'b0} + {2'b0,b2};
wire [9:0] V3 = {2'b0,t3} + {1'b0,m3,1'b0} + {2'b0,b3};
wire [9:0] V4 = {2'b0,t4} + {1'b0,m4,1'b0} + {2'b0,b4};
wire [9:0] V5 = {2'b0,t5} + {1'b0,m5,1'b0} + {2'b0,b5};

// 横向 1-2-1 加权和：HT/HB 只算上、下两行
wire [9:0] HT0 = {2'b0,t0} + {1'b0,t1,1'b0} + {2'b0,t2};
wire [9:0] HT1 = {2'b0,t1} + {1'b0,t2,1'b0} + {2'b0,t3};
wire [9:0] HT2 = {2'b0,t2} + {1'b0,t3,1'b0} + {2'b0,t4};
wire [9:0] HT3 = {2'b0,t3} + {1'b0,t4,1'b0} + {2'b0,t5};
wire [9:0] HB0 = {2'b0,b0} + {1'b0,b1,1'b0} + {2'b0,b2};
wire [9:0] HB1 = {2'b0,b1} + {1'b0,b2,1'b0} + {2'b0,b3};
wire [9:0] HB2 = {2'b0,b2} + {1'b0,b3,1'b0} + {2'b0,b4};
wire [9:0] HB3 = {2'b0,b3} + {1'b0,b4,1'b0} + {2'b0,b5};

// 梯度：gx = V[i] - V[i-2]，gy = HT[i] - HB[i]
wire signed [10:0] gx0 = $signed({1'b0,V0}) - $signed({1'b0,V2});
wire signed [10:0] gx1 = $signed({1'b0,V1}) - $signed({1'b0,V3});
wire signed [10:0] gx2 = $signed({1'b0,V2}) - $signed({1'b0,V4});
wire signed [10:0] gx3 = $signed({1'b0,V3}) - $signed({1'b0,V5});
wire signed [10:0] gy0 = $signed({1'b0,HT0}) - $signed({1'b0,HB0});
wire signed [10:0] gy1 = $signed({1'b0,HT1}) - $signed({1'b0,HB1});
wire signed [10:0] gy2 = $signed({1'b0,HT2}) - $signed({1'b0,HB2});
wire signed [10:0] gy3 = $signed({1'b0,HT3}) - $signed({1'b0,HB3});

wire [10:0] ax0 = gx0[10] ? (~gx0 + 11'd1) : gx0[10:0];
wire [10:0] ax1 = gx1[10] ? (~gx1 + 11'd1) : gx1[10:0];
wire [10:0] ax2 = gx2[10] ? (~gx2 + 11'd1) : gx2[10:0];
wire [10:0] ax3 = gx3[10] ? (~gx3 + 11'd1) : gx3[10:0];
wire [10:0] ay0 = gy0[10] ? (~gy0 + 11'd1) : gy0[10:0];
wire [10:0] ay1 = gy1[10] ? (~gy1 + 11'd1) : gy1[10:0];
wire [10:0] ay2 = gy2[10] ? (~gy2 + 11'd1) : gy2[10:0];
wire [10:0] ay3 = gy3[10] ? (~gy3 + 11'd1) : gy3[10:0];

wire [11:0] mag0 = {1'b0,ax0} + {1'b0,ay0};
wire [11:0] mag1 = {1'b0,ax1} + {1'b0,ay1};
wire [11:0] mag2 = {1'b0,ax2} + {1'b0,ay2};
wire [11:0] mag3 = {1'b0,ax3} + {1'b0,ay3};

// 前两行、每行第一组没有完整的左邻，直接置黑。
wire        win_ok = (y_pos >= 10'd2) && (cur_addr != 11'd0);

// ---------------------------------------------------------------- 双门限滞回
// 2026-11-12 上板照片确认：单一门限分不开"家具轮廓"和"墙面/木纹纹理"，
// 两者的梯度幅值区间是重叠的，调高就丢轮廓、调低就满屏噪点。
//
// 改成 Canny 的双门限滞回（不做 NMS）：
//   · 强边（mag >= HI，即 I_edge_th）→ 一定要
//   · 弱边（mag >= HI/2）→ 只有 3x3 邻域里连到强边时才保留
// 真轮廓的旁边总有强边，所以连通性保住；孤立纹理斑点周围没有强边，被剔掉。
//
// 邻域只用**已经看到过的**像素（因果）：
//   上一行（mem0 里存的 mid 强边位）：pixel i-1 / i / i+1
//   本行：左邻 pixel i-1
wire [11:0] th_ext = {1'b0, I_edge_th};
wire [11:0] lo_ext = {2'b0, I_edge_th[10:1]};   // 强门限的一半

assign e0 = win_ok && (mag0 >= th_ext);
assign e1 = win_ok && (mag1 >= th_ext);
assign e2 = win_ok && (mag2 >= th_ext);
assign e3 = win_ok && (mag3 >= th_ext);

wire w0 = win_ok && (mag0 >= lo_ext);
wire w1 = win_ok && (mag1 >= lo_ext);
wire w2 = win_ok && (mag2 >= lo_ext);
wire w3 = win_ok && (mag3 >= lo_ext);

// 上一组的边缘强边位（本行 pixel3 / 上一行 pixel3）
reg sb_p, msb_p;
always @(posedge I_clk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        sb_p  <= 1'b0;
        msb_p <= 1'b0;
    end else if (I_tvalid) begin
        sb_p  <= e3;
        msb_p <= mid_sb[0];
    end
end

// 邻域支撑：本行左邻 + 上一行 3 个（pixel i-1 / i / i+1）
wire sup0 = sb_p || msb_p   || mid_sb[3] || mid_sb[2];
wire sup1 = e0   || mid_sb[3] || mid_sb[2] || mid_sb[1];
wire sup2 = e1   || mid_sb[2] || mid_sb[1] || mid_sb[0];
wire sup3 = e2   || mid_sb[1] || mid_sb[0];

wire k0 = e0 || (w0 && sup0);
wire k1 = e1 || (w1 && sup1);
wire k2 = e2 || (w2 && sup2);
wire k3 = e3 || (w3 && sup3);

// ---------------------------------------------------------------- 显示输出
// 仍是二值（白边黑底）。门限由上层 I_edge_th 给，当前 60；弱门限自动取一半。
wire [23:0] o0 = k0 ? 24'hffffff : 24'h000000;
wire [23:0] o1 = k1 ? 24'hffffff : 24'h000000;
wire [23:0] o2 = k2 ? 24'hffffff : 24'h000000;
wire [23:0] o3 = k3 ? 24'hffffff : 24'h000000;

always @(posedge I_clk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        O_tdata  <= 96'd0;
        O_strong <= 4'd0;
        O_tvalid <= 1'b0;
        O_tuser  <= 1'b0;
        O_tlast  <= 1'b0;
    end else begin
        O_tdata  <= I_tvalid ? {o0,o1,o2,o3} : 96'd0;
        O_strong <= I_tvalid ? {e0,e1,e2,e3} : 4'd0;
        O_tvalid <= I_tvalid;
        O_tuser  <= I_tuser;
        O_tlast  <= I_tlast;
    end
end

endmodule


// ============================================================================
// cartoon_effect_96 —— 卡通化: 区域填充 + 边缘描边 (2026-10-10 从 One 工程搬来)
//
// 对应**基础扩展要求(1)「视频图像风格化处理或视觉增强, 如边缘提取与区域填充」**。
// 做法: 非边缘处把每个通道量化到高 2 位(海报化, 64 色)得到平坦色块,
//       边缘处涂黑 —— 合起来就是卡通效果。
//
// 纯组合逻辑: **无寄存器、无行缓存、无乘法器**。
// I_color 用原图(raw_tdata_d), I_edge 用 edge_detect_96 的输出 —— 两者本来
// 就同拍(都在 gamma+1), 所以**不需要任何额外对齐逻辑**。
// ============================================================================
// 扩展要求(1) 风格化/视觉增强：边缘提取 + 区域填充（卡通化）。
//
// 纯组合逻辑，无行缓存、无时钟。I_color 是 AWB 输出的原图（4 像素），
// I_edge 是 edge_detect_96 的输出（边缘为白色 0xffffff）。二者必须逐拍对齐
// （在 isp_top 中均由 AWB 流延迟一拍得到）。输出：边缘处涂黑，非边缘处把
// 每个颜色通道量化到 QUANT_BITS 位（海报化），得到平坦色块 + 黑色描边的
// 卡通效果。
module cartoon_effect_96 #(
    parameter QUANT_BITS = 2    // 2 => 64 色（明显卡通）；4 => 4096 色（较柔和）
)(
    input      [95:0] I_color,   // 4 x RGB888 原图
    input      [3:0]  I_strong,  // 每像素 1 位强边标志，bit3 = 最左像素
    output reg [95:0] O_cartoon,
    input             I_clk,
    input             I_rst_n
);

    // 3-tap horizontal smoothing before quantisation.
    // Flat areas carry 3~5 codes of sensor noise; quantising to 8 levels per
    // channel turns that into 32-code jumps -> visible flicker. Averaging the
    // left/centre/right neighbours first halves that noise and softens band
    // edges. Pure shift-add: no DSP.
    // col_d/edg_d delay one 4-pixel group so a left neighbour exists; the last
    // pixel of a group uses this group's first pixel as its right neighbour
    // (a 4-pixel error, invisible).
    reg  [95:0] col_d;
    reg  [3:0]  strong_d;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            col_d    <= 96'd0;
            strong_d <= 4'd0;
        end else begin
            col_d    <= I_color;
            strong_d <= I_strong;
        end
    end

    function [7:0] f_sm;
        input [7:0] l, c, r;
        begin
            f_sm = ({2'b0,l} + {1'b0,c,1'b0} + {2'b0,r}) >> 2;   // 10-bit sum
        end
    endfunction

    wire [23:0] d0 = col_d[95:72];
    wire [23:0] d1 = col_d[71:48];
    wire [23:0] d2 = col_d[47:24];
    wire [23:0] d3 = col_d[23: 0];
    wire [23:0] n0r = d1;
    wire [23:0] n1l = d0, n1r = d2;
    wire [23:0] n2l = d1, n2r = d3;
    wire [23:0] n3l = d2, n3r = I_color[95:72];

    wire [23:0] b0 = { f_sm(d0[23:16], d0[23:16], n0r[23:16]),
                       f_sm(d0[15: 8], d0[15: 8], n0r[15: 8]),
                       f_sm(d0[ 7: 0], d0[ 7: 0], n0r[ 7: 0]) };
    wire [23:0] b1 = { f_sm(n1l[23:16], d1[23:16], n1r[23:16]),
                       f_sm(n1l[15: 8], d1[15: 8], n1r[15: 8]),
                       f_sm(n1l[ 7: 0], d1[ 7: 0], n1r[ 7: 0]) };
    wire [23:0] b2 = { f_sm(n2l[23:16], d2[23:16], n2r[23:16]),
                       f_sm(n2l[15: 8], d2[15: 8], n2r[15: 8]),
                       f_sm(n2l[ 7: 0], d2[ 7: 0], n2r[ 7: 0]) };
    wire [23:0] b3 = { f_sm(n3l[23:16], d3[23:16], n3r[23:16]),
                       f_sm(n3l[15: 8], d3[15: 8], n3r[15: 8]),
                       f_sm(n3l[ 7: 0], d3[ 7: 0], n3r[ 7: 0]) };

    wire s0 = strong_d[3];
    wire s1 = strong_d[2];
    wire s2 = strong_d[1];
    wire s3 = strong_d[0];

    // 单通道量化：保留高 QUANT_BITS 位并复制填充到 8 位，保持满量程。
    // ★ 2026-10-11: 必须为**每一档**都写一条 case。原来只写了 2 和 4，
    //   QUANT_BITS=3 会掉到 default 而 default 是"原样透传" —— 等于卡通模式
    //   只剩黑边、没有海报化。加参数时一定要回来补这里。
    //   复制规则：8 位填满，高位先铺。
    //     2 -> 4x2 = 8 ✓      3 -> 3+3+2 = 8 ✓      4 -> 2x4 = 8 ✓
    function [7:0] f_quant;
        input [7:0] v;
        begin
            case (QUANT_BITS)
                2: f_quant = {v[7:6], v[7:6], v[7:6], v[7:6]};
                3: f_quant = {v[7:5], v[7:5], v[7:6]};
                4: f_quant = {v[7:4], v[7:4]};
                default: f_quant = v;
            endcase
        end
    endfunction

    function [23:0] f_pix;
        input [23:0] col;
        input        strong;
        begin
            if (strong)
                f_pix = 24'h000000;                                  // 强边 -> 黑色描边
            else
                f_pix = {f_quant(col[23:16]),
                         f_quant(col[15: 8]),
                         f_quant(col[ 7: 0])};
        end
    endfunction

    always @(*) begin
        O_cartoon = {f_pix(b0,s0), f_pix(b1,s1), f_pix(b2,s2), f_pix(b3,s3)};
    end

endmodule

module motion_detect_96 #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,
    // ★ 2026-10-12: 切片宽 16 -> 32。不是为了省资源, 是为了**腾出空间放第二个 bank**
    //   (三帧差需要 f(n)/f(n-1)/f(n-2) 三者同时可比)。片数从 57600 减半到 28800,
    //   两个 bank 的总位数正好等于原来单 bank 的位数 —— **BRAM 用量不变**。
    parameter SW         = 32,      // 切片宽(像素), 必须是 4 的倍数(一拍 4 像素)
    parameter DIFF_TH    = 12       // 切片平均亮度差超过这个值算"这里在动"
)(
    input             I_clk,
    input             I_rst_n,
    input             I_bypass,     // 非运动模式直通
    input             I_tuser,
    input             I_tvalid,
    input      [95:0] I_tdata,
    output reg        O_tuser,
    output reg        O_tvalid,
    output reg [95:0] O_tdata,
    output reg [14:0] O_mot_cnt,    // 本帧有运动的切片数 (二进制, 给框的门槛用)
    // 2026-10-12: 同一个计数的 **BCD 版** (16 位 = 4 个十进制数字, 千/百/十/个),
    // 直接给 OSD 显示 —— 这样 HDMI 域**不需要任何进制转换器**。
    output reg [15:0] O_mot_bcd,
    // 2026-10-12: 运动区域的**外接框**, 格式和 det_boxes 一样 (64 位):
    //   {cy[9:0], cx[10:0], valid, left[10:0], right[10:0], top[9:0], bottom[9:0]}
    // 用来把进阶要求(4) 的"运动区域**提示**"补齐 —— 原来只有计数, 没有区域。
    // 它和染色用同一套"上一帧"的数据, 所以两者天然同步 (都晚一帧)。
    output reg [63:0] O_mot_box
);

    localparam GRP_W   = IMG_WIDTH / 4;          // 320 组/行
    localparam SW_GRP  = SW / 4;                 // 每切片几组 (32/4 = 8)
    localparam NPERROW = IMG_WIDTH / SW;         // 每行几片 (40)
    localparam NSLICE  = NPERROW * IMG_HEIGHT;   // 总片数 (28800)

    // ---- 位置计数 (只靠递增维护, 不做除法) ---------------------------------
    reg [8:0]  x_grp;    // 0..319  4 像素组
    reg [9:0]  y_pos;    // 0..719  像素行
    reg [3:0]  sl_cyc;   // 切片内第几拍 0..SW_GRP-1  (0..7)

    // 切片地址 = y_pos * NPERROW + (x_grp / SW_GRP)
    //   40 = 32 + 8 -> y*40 = (y<<5)+(y<<3)
    //   x_grp/8 = x_grp[8:3] (0..39)
    wire [14:0] sl_addr = (y_pos << 5) + (y_pos << 3) + x_grp[8:3];

    // ---- 帧 bank: 每帧翻转 -------------------------------------------------
    // 当前帧写进 bank; 读 bank(写之前)拿到的是**上上帧** f(n-2),
    // 读 !bank 拿到的是**上一帧** f(n-1)。三帧差要的就是这三个。
    reg         bank;
    wire [15:0] addr_cur  = { bank, sl_addr};   // 本帧要写的; 写之前 = f(n-2)
    wire [15:0] addr_last = {~bank, sl_addr};   // f(n-1)

    // ---- 亮度近似 R/4 + G/2 + B/4 (最大 253, 8 位装得下, 不用除法器) -------
    function [7:0] f_luma;
        input [23:0] p;
        begin
            f_luma = {2'b0,p[23:18]} + {1'b0,p[15:9]} + {2'b0,p[7:2]};
        end
    endfunction

    // 一拍 4 个像素的亮度和 (最大 4*253 = 1012, 10 位)
    wire [9:0] cyc_sum = f_luma(I_tdata[95:72]) + f_luma(I_tdata[71:48]) +
                         f_luma(I_tdata[47:24]) + f_luma(I_tdata[23: 0]);

    // ---- 切片累加: SW_GRP 个连续拍 -> SW 个像素 ----------------------------
    reg  [12:0] sl_acc;
    wire [12:0] sl_sum = sl_acc + cyc_sum;
    wire        sl_end = (sl_cyc == 4'd7);       // SW_GRP = 8
    wire [7:0]  sl_val = sl_sum[12:5];           // 除以 32 -> 切片平均亮度

    // ---- 两帧的切片存: 两个 bank 轮流 + **分时复用一个读口** ----------------
    // ★ 为什么两个 bank: 三帧差要 f(n), f(n-1), f(n-2) 三者同时可比, 必须存两帧。
    //   切片宽 16->32 之后片数减半, 两个 bank 的总位数和原来单 bank 一样,
    //   **BRAM 用量不变**。
    // ★ 一个读口读两个地址: 切片有 8 拍, 前几拍读"上一帧"(!bank), 后几拍读
    //   "上上帧"(bank)。读在某一拍给出地址、下一拍有效, 所以:
    //     sl_cyc==2 锁 last_r  (f(n-1), 来自 cyc 1 对 !bank 的读)
    //     sl_cyc==4 锁 prev2_r (f(n-2), 来自 cyc 3 对 bank  的读)
    //   写发生在片末(sl_cyc==7), 而对同一地址的最后一次读在 cyc 3 —— 隔 4 拍,
    //   不冲突。
    // ★ 2026-10-12 正式版: 修越界。原来声明 [0:2*NSLICE-1] = [0:57599],
    //   但地址是 {bank, sl_addr} —— bank 占 bit15, sl_addr 占 bit14:0
    //   (sl_addr 最大 719*40+39 = 28799 > 16383, 所以 bit14 是用到的)。
    //   于是两个 bank 实际落在 [0,28799] 和 [32768,61567] 两段, 中间
    //   [28800,32767] 是空洞, 而 bank=1 的末尾到 61567 —— **超出 57600 的声明深度**。
    //   综合器**按声明深度分配物理 RAM 且不报错**, 超出的地址静默回绕/丢弃,
    //   所以 bank=1 帧里一大段切片读到垃圾 -> d1/d2 双双越过 DIFF_TH
    //   -> 第5档整帧冒假运动散点 (板上实测确认), 外接框坐标也被写成垃圾值,
    //   表现为画面左下角凭空多出一个框。
    //   独立佐证: gate.area 里 u_motion 的 eram 列, 未修版 = 29 块 (57600),
    //   本修法 = 32 块 (65536); 而综合器对越界**一个 warning 都不发**。
    //   SW 从 16 改成 32 时 NSLICE 减半, 但拼接地址的字段位宽没跟着改 —— 是那次引入的。
    //   修法: 声明到 16 位地址的全空间。代价 3 块 BRAM (#eram 68 -> 71, 可用 108),
    //   **零逻辑、零时序**。板上已单独验证有效 (MOTFIX.bit)。
    reg [8:0]  mot_mem [0:65535];        // {运动标志, 切片平均亮度}
    reg [8:0]  md_dout;
    reg [8:0]  last_r;                   // f(n-1) 这一片的值
    reg [8:0]  prev2_r;                  // f(n-2) 这一片的值
    reg        prev_flag;                // f(n-1) 这一片有没有动 (染色用)

    reg         md_rd_b;                 // 0 -> 读 !bank(上上帧), 1 -> 读 bank
    wire [15:0] md_raddr = md_rd_b ? addr_cur : addr_last;

    // ---- 三帧差 (2026-10-12) ----------------------------------------------
    // 两帧差 |f(n)-f(n-1)| 只能框出物体的**新旧两条边** —— 重叠区两帧一样、差分为 0,
    // 所以得到的是一个**空心的环**, 不是运动区域。这也是"看着很一般"的根源。
    // 三帧差要求**连续两段都有变化**:
    //      运动 = (|f(n)-f(n-1)| > TH) && (|f(n-1)-f(n-2)| > TH)
    // 在物体的**当前位置**上: 前后两帧都是背景 -> 两段差分都大 -> 判成运动 ✓
    // 而"物体的旧位置"和纯背景, 两段里总有一段为 0 -> 被排除 ✓
    // **得到实心的运动区域**, 计数也从"环上有多少片"变成真正的**运动面积**。
    // (代价: 物体一帧内移动必须小于它自己的宽度 —— 手速下远远够。)
    wire [7:0] d1 = (sl_val      > last_r[7:0]) ? (sl_val      - last_r[7:0])
                                                : (last_r[7:0] - sl_val     );
    wire [7:0] d2 = (last_r[7:0] > prev2_r[7:0]) ? (last_r[7:0] - prev2_r[7:0])
                                                : (prev2_r[7:0] - last_r[7:0]);
    wire       new_flag = (d1 > DIFF_TH[7:0]) && (d2 > DIFF_TH[7:0]);

    always @(posedge I_clk) begin
        if (sl_end) mot_mem[addr_cur] <= {new_flag, sl_val};
        md_dout <= mot_mem[md_raddr];
    end

    // ---- 染色: 红色半透明。只加移位, 不占乘法器。 --------------------------
    // ★ 必须先把 (R+255) 扩成 9 位再右移 —— 写成 8 位加法会溢出截断,
    //   结果变成"整体变暗"而不是"染红"。 (R+255)>>1 最大 255, 8 位正好装得下。
    function [23:0] f_tint;
        input [23:0] p;
        begin
            f_tint = { ({1'b0,p[23:16]} + 9'd255) >> 1, p[15:8] >> 1, p[7:0] >> 1 };
        end
    endfunction

    wire tint_on = (!I_bypass) && prev_flag;

    // ---- 运动区域外接框 (2026-10-12) --------------------------------------
    // 逐个运动切片累积 min/max, 帧末锁存。切片是 **16x1 的横条**, 所以:
    //   x: 这个切片覆盖 [sl_x0, sl_x0+15]   (sl_x0 = 切片号 x 16)
    //   y: 就是 y_pos (一行高)
    // 最少要有 MIN_MOT 个切片在动才画框 —— 免得一两个噪声切片也冒个框出来。
    localparam [11:0] MIN_MOT = 12'd8;      // 8 片 = 128 个像素
    wire [10:0] sl_x0 = {x_grp[8:3], 5'b00000};   // 切片号 x 32
    wire [10:0] sl_x1 = sl_x0 + 11'd31;

    reg [10:0] M_x0, M_x1;      // 本帧累积中
    reg [ 9:0] M_y0, M_y1;
    reg [10:0] W_x0, W_x1;      // 帧末锁存 (上一帧的结果, 用来画框)
    reg [ 9:0] W_y0, W_y1;
    reg        W_on;

    // ---- 运动切片数的 **BCD 计数** (2026-10-12) ---------------------------
    // ★ 为什么在这里直接数十进制, 而不是事后再转换:
    //   HDMI 域原来那个 Double Dabble 二进制->十进制转换器是我 10-10 写的, 但它的
    //   输出**从来没显示过**(CNT_DIGITS_EN=0 一直关着), 所以从没被验证 —— 板上
    //   实测转出来就是乱码(显示成方框)。与其去修一个没验证过的转换器, 不如
    //   **在计数的同时就数十进制**: 每来一个运动切片给 BCD 加 1, 逢十进位,
    //   到 9999 饱和。**这一路不可能算错, 也不需要任何转换器。**
    reg [3:0] B_d0, B_d1, B_d2, B_d3;
    wire bcd_c0  = (B_d0 == 4'd9);
    wire bcd_c1  = bcd_c0 && (B_d1 == 4'd9);
    wire bcd_c2  = bcd_c1 && (B_d2 == 4'd9);
    wire bcd_sat = bcd_c2 && (B_d3 == 4'd9);   // 已经 9999, 饱和不再增

    // ---- 主状态 ------------------------------------------------------------
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            x_grp     <= 9'd0;
            y_pos     <= 10'd0;
            sl_cyc    <= 4'd0;
            sl_acc    <= 13'd0;
            prev_flag <= 1'b0;
            last_r    <= 9'd0;
            prev2_r   <= 9'd0;
            bank      <= 1'b0;
            md_rd_b   <= 1'b0;
            O_mot_cnt <= 15'd0;
            M_x0 <= 11'h7ff; M_x1 <= 11'd0;
            M_y0 <= 10'h3ff; M_y1 <= 10'd0;
            W_x0 <= 11'h7ff; W_x1 <= 11'd0;
            W_y0 <= 10'h3ff; W_y1 <= 10'd0;
            W_on <= 1'b0;
            B_d0 <= 4'd0; B_d1 <= 4'd0; B_d2 <= 4'd0; B_d3 <= 4'd0;
            O_mot_bcd <= 16'd0;
            O_mot_box <= 64'd0;
        end else begin
            // ---- 帧首 ----
            if (I_tuser) begin
                O_mot_cnt <= 15'd0;
                sl_cyc    <= 4'd0;
                sl_acc    <= 13'd0;
                // 每帧换 bank: 当前帧写进 bank, 读 !bank 拿到上一帧
                bank      <= ~bank;
                // BCD 计数: 输出上一帧的结果, 然后清零
                O_mot_bcd <= {B_d3, B_d2, B_d1, B_d0};
                B_d0 <= 4'd0; B_d1 <= 4'd0; B_d2 <= 4'd0; B_d3 <= 4'd0;

                // ---- 锁存本帧的运动区域, 并复位累积器 ----
                // 注意顺序: 下面读的 O_mot_cnt 是**上一帧**的值(非阻塞赋值,
                // 本拍写的清零要到下一拍才生效), 正是"上一帧动得够不够多"。
                O_mot_box <= { 10'd0, 11'd0, W_on, W_x0, W_x1, W_y0, W_y1 };
                W_x0 <= M_x0; W_x1 <= M_x1; W_y0 <= M_y0; W_y1 <= M_y1;
                W_on <= (O_mot_cnt >= MIN_MOT);
                M_x0 <= 11'h7ff; M_x1 <= 11'd0;
                M_y0 <= 10'h3ff; M_y1 <= 10'd0;
            end
            // 位置计数器只在 I_tuser 与 I_tvalid 不同拍时复位 (上游 awb 的 O_tuser
            // 组合直通、O_tvalid 延两拍)。否则靠"每帧正好 320x720 拍"自然绕回。
            if (I_tuser && !I_tvalid) begin
                x_grp <= 9'd0;
                y_pos <= 10'd0;
            end

            if (I_tvalid) begin
                // 切片累加: 满 4 拍清零, 并把这一片的判决/新值写回循环 RAM
                sl_acc <= sl_end ? 13'd0 : sl_sum;
                if (sl_end && new_flag) O_mot_cnt <= O_mot_cnt + 15'd1;

                // ---- 运动区域外接框: 逐个运动切片累积 min/max ---------------
                // 顺带把 BCD 计数加 1 (逢十进位, 到 9999 饱和)
                if (sl_end && new_flag) begin
                    if (sl_x0 < M_x0) M_x0 <= sl_x0;
                    if (sl_x1 > M_x1) M_x1 <= sl_x1;
                    if (y_pos < M_y0) M_y0 <= y_pos;
                    if (y_pos > M_y1) M_y1 <= y_pos;

                    if (!bcd_sat) begin
                        B_d0 <= bcd_c0 ? 4'd0 : (B_d0 + 4'd1);
                        B_d1 <= bcd_c0 ? (bcd_c1 ? 4'd0 : (B_d1 + 4'd1)) : B_d1;
                        B_d2 <= bcd_c1 ? (bcd_c2 ? 4'd0 : (B_d2 + 4'd1)) : B_d2;
                        B_d3 <= bcd_c2 ? (B_d3 + 4'd1) : B_d3;
                    end
                end

                // 分时复用同一个读口: 切片前半段读 !bank(上上帧), 后半段读 bank
                // (md_rd_b 在第 2 拍置起, 所以第 3 拍的地址就是 bank)
                if (sl_cyc == 4'd2) md_rd_b <= 1'b1;
                if (sl_end)         md_rd_b <= 1'b0;

                // 把两帧的值分别锁下来
                if (sl_cyc == 4'd2) begin
                    last_r    <= md_dout;      // f(n-1), 来自第 1 拍对 !bank 的读
                    prev_flag <= md_dout[8];   // 染色用: 上一帧这一片动没动
                end
                if (sl_cyc == 4'd4)
                    prev2_r <= md_dout;        // f(n-2), 来自第 3 拍对 bank 的读

                sl_cyc <= sl_end ? 4'd0 : (sl_cyc + 4'd1);

                // 位置推进
                if (x_grp == GRP_W - 1) begin
                    x_grp <= 9'd0;
                    y_pos <= (y_pos == IMG_HEIGHT - 1) ? 10'd0 : (y_pos + 10'd1);
                end else
                    x_grp <= x_grp + 9'd1;
            end
        end
    end

    // ---- 输出 (比输入晚一拍, 和 O_tuser/O_tvalid 对齐) ----------------------
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tuser  <= 1'b0;
            O_tvalid <= 1'b0;
            O_tdata  <= 96'd0;
        end else begin
            O_tuser  <= I_tuser;
            O_tvalid <= I_tvalid;
            O_tdata  <= tint_on ?
                        { f_tint(I_tdata[95:72]), f_tint(I_tdata[71:48]),
                          f_tint(I_tdata[47:24]), f_tint(I_tdata[23: 0]) }
                        : I_tdata;
        end
    end

endmodule

