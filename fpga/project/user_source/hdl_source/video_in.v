

module video_in (
    input wire         I_rst_n,

    input wire         I_camera_clk,
    input wire         I_camera_frame_start,
    input wire         I_camera_valid,
    input wire[127:0]  I_camera_data,
    input wire         I_mipi_rx_error,

    input wire         I_ddr_clk,

    input wire         I_display_pause,
    input wire         I_video_out_rd_busy,
    output wire        O_video_in_wr_busy,
    output reg[1:0]    O_video_out_rp,     ///读指针
    output wire[15:0]  O_lat_fid,          ///采集到显示的延迟 (帧数) —— 2026-10-14 新增
    output wire[15:0]  O_frame_id,         ///累计采集帧号，供性能监控使用

    output reg         O_ddr_user_wr_en,
    output reg[24:0]   O_ddr_user_addr,
    output wire[127:0] O_ddr_user_wr_data,
    input wire         I_ddr_user_ready
);

    wire        S_fifo_rst;
    reg         S_camera_frame_start_extend; ///脉冲展宽，同步到ddr_clk时钟域
    reg[3:0]    S_extend_cnt;
    reg         S_camera_frame_start_extend_1d;
    reg         S_camera_frame_start_extend_2d;
    reg         S_camera_frame_start_extend_3d;
    wire        S_frame_start;
    reg[1:0]    S_video_in_wp;       ///写指针
    wire[8:0]   S_fifo_rd_num;      
    wire        S_fifo_rd_en;   
    wire        S_fifo_rd_valid;
    wire[127:0] S_fifo_rd_data; 
    reg         S_ddr_wr_valid;
    reg[9:0]    S_ddr_wr_cnt;

    localparam IMAGE_BASE_ADDR_0 = 25'd0;
    localparam IMAGE_BASE_ADDR_1 = 25'd7000000;
    localparam IMAGE_BASE_ADDR_2 = 25'd14000000;
    localparam IMAGE_BASE_ADDR_3 = 25'd21000000;


    assign S_fifo_rst = S_camera_frame_start_extend_3d;

    // 以完整DDR写突发的占用标志仲裁，避免连续视频写入长期阻塞读通道。
    assign O_video_in_wr_busy = S_ddr_wr_valid;

    w128_d512_fifo U_w128_d512_fifo(
        .rst        ( S_fifo_rst         ),   

        .clkw       ( I_camera_clk       ),     
        .we         ( I_camera_valid     ),
        .di         ( I_camera_data      ),
        .afull      (),
        .full_flag  (),
        .wrusedw    (),
 
        .clkr       ( I_ddr_clk          ),
        .re         ( S_fifo_rd_en       ), 
        .dout       ( O_ddr_user_wr_data ),  
        .rdusedw    ( S_fifo_rd_num      ),
        .valid      (), 
        .empty_flag (),
        .aempty     ()
    );


    always @(posedge I_camera_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_camera_frame_start_extend <= 1'b0;
        else
            if(I_camera_frame_start)
                S_camera_frame_start_extend <= 1'b1;
            else if(S_extend_cnt == 'd7)
                S_camera_frame_start_extend <= 1'b0;
            else
                S_camera_frame_start_extend <= S_camera_frame_start_extend;
    end

	
    always @ (posedge I_camera_clk) begin
    	if(S_camera_frame_start_extend)
        	S_extend_cnt <= S_extend_cnt + 'd1;
      	else
          	S_extend_cnt <= 'd0;
    end


    always @(posedge I_ddr_clk) begin
        S_camera_frame_start_extend_1d <= S_camera_frame_start_extend;
        S_camera_frame_start_extend_2d <= S_camera_frame_start_extend_1d;
        S_camera_frame_start_extend_3d <= S_camera_frame_start_extend_2d;
    end

    assign S_frame_start = ~S_camera_frame_start_extend_3d & S_camera_frame_start_extend_2d;

	/*
		如果前一帧图像有误少行了，那么地址回退为之前的，覆盖有问题的那帧图像
	*/
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_video_in_wp <= 'd0;
        else
            if(I_display_pause)
                S_video_in_wp <= S_video_in_wp;
            else if(S_frame_start)
                begin
                    if(I_mipi_rx_error)
                        S_video_in_wp <= S_video_in_wp;
                    else
                        S_video_in_wp <= S_video_in_wp + 'd1;
                end
            else
                S_video_in_wp <= S_video_in_wp;
    end


    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            O_video_out_rp <= 'd0;
        else
            if(I_display_pause)
                O_video_out_rp <= O_video_out_rp;
            else if(S_frame_start)
                begin
                    case(S_video_in_wp)
                        'd0: O_video_out_rp <= 'd2;
                        'd1: O_video_out_rp <= 'd3;
                        'd2: O_video_out_rp <= 'd0;
                        'd3: O_video_out_rp <= 'd1;
                    endcase
                end
            else
                O_video_out_rp <= O_video_out_rp;
    end

    /*
        fifo的深度是512，实际的深度是510，因此需要注意每次读出的长度避免为256，否则连续两次读写会引起fifo读空，丢失数据
    */
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_ddr_wr_valid <= 1'b0;
        else
            if(S_ddr_wr_valid && I_ddr_user_ready && S_ddr_wr_cnt == 'd239)
                S_ddr_wr_valid <= 1'b0;
            else if(S_fifo_rd_num >= 'd240 && (!I_video_out_rd_busy) && (!S_fifo_rst))
                S_ddr_wr_valid <= 1'b1;
            else
                S_ddr_wr_valid <= S_ddr_wr_valid;
    end

    always @(posedge I_ddr_clk) begin
        if(S_ddr_wr_valid)
            begin
                if(I_ddr_user_ready)
                    S_ddr_wr_cnt <= S_ddr_wr_cnt + 'd1;
                else
                    S_ddr_wr_cnt <= S_ddr_wr_cnt;
            end
        else
            S_ddr_wr_cnt <= 'd0;
    end

    assign S_fifo_rd_en = S_ddr_wr_valid & I_ddr_user_ready;

    always @(posedge I_ddr_clk) begin
        O_ddr_user_wr_en <= S_fifo_rd_en;
    end

	/*
		如果前一帧图像有误少行了，那么地址回退为之前的，覆盖有问题的那帧图像
	*/
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            O_ddr_user_addr <= 1'b0;
        else
            if(S_frame_start && (!I_mipi_rx_error))
                begin
                    case(S_video_in_wp)
                        'd0: O_ddr_user_addr <= IMAGE_BASE_ADDR_0;
                        'd1: O_ddr_user_addr <= IMAGE_BASE_ADDR_1;
                        'd2: O_ddr_user_addr <= IMAGE_BASE_ADDR_2;
                        'd3: O_ddr_user_addr <= IMAGE_BASE_ADDR_3;
                    endcase
                end
			else if(S_frame_start && I_mipi_rx_error)
				begin
                	case(S_video_in_wp)
                        'd0: O_ddr_user_addr <= IMAGE_BASE_ADDR_3;
                        'd1: O_ddr_user_addr <= IMAGE_BASE_ADDR_0;
                        'd2: O_ddr_user_addr <= IMAGE_BASE_ADDR_1;
                        'd3: O_ddr_user_addr <= IMAGE_BASE_ADDR_2;
                    endcase
                end
            else if(O_ddr_user_wr_en)
                O_ddr_user_addr <= O_ddr_user_addr + 'd8;
            else    
                O_ddr_user_addr <= O_ddr_user_addr;
    end

    
    // ========================================================================
    // 采集→显示的延迟测量 (2026-10-14) —— 进阶要求 2.5(3)「处理延迟可视化」
    //
    // 思路: **给帧缓存记一份"这里装的是第几帧"的账**。
    //   写入时把当前帧号记进该缓冲; 读出时把帧号取回来; 两者相减就是延迟。
    //
    // ★ 关键在于这是**测量**而不是**假设**: 帧号真的穿过 DDR 缓冲表走了一圈。
    //   哪天真去改缓冲策略(比如把 rp 从 wp+2 改成 wp+3), 这个数会跟着变成 3,
    //   不需要回来改任何常数。
    //
    // 帧序核对 (第 j 帧, j 从 0 起; 注意 wp 和 rp 用的都是**自增前**的 wp):
    //   第 j 帧開始 -> 地址 = BASE_{(j)%4}  , 即写进缓冲 j%4        -> S_buf_fid[j%4] = j
    //               -> rp = (j%4)+2 = (j+2)%4
    //               而缓冲 (j+2)%4 里躺的是第 (j+2)-4 = j-2 帧
    //   => 正在采集 j、正在显示 j-2  => **延迟 = 2 帧 ≈ 33.3ms**
    //   上板若显示的不是 2, 以**板上为准** —— 那说明上面这段推导有偏差, 数字是真的。
    // ========================================================================
    reg [15:0] S_cap_fid;               // 正在采集的是第几帧
    reg [15:0] S_buf_fid [0:3];         // 每个缓冲里装的是第几帧

    integer bi;
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_cap_fid <= 16'd0;
            for (bi = 0; bi < 4; bi = bi + 1) S_buf_fid[bi] <= 16'd0;
        end else if(S_frame_start && (!I_display_pause) && (!I_mipi_rx_error)) begin
            // 新的一帧开始: 它的编号 = S_cap_fid + 1
            //
            // ★ 2026-10-14 修 off-by-one: 原来这里写的是
            //       S_buf_fid[S_video_in_wp] <= S_cap_fid;   S_cap_fid <= S_cap_fid + 1;
            //   存进去的是**自增前**的值, 而计数器当拍就自增了 —— 于是帧首之后
            //   S_cap_fid 记的是"下一帧", 正在采集的其实是它减 1, 延迟**天生多算 1**
            //   (板上显示 3F/50MS, 而缓冲里那一帧其实只有 2 帧)。
            //   现在存自增后的值, S_cap_fid 就名副其实 = **正在采集的是第几帧**。
            //
            // 注意这里必须和上面 O_ddr_user_addr 用**同一个** S_video_in_wp (自增前的)
            // —— 因为那一帧的数据正是写进这个缓冲的。
            S_buf_fid[S_video_in_wp] <= S_cap_fid + 16'd1;
            S_cap_fid                <= S_cap_fid + 16'd1;
        end
    end

    // 延迟 = 正在采集的帧号 - 正在显示的那个缓冲里记的帧号
    // (O_video_out_rp 只在帧首变, 整帧稳定; 减法在 ddr 域做完再过 CDC)
    assign O_lat_fid = S_cap_fid - S_buf_fid[O_video_out_rp];
    assign O_frame_id = S_cap_fid;

endmodule
