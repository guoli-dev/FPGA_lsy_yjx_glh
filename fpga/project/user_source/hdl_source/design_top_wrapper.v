

module design_top_wrapper (
    input wire        I_sys_clk,

    output wire       O_cam_scl,
    inout  wire       IO_cam_sda,
    output wire       O_cam_24m,
    output wire       O_cam_rst,
      
    inout wire [1:0]  I_button,

    output wire       O_uart_tx,
    output wire       O_buzzer,
    output wire       O_tmds_ch0_p,
    output wire       O_tmds_ch1_p,
    output wire       O_tmds_ch2_p,
    output wire       O_tmds_clk_p,

    output wire       O_phy_rst,
    input  wire [3:0] I_a_rgmii_rxd,
    input  wire       I_a_rgmii_rx_ctl,
    input  wire       I_a_rgmii_rxc,
    output wire [3:0] O_a_rgmii_txd,
    output wire       O_a_rgmii_tx_ctl,
    output wire       O_a_rgmii_txc,

    inout wire        IO_rx_clk_pad_n,
    inout wire        IO_rx_clk_pad_p, 
    inout wire[3:0]   IO_rx_data_pad_n,
    inout wire[3:0]   IO_rx_data_pad_p,

    output wire[12:0] ddr_addr,
    output wire[ 1:0] ddr_ba,
    output wire[ 0:0] ddr_cke,
    output wire[ 0:0] ddr_odt,
    output wire[ 0:0] ddr_cs_n,
    output wire       ddr_ras_n,
    output wire       ddr_cas_n,
    output wire       ddr_we_n,
    output wire[ 0:0] ddr_ck_p,
    output wire[ 0:0] ddr_ck_n,
    inout wire[1:0]   ddr_dm,
    inout wire[15:0]  ddr_dq,
    inout wire[1:0]   ddr_dqs_p,
    inout wire[1:0]   ddr_dqs_n   
);


    wire        	S_100m_clk;
    wire        	S_24m_clk;
    wire        	S_aux_50m_clk;
	wire        	S_10m_clk;
		
	wire        	S_pll_lock;
    wire        	S_rst_n;
	
	wire [15:0] 	S_ae;
    wire [15:0] 	S_ag;
    wire 			S_cam_cfg_done;
    wire 			S_ae_cfg_done;
    wire 			S_ae_req; 
	
	wire        	S_csi_rx_clk;  
    wire        	S_hs_rx_valid;  
    wire[15:0]  	S_hs_rx_data;   
	wire[1:0]   	S_lane_error;
	
	wire        	S_csi_frame_start;       
	wire        	S_csi_frame_end;         
	wire        	S_csi_valid;             
	wire[31:0]  	S_csi_data;  
		
	wire        	S_raw10_frame_start; 
	wire        	S_raw10_frame_end;   
	wire        	S_raw10_valid;       
	wire [39:0] 	S_raw10_data;
		
	wire 			S_axis_tlast;  
	wire 			S_axis_tuser;  
	wire [39:0]		S_axis_tdata;  
	wire 			S_axis_tvalid; 
	
	wire [39:0]		S_raw_tdata ;
	wire			S_raw_tlast ;
	wire 			S_raw_tvalid;
	wire 			S_raw_tuser ;
	
	wire			S_ISP_O_tready;
	wire [127:0]	S_ISP_O_tdata ;
	wire 			S_ISP_O_tlast ;
	wire 			S_ISP_O_tuser ;
	wire 			S_ISP_O_tvalid; 
	

    wire        S_ddr_clk;
    wire        S_hdmi_pixel_clk;
    wire        S_hdmi_serial_clk;
    wire        S_hdmi_rst_n;
    wire        S_video_out_rst_n;


    wire        S_vi_128b_frame_start;
    wire        S_vi_128b_valid;      
    wire[127:0] S_vi_128b_data;    
    
    wire        S_video_out_rd_busy;
    wire        S_video_in_wr_busy; 
    wire[1:0]   S_video_out_rp;     

    wire        S_ddr_user_wr_en;       
    wire        S_ddr_user_rd_en;       
    wire[24:0]  S_ddr_user_addr;        
    wire[127:0] S_ddr_user_wr_data;     
    wire        S_ddr_user_ready;       
    wire        S_ddr_user_rd_valid;    
    wire[127:0] S_ddr_user_rd_data;     

    wire        S_vi_ddr_wr_en;   
    wire[24:0]  S_vi_ddr_wr_addr; 
    wire[127:0] S_vi_ddr_wr_data;
    wire        S_vi_ddr_wr_ready;

    wire        S_vo_ddr_rd_en;   
    wire[24:0]  S_vo_ddr_rd_addr; 
    wire        S_vo_ddr_rd_ready;
    wire        S_vo_dbg_fifo_rst;
    wire        S_vo_dbg_ddr_rd_valid;
    wire        S_vo_dbg_fifo_rd_en;
    wire        S_vo_dbg_fifo_empty;

    wire        S_init_calib_complete; 
    wire[24:0]  S_mc_app_addr;          
    wire[2:0]   S_mc_app_cmd;           
    wire        S_mc_app_en;            
    wire[127:0] S_mc_app_wdf_data;      
    wire        S_mc_app_wdf_end;       
    wire[15:0]  S_mc_app_wdf_mask;      
    wire        S_mc_app_wdf_wren;      
    wire[127:0] S_mc_app_rd_data;       
    wire        S_mc_app_rd_data_end;   
    wire        S_mc_app_rd_data_valid; 
    wire        S_mc_app_rdy;           
    wire        S_mc_app_wdf_rdy;       
    wire        S_mc_dbg_fifo_afull;
    wire        S_mc_dbg_app_rdy;
    wire        S_mc_dbg_wdf_rdy;
    wire        S_mc_dbg_cmd_pop;

    wire        S_hdmi_vsync;
    wire        S_hdmi_hsync;
    wire        S_hdmi_de;
    wire        S_hdmi_user;
    wire        S_hdmi_last;
    wire        S_video_out_vsync;
    wire        S_hdmi_window_rd_en;
    wire        S_hdmi_out_vsync;
    wire        S_hdmi_out_hsync;
    wire        S_hdmi_out_de;
    wire[23:0]  S_hdmi_out_data;

    wire[23:0]  S_video_rd_data;
    reg         S_dbg_raw_seen;
    reg         S_dbg_isp_seen;
    reg         S_dbg_ddr_wr_seen;
    reg         S_dbg_ddr_rd_seen;
    reg         S_dbg_cam_cfg_seen;
    reg         S_dbg_hs_seen;
    reg         S_dbg_csi_seen;
    reg         S_dbg_raw10_seen;
    reg         S_dbg_isp_fs_seen;
    reg         S_dbg_isp_valid_seen;
    reg         S_dbg_ddr_req_seen;
    reg         S_dbg_ddr_ready_seen;
    reg [1:0]   S_dbg_raw_seen_sync;
    reg [1:0]   S_dbg_isp_seen_sync;
    reg [1:0]   S_dbg_ddr_wr_seen_sync;
    reg [1:0]   S_dbg_ddr_rd_seen_sync;
    reg [1:0]   S_dbg_cam_cfg_seen_sync;
    reg [1:0]   S_dbg_hs_seen_sync;
    reg [1:0]   S_dbg_csi_seen_sync;
    reg [1:0]   S_dbg_raw10_seen_sync;
    reg [1:0]   S_dbg_isp_fs_seen_sync;
    reg [1:0]   S_dbg_isp_valid_seen_sync;
    reg [1:0]   S_dbg_ddr_req_seen_sync;
    reg [1:0]   S_dbg_ddr_ready_seen_sync;
    reg         S_dbg_video_nonzero_seen;
    reg         S_dbg_rd_req_seen;
    reg         S_dbg_rd_valid_seen;
    reg         S_dbg_rd_nonzero_seen;
    reg [1:0]   S_dbg_rd_req_seen_sync;
    reg [1:0]   S_dbg_rd_valid_seen_sync;
    reg [1:0]   S_dbg_rd_nonzero_seen_sync;
    reg         S_dbg_mc_init_seen;
    reg         S_dbg_mc_app_rdy_seen;
    reg         S_dbg_mc_wdf_rdy_seen;
    reg         S_dbg_mc_cmd_pop_seen;
    reg [1:0]   S_dbg_mc_init_seen_sync;
    reg [1:0]   S_dbg_mc_app_rdy_seen_sync;
    reg [1:0]   S_dbg_mc_wdf_rdy_seen_sync;
    reg [1:0]   S_dbg_mc_cmd_pop_seen_sync;
    wire[3:0]   S_hdmi_debug_status;
    wire        S_lane_error_any;


    assign S_video_out_vsync = ~S_hdmi_vsync;
	
	
    assign S_rst_n 		= S_pll_lock;
    assign S_hdmi_rst_n = S_pll_lock;

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_raw_seen <= 1'b0;
        else if(S_raw10_frame_start | S_axis_tvalid)
            S_dbg_raw_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_isp_seen <= 1'b0;
        else if(S_ISP_O_tuser | S_ISP_O_tvalid)
            S_dbg_isp_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_wr_seen <= 1'b0;
        else if(S_vi_ddr_wr_en)
            S_dbg_ddr_wr_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_rd_seen <= 1'b0;
        else if(S_ddr_user_rd_valid)
            S_dbg_ddr_rd_seen <= 1'b1;
    end

    always @(posedge S_24m_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_cam_cfg_seen <= 1'b0;
        else if(S_cam_cfg_done)
            S_dbg_cam_cfg_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_hs_seen <= 1'b0;
        else if(S_hs_rx_valid)
            S_dbg_hs_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_csi_seen <= 1'b0;
        else if(S_csi_frame_start | S_csi_valid)
            S_dbg_csi_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_raw10_seen <= 1'b0;
        else if(S_raw10_frame_start | S_raw10_valid)
            S_dbg_raw10_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_isp_fs_seen <= 1'b0;
        else if(S_ISP_O_tuser)
            S_dbg_isp_fs_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_isp_valid_seen <= 1'b0;
        else if(S_ISP_O_tvalid)
            S_dbg_isp_valid_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_req_seen <= 1'b0;
        else if(S_vi_ddr_wr_en)
            S_dbg_ddr_req_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_ready_seen <= 1'b0;
        else if(S_ddr_user_ready)
            S_dbg_ddr_ready_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_req_seen <= 1'b0;
        else if(S_video_out_vsync)
            S_dbg_rd_req_seen <= 1'b0;
        else if(S_vo_ddr_rd_en)
            S_dbg_rd_req_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_valid_seen <= 1'b0;
        else if(S_video_out_vsync)
            S_dbg_rd_valid_seen <= 1'b0;
        else if(S_ddr_user_rd_valid)
            S_dbg_rd_valid_seen <= 1'b1;
    end

    always @(posedge S_hdmi_pixel_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_nonzero_seen <= 1'b0;
        else if(S_video_out_vsync)
            S_dbg_rd_nonzero_seen <= 1'b0;
        else if(S_hdmi_window_rd_en && (S_video_rd_data != 24'd0))
            S_dbg_rd_nonzero_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_init_seen <= 1'b0;
        else if(S_init_calib_complete)
            S_dbg_mc_init_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_app_rdy_seen <= 1'b0;
        else if(S_mc_dbg_app_rdy)
            S_dbg_mc_app_rdy_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_wdf_rdy_seen <= 1'b0;
        else if(S_mc_dbg_wdf_rdy)
            S_dbg_mc_wdf_rdy_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_cmd_pop_seen <= 1'b0;
        else if(S_mc_dbg_cmd_pop)
            S_dbg_mc_cmd_pop_seen <= 1'b1;
    end

    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if(!S_hdmi_rst_n) begin
            S_dbg_cam_cfg_seen_sync <= 2'b00;
            S_dbg_hs_seen_sync      <= 2'b00;
            S_dbg_csi_seen_sync     <= 2'b00;
            S_dbg_raw10_seen_sync   <= 2'b00;
            S_dbg_raw_seen_sync    <= 2'b00;
            S_dbg_isp_seen_sync    <= 2'b00;
            S_dbg_ddr_wr_seen_sync <= 2'b00;
            S_dbg_ddr_rd_seen_sync <= 2'b00;
            S_dbg_isp_fs_seen_sync  <= 2'b00;
            S_dbg_isp_valid_seen_sync <= 2'b00;
            S_dbg_ddr_req_seen_sync <= 2'b00;
            S_dbg_ddr_ready_seen_sync <= 2'b00;
            S_dbg_video_nonzero_seen <= 1'b0;
            S_dbg_rd_req_seen_sync <= 2'b00;
            S_dbg_rd_valid_seen_sync <= 2'b00;
            S_dbg_rd_nonzero_seen_sync <= 2'b00;
            S_dbg_mc_init_seen_sync <= 2'b00;
            S_dbg_mc_app_rdy_seen_sync <= 2'b00;
            S_dbg_mc_wdf_rdy_seen_sync <= 2'b00;
            S_dbg_mc_cmd_pop_seen_sync <= 2'b00;
        end
        else begin
            S_dbg_cam_cfg_seen_sync <= {S_dbg_cam_cfg_seen_sync[0], S_dbg_cam_cfg_seen};
            S_dbg_hs_seen_sync      <= {S_dbg_hs_seen_sync[0],      S_dbg_hs_seen};
            S_dbg_csi_seen_sync     <= {S_dbg_csi_seen_sync[0],     S_dbg_csi_seen};
            S_dbg_raw10_seen_sync   <= {S_dbg_raw10_seen_sync[0],   S_dbg_raw10_seen};
            S_dbg_raw_seen_sync    <= {S_dbg_raw_seen_sync[0],    S_dbg_raw_seen};
            S_dbg_isp_seen_sync    <= {S_dbg_isp_seen_sync[0],    S_dbg_isp_seen};
            S_dbg_ddr_wr_seen_sync <= {S_dbg_ddr_wr_seen_sync[0], S_dbg_ddr_wr_seen};
            S_dbg_ddr_rd_seen_sync <= {S_dbg_ddr_rd_seen_sync[0], S_dbg_ddr_rd_seen};
            S_dbg_isp_fs_seen_sync  <= {S_dbg_isp_fs_seen_sync[0],  S_dbg_isp_fs_seen};
            S_dbg_isp_valid_seen_sync <= {S_dbg_isp_valid_seen_sync[0], S_dbg_isp_valid_seen};
            S_dbg_ddr_req_seen_sync <= {S_dbg_ddr_req_seen_sync[0], S_dbg_ddr_req_seen};
            S_dbg_ddr_ready_seen_sync <= {S_dbg_ddr_ready_seen_sync[0], S_dbg_ddr_ready_seen};
            S_dbg_rd_req_seen_sync <= {S_dbg_rd_req_seen_sync[0], S_dbg_rd_req_seen};
            S_dbg_rd_valid_seen_sync <= {S_dbg_rd_valid_seen_sync[0], S_dbg_rd_valid_seen};
            S_dbg_rd_nonzero_seen_sync <= {S_dbg_rd_nonzero_seen_sync[0], S_dbg_rd_nonzero_seen};
            S_dbg_mc_init_seen_sync <= {S_dbg_mc_init_seen_sync[0], S_dbg_mc_init_seen};
            S_dbg_mc_app_rdy_seen_sync <= {S_dbg_mc_app_rdy_seen_sync[0], S_dbg_mc_app_rdy_seen};
            S_dbg_mc_wdf_rdy_seen_sync <= {S_dbg_mc_wdf_rdy_seen_sync[0], S_dbg_mc_wdf_rdy_seen};
            S_dbg_mc_cmd_pop_seen_sync <= {S_dbg_mc_cmd_pop_seen_sync[0], S_dbg_mc_cmd_pop_seen};
            if(S_hdmi_window_rd_en && (S_video_rd_data != 24'd0))
                S_dbg_video_nonzero_seen <= 1'b1;
        end
    end

    assign S_lane_error_any = |S_lane_error;

    assign S_vo_dbg_fifo_rst = 1'b0;
    assign S_vo_dbg_ddr_rd_valid = 1'b0;
    assign S_vo_dbg_fifo_rd_en = 1'b0;
    assign S_vo_dbg_fifo_empty = 1'b0;
    assign S_mc_dbg_fifo_afull = 1'b0;
    assign S_mc_dbg_app_rdy = 1'b0;
    assign S_mc_dbg_wdf_rdy = 1'b0;
    assign S_mc_dbg_cmd_pop = 1'b0;

    assign S_hdmi_debug_status = {
        (|S_ddr_user_rd_data),
        S_ddr_user_rd_valid,
        S_vo_ddr_rd_en,
        S_vi_ddr_wr_en
    };
	
	assign O_cam_rst 	= 1'b1;
    assign O_cam_24m 	= S_24m_clk;
	
	
	
	
    PLL u_PLL(
        .refclk      ( I_sys_clk         ),
        .reset    	 ( 1'b0              ),
        
        .clk0_out    ( S_100m_clk        ),
        .clk1_out    ( S_24m_clk         ),

        .clk4_out    ( S_hdmi_pixel_clk  ),
        .clk5_out    ( S_hdmi_serial_clk ),

        .lock        ( S_pll_lock        )

    );


	

  
  // Frame statistics cross from the ISP clock to the 24 MHz sensor-control
  // clock. The data flags settle through two stages before the toggle event.
  wire S_isp_ae_too_bright;
  wire S_isp_ae_too_dark;
  wire S_isp_ae_frame_toggle;

  reg [1:0] S_ae_bright_24m;
  reg [1:0] S_ae_dark_24m;
  reg [2:0] S_ae_tgl_24m;
  always @(posedge S_24m_clk or negedge S_rst_n) begin
      if (!S_rst_n) begin
          S_ae_bright_24m <= 2'd0;
          S_ae_dark_24m   <= 2'd0;
          S_ae_tgl_24m    <= 3'd0;
      end else begin
          S_ae_bright_24m <= {S_ae_bright_24m[0], S_isp_ae_too_bright};
          S_ae_dark_24m   <= {S_ae_dark_24m[0], S_isp_ae_too_dark};
          S_ae_tgl_24m    <= {S_ae_tgl_24m[1:0], S_isp_ae_frame_toggle};
      end
  end

  wire S_ae_frame_event_24m = S_ae_tgl_24m[2] ^ S_ae_tgl_24m[1];
  wire S_ae_too_bright_24m  = S_ae_bright_24m[1];
  wire S_ae_too_dark_24m    = S_ae_dark_24m[1];

  ae_set u_ae_set (
      .I_clk(S_24m_clk),
      .I_rst(~S_rst_n),
      // 2026-10-09: 按键全部改作 Logo 开关, ae_set 彻底脱离按键。
      // 理由: 增益已定死在满量程 143, ae_set 那两个"加"分支从初值起就够不着
      // (r_ae_set<2246 / r_ag_set<143), 只剩"减"能走 —— 按下去只会让画面变暗,
      // 是纯副作用。四个键全填 1 = 全释放。
      .I_btn(4'b1111),
      .I_cam_cfg_done(S_cam_cfg_done),
      .I_ae_cfg_done(S_ae_cfg_done),
      .I_frame_event(S_ae_frame_event_24m),
      .I_too_bright(S_ae_too_bright_24m),
      .I_too_dark(S_ae_too_dark_24m),
      .O_ae_req(S_ae_req),
      .O_ae(S_ae),
      .O_ag(S_ag)
  );
  
    uicfgcs500_720p #(
      .CLK_DIV(24000000 / 100000 - 1)
  ) u_uicfgcs500 (
      .I_clk(S_24m_clk),  //系统时钟输入
      .I_rst_n(S_rst_n),  //系统复位输入
      .I_ae_req(S_ae_req),
      .I_ae(S_ae),
      .I_ag(S_ag),
      .O_cam_scl(O_cam_scl),  //I2C总线，SCL时钟
      .IO_cam_sda(IO_cam_sda),  //I2C总线，SDA数据
      .O_cfg_done(S_cam_cfg_done),  //摄像头寄存器初始化完成
      .O_ae_cfg_done(S_ae_cfg_done)  //AE配置完成
  );
	
    mipi_dphy_rx_ph1p_mipiio_wrapper#(
        .DPHY_RX_LOCATION      ( "DPHY0" ),
        .HS_EQUALIZER          ( "0dB"   ),//"0dB","1.5dB","3dB","4.5dB","6dB","7.5dB","9dB","10.5dB"
        .HS_VGA_GAIN           ( "8dB" ),//"-3dB","-1.5dB","0dB","1.5dB","3dB","4.5dB","6dB","7.5dB"
        .LANE_NUM              ( 2       ),
        .BYTE_NUM              ( 1       )
    )u_mipi_dphy_rx_ph1p_mipiio_wrapper(
        .I_lp_clk              ( S_100m_clk       ),
        .I_rst                 ( ~S_rst_n         ),

        .I_clk_lane_in_delay   ( 6'd0             ),
        .I_data_lane0_in_delay ( 6'd0             ),
        .I_data_lane1_in_delay ( 6'd0             ),
        .I_data_lane2_in_delay ( 6'd0             ),
        .I_data_lane3_in_delay ( 6'd0             ),

        .I_lane_invert         ( 4'b0000          ),
     
        .O_hs_rx_clk           ( S_csi_rx_clk     ),
        .O_hs_rx_valid         ( S_hs_rx_valid    ),
        .O_hs_rx_data          ( S_hs_rx_data     ),
      
        .O_lp_rx_lane0_p       (  ),
        .O_lp_rx_lane0_n       (  ),
      
        .I_lp_tx_en            ( 1'b0             ),
        .I_lp_tx_lane0_p       ( 1'b1             ),
        .I_lp_tx_lane0_n       ( 1'b1             ),
      
        .O_lane_match_error    (                  ),
        .O_lane_error          ( S_lane_error     ),
      
        .IO_rx_clk_pad_n       ( IO_rx_clk_pad_n  ),
        .IO_rx_clk_pad_p       ( IO_rx_clk_pad_p  ),
        .IO_rx_data_pad_n      ( IO_rx_data_pad_n ),
        .IO_rx_data_pad_p      ( IO_rx_data_pad_p )
    );
	
	
 //  cwc cwc_inst
 //(
 //    .probe0(S_hs_rx_valid),
 //    .probe1(S_hs_rx_data),
 //    .probe2(S_lane_error),
 //    .clk(S_csi_rx_clk)
 //);

 //csi 解码为RAW数据
csi_unpacket_2lane u_csi_unpacket(
.I_clk                 ( S_csi_rx_clk       ),
.I_rst_n               ( S_rst_n        	),
.I_hs_valid            ( S_hs_rx_valid     ),
.I_hs_data             ( S_hs_rx_data      ),

.O_csi_frame_start     ( S_csi_frame_start ),
.O_csi_frame_end       ( S_csi_frame_end   ),
.O_csi_valid           ( S_csi_valid       ),
.O_csi_data            ( S_csi_data        )
);


//解码为RAW8
raw10_unpacket_2lane u_raw10_unpacket (
.I_clk  (S_csi_rx_clk),
.I_rst_n(S_rst_n),

.I_csi_frame_start(S_csi_frame_start),
.I_csi_frame_end  (S_csi_frame_end),
.I_csi_valid      (S_csi_valid),
.I_csi_data       (S_csi_data),

.O_raw10_frame_start(S_raw10_frame_start),
.O_raw10_frame_end  (S_raw10_frame_end),
.O_raw10_valid      (S_raw10_valid),
.O_raw10_data       (S_raw10_data)
  );


//将数据转为stream流
uial2axis #(
.IMG_WIDTH(1280),
.IMG_HEIGHT(720),
.INPUT_DATA_WIDTH(40)
) 
u_uial2axis (
.I_native_clk(S_csi_rx_clk),
.I_rst_n     (S_rst_n),
.I_data      (S_raw10_data       ),
.I_data_valid(S_raw10_valid      ),
.I_data_start(S_raw10_frame_start),
.I_data_end  (S_raw10_frame_end  ),
.axis_tvalid (S_axis_tvalid),
.axis_tdata  (S_axis_tdata ),
.axis_tuser  (S_axis_tuser ),
.axis_tlast  (S_axis_tlast )
);
	

// 原厂HD模式直接输出1280x720 RAW10，不再进行FPGA固定窗口裁剪。
assign S_raw_tdata  = S_axis_tdata;
assign S_raw_tlast  = S_axis_tlast;
assign S_raw_tvalid = S_axis_tvalid;
assign S_raw_tuser  = S_axis_tuser;


//cwc1 cwc1_Inst
//  (
//      .probe0(S_axis_tuser),
//      .probe1(S_axis_tvalid),
//      .probe2(S_axis_tlast),
//      .probe3(S_axis_tdata),
//      .probe4(S_ISP_O_tuser),
//      .probe5(S_ISP_O_tvalid),
//      .probe6(S_ISP_O_tlast),
//      .probe7(S_ISP_O_tdata),
//      .probe8 (S_raw_tdata ),
//      .probe9 (S_raw_tlast ),
//      .probe10(S_raw_tvalid),
//      .probe11(S_raw_tuser ),
//      .clk(S_csi_rx_clk)
//  );


// ---- 显示模式按键 (2026-10-10) --------------------------------------------
// I_button[0] = N2 = 原理图的**按键0** (GPIOA5, 交叉验证过) —— 每按一次循环切一个模式:
//     0=原图  1=边缘  2=分割  3=跟踪
// 用 2 位寄存器, +1 自然回绕 (3->0), 不需要额外的比较。
// 按键消抖用 .al 里已有的 key_remove_shakes: 下降沿触发, 按住约 100000 拍
// (@60MHz 约 1.7ms) 后出一个单拍高脉冲 —— 正常按键都满足。
// 放在 CSI(ISP) 时钟域, 与 isp_top 同域, 不需要跨时钟同步。
// isp_top 内部在**帧边界**采样这个值, 所以按键的抖动不会造成半帧撕裂。
wire       S_mode_key_trig;
// ★ 2026-10-12: 2 位 -> 3 位, 为了加第 5 个模式 (MOTION 运动检测)。
//   ⚠️ 3 位计数器会在 **8** 回绕而不是 4 —— 所以加法必须显式钳回 0。
reg  [2:0] S_display_mode;

key_remove_shakes u_mode_key (
    .I_clk         ( S_csi_rx_clk    ),
    .I_rst_n       ( S_rst_n         ),
    .I_key_in      ( I_button[0]     ),
    .O_key_trig_out( S_mode_key_trig )
);

always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
    if(!S_rst_n)
        S_display_mode <= 3'd0;                 // 上电 = 原图模式
    else if(S_eth_mode_set)
        S_display_mode <= S_eth_mode;           // 上位机命令优先
    else if(S_mode_key_trig)
        // 0->1->2->3->4->0。3 位寄存器本身在 8 回绕, 所以到 4 要手动钳回 0。
        S_display_mode <= (S_display_mode == 3'd7) ? 3'd0 : (S_display_mode + 3'd1);
end

// ---- 模式值跨时钟域到 HDMI (2026-10-10) -----------------------------------
// 模式在 CSI(ISP) 域产生(按键驱动), 但把它显示到画面上的 OSD 在 HDMI 域。
// 只有几位、且只在按键时变, 两级同步就够 —— 最坏情况是切换那一瞬间 OSD 上
// 显示一个中间值, 而按键是人工操作(几十毫秒一次), 根本看不出来。
reg [2:0] S_mode_hdmi_meta, S_mode_hdmi_sync;
reg [15:0] S_ae_hdmi_meta, S_ae_hdmi_sync;
reg [7:0]  S_ag_hdmi_meta, S_ag_hdmi_sync;
always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
    if(!S_hdmi_rst_n) begin
        S_mode_hdmi_meta <= 3'd0;
        S_mode_hdmi_sync <= 3'd0;
        S_ae_hdmi_meta <= 16'd0;
        S_ae_hdmi_sync <= 16'd0;
        S_ag_hdmi_meta <= 8'd0;
        S_ag_hdmi_sync <= 8'd0;
    end else begin
        S_mode_hdmi_meta <= S_display_mode;
        S_mode_hdmi_sync <= S_mode_hdmi_meta;
        S_ae_hdmi_meta <= S_ae;
        S_ae_hdmi_sync <= S_ae_hdmi_meta;
        S_ag_hdmi_meta <= S_ag[7:0];
        S_ag_hdmi_sync <= S_ag_hdmi_meta;
    end
end

// ---- 以太网上位机 (2026-10-22) ----------------------------------------------
// eth_host: UDP 收上位机命令(切算法), 周期性上报状态(模式/帧率/链路)。
// 命令在 clk_125 域产生(O_mode_toggle/O_mode_val), 跨到 CSI 域写 S_display_mode。
// toggle 3 级同步(边沿检测), 值 2 级同步 —— 边沿到时值已稳定一周期。
wire        S_eth_mode_toggle;
wire [2:0]  S_eth_mode_val;
wire [15:0] S_frame_id;
wire [15:0] S_lat_fid;
wire [14:0] S_mot_cnt_csi;
wire [71:0] S_color_telemetry;
wire [63:0] S_mot_box_csi;

eth_host u_eth_host(
    .I_sys_clk       ( I_sys_clk        ),
    .I_rgmii_rxd     ( I_a_rgmii_rxd    ),
    .I_rgmii_rx_ctl  ( I_a_rgmii_rx_ctl ),
    .I_rgmii_rxc     ( I_a_rgmii_rxc    ),
    .O_rgmii_txd     ( O_a_rgmii_txd    ),
    .O_rgmii_tx_ctl  ( O_a_rgmii_tx_ctl ),
    .O_rgmii_txc     ( O_a_rgmii_txc    ),
    .O_phy_rst       ( O_phy_rst        ),
    .I_mode          ( S_display_mode   ),
    .I_frame_id      ( S_frame_id       ),
    .I_latency_frames( S_lat_fid        ),
    .I_motion_count  ( S_mot_cnt_csi    ),
    .I_color_data    ( S_color_telemetry),
    .I_mot_box       ( S_mot_box_csi    ),
    .O_mode_toggle   ( S_eth_mode_toggle),
    .O_mode_val      ( S_eth_mode_val   )
);

reg        S_eth_tgl1, S_eth_tgl2, S_eth_tgl3;
reg [2:0]  S_eth_val1, S_eth_val2;
always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
    if(!S_rst_n) begin
        S_eth_tgl1 <= 1'b0; S_eth_tgl2 <= 1'b0; S_eth_tgl3 <= 1'b0;
        S_eth_val1 <= 3'd0; S_eth_val2 <= 3'd0;
    end else begin
        S_eth_tgl1 <= S_eth_mode_toggle;
        S_eth_tgl2 <= S_eth_tgl1;
        S_eth_tgl3 <= S_eth_tgl2;
        S_eth_val1 <= S_eth_mode_val;
        S_eth_val2 <= S_eth_val1;
    end
end
wire        S_eth_mode_set = (S_eth_tgl3 != S_eth_tgl2);
wire [2:0]  S_eth_mode     = S_eth_val2;

// ---- capture-to-display latency CDC (2026-10-14) ---------------------------
// video_in counts frames in the ddr clock domain; the OSD that shows it lives
// in the HDMI domain. Frame-rate quantity -> two-stage sync is enough.
reg  [15:0] S_lat_meta, S_lat_sync;
always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
    if(!S_hdmi_rst_n) begin
        S_lat_meta <= 16'd0;
        S_lat_sync <= 16'd0;
    end else begin
        S_lat_meta <= S_lat_fid;
        S_lat_sync <= S_lat_meta;
    end
end

// ---- 三色检测结果跨时钟域到 HDMI (2026-10-10) ------------------------------
// 192 位 = 3 色 x 64 位, 从 isp_top 导出(ISP 域), 给 hdmi_mixer 画**质心十字**
// 和**颜色名文字** —— 对应扩展要求②的"文字说明"和进阶要求(2)的"跟踪标识"。
//
// 两级同步就够: 这是个**帧级**的量(每帧在 I_tuser 才更新一次)。逐位 2 拍同步
// 最坏让某一帧读到"半新半旧"的值 —— 表现是那一帧的十字位置差一点, 下一帧就对
// 了, 肉眼看不出来。所以不需要握手, 也不需要格雷码。
// (One 工程里有单独的 cdc_sync 模块, 这里只有一处用途, 直接写两级同步更省事,
//  也免得为了一个模块再去动 .al 的源文件列表。)
wire [191:0] S_det_boxes_csi;      // isp_top 导出 (ISP 域)
wire [191:0] S_det_boxes_hdmi;     // 同步到 HDMI 域
reg  [191:0] S_det_meta, S_det_sync;
always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
    if(!S_hdmi_rst_n) begin
        S_det_meta <= 192'd0;
        S_det_sync <= 192'd0;
    end else begin
        S_det_meta <= S_det_boxes_csi;
        S_det_sync <= S_det_meta;
    end
end
assign S_det_boxes_hdmi = S_det_sync;

// ---- 小车串口 (2026-10-12): 检测结果 -> UART TX (CYT4BB7 的 RX) -------------
// 摄像头装在小车上往前看。追踪 = 视觉伺服: 每帧把三色块的"横向偏差 + 尺寸"
// 发给小车 MCU, 它据偏差转向、据尺寸调速, 让目标色块保持在画面正中。
//
// 协议 (每帧 7 字节, 60Hz, 115200 8N1):
//   [0] 0xAA        帧头
//   [1] 红 偏差     有符号: (红cx-640)>>3, 0=居中 负=偏左 正=偏右; 0x80=本帧无红
//   [2] 红 宽度     (right-left)>>3, 小=远 大=近
//   [3] 绿 偏差   [4] 绿 宽度
//   [5] 蓝 偏差   [6] 蓝 宽度
// 0xAA 不会与数据撞车: 偏差取值 [-80,+79] (0x80 哨兵), 宽度 [0,159], 都到不了
// 0xAA。前提是 >>3 这个比例不变; 改比例要重新核对 0xAA 会不会出现在数据里。

// 检测结果跨时钟域 (CSI -> 100MHz)。帧级量, 两级同步够(理由同上面到 HDMI 那段)。
wire [191:0] S_det_boxes_100m;
reg  [191:0] S_det_meta_100m, S_det_sync_100m;
always @(posedge S_100m_clk or negedge S_rst_n) begin
    if (!S_rst_n) begin
        S_det_meta_100m <= 192'd0;
        S_det_sync_100m <= 192'd0;
    end else begin
        S_det_meta_100m <= S_det_boxes_csi;
        S_det_sync_100m <= S_det_meta_100m;
    end
end
assign S_det_boxes_100m = S_det_sync_100m;

// 每色取 valid/cx/left/right (位布局见 isp_top 头部注释: 每色 64 位)
wire        S_v_r = S_det_boxes_100m[ 42];
wire [10:0] S_cx_r = S_det_boxes_100m[ 53: 43];
wire [9:0]  S_cy_r = S_det_boxes_100m[ 63: 54];
wire [10:0] S_l_r  = S_det_boxes_100m[ 41: 31];
wire [10:0] S_r_r  = S_det_boxes_100m[ 30: 20];
wire        S_v_g = S_det_boxes_100m[106];
wire [10:0] S_cx_g = S_det_boxes_100m[117:107];
wire [9:0]  S_cy_g = S_det_boxes_100m[127:118];
wire [10:0] S_l_g  = S_det_boxes_100m[105: 95];
wire [10:0] S_r_g  = S_det_boxes_100m[ 94: 84];
wire        S_v_b = S_det_boxes_100m[170];
wire [10:0] S_cx_b = S_det_boxes_100m[181:171];
wire [9:0]  S_cy_b = S_det_boxes_100m[191:182];
wire [10:0] S_l_b  = S_det_boxes_100m[169:159];
wire [10:0] S_r_b  = S_det_boxes_100m[158:148];

// 偏差字节: (cx-640)>>3, 有符号 8bit; 无目标 -> 0x80
wire signed [11:0] S_dx_r = $signed({1'b0, S_cx_r}) - 12'sd640;
wire signed [11:0] S_dx_g = $signed({1'b0, S_cx_g}) - 12'sd640;
wire signed [11:0] S_dx_b = $signed({1'b0, S_cx_b}) - 12'sd640;
wire [7:0] S_dev_r = S_v_r ? S_dx_r[10:3] : 8'h80;
wire [7:0] S_dev_g = S_v_g ? S_dx_g[10:3] : 8'h80;
wire [7:0] S_dev_b = S_v_b ? S_dx_b[10:3] : 8'h80;

// 宽度字节: (right-left)>>3, 0..159
wire [10:0] S_w_r = S_r_r - S_l_r;
wire [10:0] S_w_g = S_r_g - S_l_g;
wire [10:0] S_w_b = S_r_b - S_l_b;
wire [7:0] S_wid_r = S_v_r ? S_w_r[10:3] : 8'd0;
wire [7:0] S_wid_g = S_v_g ? S_w_g[10:3] : 8'd0;
wire [7:0] S_wid_b = S_v_b ? S_w_b[10:3] : 8'd0;

// UDP compact telemetry: red, green and blue each use deviation/width/y-div4.
assign S_color_telemetry = {
    S_cy_b[9:2], S_wid_b, S_dev_b,
    S_cy_g[9:2], S_wid_g, S_dev_g,
    S_cy_r[9:2], S_wid_r, S_dev_r
};

// 帧触发: S_raw_tuser (CSI 域帧开始脉冲) 打翻转 -> 同步到 100MHz -> 沿检测。
// 沿(3 级)比数据(2 级)晚一拍到达, 保证读到的是已稳定的上一帧检测结果。
reg S_frame_toggle_csi;
always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
    if (!S_rst_n) S_frame_toggle_csi <= 1'b0;
    else if (S_raw_tuser) S_frame_toggle_csi <= ~S_frame_toggle_csi;
end
reg [2:0] S_frame_toggle_100m;
always @(posedge S_100m_clk or negedge S_rst_n) begin
    if (!S_rst_n) S_frame_toggle_100m <= 3'd0;
    else S_frame_toggle_100m <= {S_frame_toggle_100m[1:0], S_frame_toggle_csi};
end
wire S_frame_event_100m = S_frame_toggle_100m[2] ^ S_frame_toggle_100m[1];

// Buzzer alert was intentionally removed. Keep the board pin quiet while
// preserving the top-level port and pin constraint for rollback compatibility.
assign O_buzzer = 1'b0;

// 打包: [7:0]=0xAA 先发, 依次 红dev 红宽 绿dev 绿宽 蓝dev 蓝宽
wire [55:0] S_car_pkt = { S_wid_b, S_dev_b, S_wid_g, S_dev_g, S_wid_r, S_dev_r, 8'hAA };

uart_pkt_tx #(
    .CLK_FREQ(100_000_000),
    .BAUD    (115200),
    .NBYTE   (7)
) u_car_tx (
    .I_clk  (S_100m_clk),
    .I_rst_n(S_rst_n),
    .I_send (S_frame_event_100m),
    .I_pkt  (S_car_pkt),
    .O_tx   (O_uart_tx),
    .O_busy ()
);

//ISP算法顶层模块
// ---- motion slice count CSI -> HDMI (2026-10-12 / restored 2026-10-19) -----
wire [15:0] S_mot_bcd_csi;
reg  [15:0] S_mot_meta, S_mot_sync;
always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
    if(!S_hdmi_rst_n) begin
        S_mot_meta <= 16'd0;
        S_mot_sync <= 16'd0;
    end else begin
        S_mot_meta <= S_mot_bcd_csi;
        S_mot_sync <= S_mot_meta;
    end
end

isp_top u_isp_top (
.axi4s_video_aclk(S_csi_rx_clk),
.I_rst_n         (S_rst_n),
.I_mode          (S_display_mode),
.I_tlast         (S_raw_tlast	),
.I_tuser         (S_raw_tuser	),
.I_tdata         (S_raw_tdata	),
.I_tvalid        (S_raw_tvalid	),
.I_tdest         (),
.O_tready        (S_ISP_O_tready),
.O_tdata         (S_ISP_O_tdata ),
.O_tlast         (S_ISP_O_tlast ),
.O_tuser         (S_ISP_O_tuser ),
.O_tvalid        (S_ISP_O_tvalid),
.I_tready        (),
.O_det_boxes     (S_det_boxes_csi),
.O_mot_cnt       (S_mot_cnt_csi),
.O_mot_bcd       (S_mot_bcd_csi),
.O_mot_box       (S_mot_box_csi),
.O_ae_too_bright (S_isp_ae_too_bright),
.O_ae_too_dark   (S_isp_ae_too_dark),
.O_ae_frame_toggle(S_isp_ae_frame_toggle)
  );


    video_in u_video_in(
        .I_rst_n              (  S_rst_n             ),

        .I_camera_clk         ( S_csi_rx_clk          ),
        .I_camera_frame_start ( S_ISP_O_tuser  ),
        .I_camera_valid       ( S_ISP_O_tvalid ),
        .I_camera_data        ( S_ISP_O_tdata  ),
        .I_mipi_rx_error      ( 1'b0			      ),

        .I_ddr_clk            ( S_ddr_clk             ),
		.I_display_pause      ( 1'b0                  ),
        .I_video_out_rd_busy  ( S_video_out_rd_busy   ),
        .O_video_in_wr_busy   ( S_video_in_wr_busy    ),
        .O_video_out_rp       ( S_video_out_rp        ),
        .O_lat_fid            ( S_lat_fid             ),
        .O_frame_id           ( S_frame_id            ),

        .O_ddr_user_wr_en     ( S_vi_ddr_wr_en        ),
        .O_ddr_user_addr      ( S_vi_ddr_wr_addr      ),
        .O_ddr_user_wr_data   ( S_vi_ddr_wr_data      ),
        .I_ddr_user_ready     ( S_ddr_user_ready      )
    );



    assign S_ddr_user_wr_en    = S_vi_ddr_wr_en;

    assign S_ddr_user_rd_en    = S_vo_ddr_rd_en;

    assign S_ddr_user_addr     = S_vi_ddr_wr_en ? S_vi_ddr_wr_addr :
                                 S_vo_ddr_rd_en ? S_vo_ddr_rd_addr : 'd0;

    assign S_ddr_user_wr_data  = S_vi_ddr_wr_data;


    assign S_video_out_rst_n = S_hdmi_rst_n;

    video_out u_video_out(
        .I_rst_n             ( S_video_out_rst_n    ),
        .I_ddr_clk           ( S_ddr_clk            ),
 
        .O_video_out_rd_busy ( S_video_out_rd_busy  ),
        .I_video_in_wr_busy  ( S_video_in_wr_busy   ),
        .I_video_out_rp      ( S_video_out_rp       ),
 
        .O_ddr_user_rd_en    ( S_vo_ddr_rd_en       ),
        .O_ddr_user_addr     ( S_vo_ddr_rd_addr     ),
        .I_ddr_user_ready    ( S_ddr_user_ready     ),
        .I_ddr_user_rd_valid ( S_ddr_user_rd_valid  ),
        .I_ddr_user_rd_data  ( S_ddr_user_rd_data   ),

        .I_dsi_clk           ( S_hdmi_pixel_clk     ),
        .I_video_vsync       ( S_video_out_vsync    ),
        .I_video_rd_en       ( S_hdmi_window_rd_en  ),
        .O_vdieo_data        ( S_video_rd_data      )
    );



    mc_to_user_interface u_mc_to_user_interface(
        .I_clk                   ( S_ddr_clk               ),
        .I_rst_n                 ( S_rst_n                 ),

        .I_ddr_user_wr_en        ( S_ddr_user_wr_en        ),
        .I_ddr_user_rd_en        ( S_ddr_user_rd_en        ),
        .I_ddr_user_addr         ( S_ddr_user_addr         ),
        .I_ddr_user_wr_data      ( S_ddr_user_wr_data      ),
        .O_ddr_user_ready        ( S_ddr_user_ready        ),
        .O_ddr_user_rd_valid     ( S_ddr_user_rd_valid     ),
        .O_ddr_user_rd_data      ( S_ddr_user_rd_data      ),
            
        .O_mc_app_en             ( S_mc_app_en             ),
        .O_mc_app_addr           ( S_mc_app_addr           ),
        .O_mc_app_cmd            ( S_mc_app_cmd            ),
        .I_mc_app_rdy            ( S_mc_app_rdy            ),
        .O_mc_app_wdf_wren       ( S_mc_app_wdf_wren       ),
        .O_mc_app_wdf_data       ( S_mc_app_wdf_data       ),
        .O_mc_app_wdf_end        ( S_mc_app_wdf_end        ),
        .O_mc_app_wdf_mask       ( S_mc_app_wdf_mask       ),
        .I_mc_app_wdf_rdy        ( S_mc_app_wdf_rdy        ),
        .I_mc_app_rd_data        ( S_mc_app_rd_data        ),
        .I_mc_app_rd_data_end    ( S_mc_app_rd_data_end    ),
        .I_mc_app_rd_data_valid  ( S_mc_app_rd_data_valid  )
    );



    ph1p35_324_ddr_wrapper u_ph1p35_324_ddr_wrapper(
        .I_sys_clk              ( I_sys_clk              ),
        .I_sys_rst_n            ( S_rst_n                ),

        .O_ddr_clk              ( S_ddr_clk              ),
        .O_init_calib_complete  ( S_init_calib_complete  ),
        .I_mc_app_addr          ( S_mc_app_addr          ),
        .I_mc_app_cmd           ( S_mc_app_cmd           ),
        .I_mc_app_en            ( S_mc_app_en            ),
        .I_mc_app_wdf_data      ( S_mc_app_wdf_data      ),
        .I_mc_app_wdf_end       ( S_mc_app_wdf_end       ),
        .I_mc_app_wdf_mask      ( S_mc_app_wdf_mask      ),
        .I_mc_app_wdf_wren      ( S_mc_app_wdf_wren      ),
        .O_mc_app_rd_data       ( S_mc_app_rd_data       ),
        .O_mc_app_rd_data_end   ( S_mc_app_rd_data_end   ),
        .O_mc_app_rd_data_valid ( S_mc_app_rd_data_valid ),
        .O_mc_app_rdy           ( S_mc_app_rdy           ),
        .O_mc_app_wdf_rdy       ( S_mc_app_wdf_rdy       ),

        .ddr_addr               ( ddr_addr               ),
        .ddr_ba                 ( ddr_ba                 ),
        .ddr_cke                ( ddr_cke                ),
        .ddr_odt                ( ddr_odt                ),
        .ddr_cs_n               ( ddr_cs_n               ),
        .ddr_ras_n              ( ddr_ras_n              ),
        .ddr_cas_n              ( ddr_cas_n              ),
        .ddr_we_n               ( ddr_we_n               ),
        .ddr_ck_p               ( ddr_ck_p               ),
        .ddr_ck_n               ( ddr_ck_n               ),
        .ddr_dm                 ( ddr_dm                 ),
        .ddr_dq                 ( ddr_dq                 ),
        .ddr_dqs_p              ( ddr_dqs_p              ),
        .ddr_dqs_n              ( ddr_dqs_n              )
    );



    uivtc #(
        .H_ActiveSize ( 1280 ),
        .H_FrameSize  ( 1650 ),
        .H_SyncStart  ( 1390 ),
        .H_SyncEnd    ( 1430 ),
        .V_ActiveSize ( 720  ),
        .V_FrameSize  ( 750  ),
        .V_SyncStart  ( 725  ),
        .V_SyncEnd    ( 730  )
    )u_hdmi_vtc(
        .I_vtc_rstn    ( S_hdmi_rst_n    ),
        .I_vtc_clk     ( S_hdmi_pixel_clk ),
        .O_vtc_vs      ( S_hdmi_vsync     ),
        .O_vtc_hs      ( S_hdmi_hsync     ),
        .O_vtc_de_valid( S_hdmi_de        ),
        .O_vtc_user    ( S_hdmi_user      ),
        .O_vtc_last    ( S_hdmi_last      )
    );

    // ---- 按键控制 "安路" Logo 显示 (2026-10-09) ----------------------------
    // 两个按键都接进来: I_button[0] (N2) 和 I_button[1] (J14)。
    // 原因: 原理图里按键网络是 KEY0..KEY3, 而按焊球反查哪个是哪个没查出来
    // (竖排文字配对, 抽文本对不上)。用 & 就不用管了:
    //   - 哪个键没接按键 -> 引脚约束带内部上拉, 读恒 1 -> x & 1 = x, 不影响另一个
    //   - 两个都接了 -> 按哪个都翻转
    // 别再假设"J14 是按键": 板上确认存在的是 N2 (GPIOA5, 按键0)。
    //
    // 每按一次翻转一次。默认 1 = 显示 —— 赛题基础要求 4 要求输出画面里含"安路"
    // 标识 Logo, 所以上电必须带着; 按键是用来关掉它看干净画面的。
    //
    // key_remove_shakes 已在 .al 里, 直接复用。它下降沿触发, 按住约 100000 拍
    // (@75MHz 约 1.33ms) 后出一个单拍高脉冲 —— 正常按键都能满足。
    // 整条逻辑放在 HDMI 像素时钟域, 和 hdmi_mixer 同域, 不需要跨时钟同步。
    wire S_logo_key_trig;
    reg  S_logo_en;

    // ---- 2026-10-10: 按键重新分工 -----------------------------------------
    //   I_button[0] = N2  = 原理图上的**按键0** (GPIOA5, 交叉验证过) -> 模式切换
    //   I_button[1] = J14 -> Logo 开关
    // J14 在原理图上挨着 GPIOB 网络, 反查不出是哪个 KEY 网络。之前把 Logo 开关
    // 放在它上面, 结果按了没反应。现在只把它留在 Logo 上 —— 就算它真不是按键,
    // 引脚内部上拉读到 1, Logo 保持常开, **没有任何副作用**; 而模式切换放在
    // 确认过的 N2 上。
    // Logo 上电默认开 (基础要求 4 要求画面里必须含"安路"标识)。
    key_remove_shakes u_logo_key (
        .I_clk         ( S_hdmi_pixel_clk ),
        .I_rst_n       ( S_hdmi_rst_n     ),
        .I_key_in      ( I_button[1]      ),
        .O_key_trig_out( S_logo_key_trig  )
    );

    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if(!S_hdmi_rst_n)
            S_logo_en <= 1'b1;              // 上电默认带 Logo
        else if(S_logo_key_trig)
            S_logo_en <= ~S_logo_en;
    end

    hdmi_mixer #(
        .H_OFFSET   ( 0    ),
        .V_OFFSET   ( 0    ),
        .IMG_WIDTH  ( 1280 ),
        .IMG_HEIGHT ( 720  ),
        .DEBUG_MODE ( 0    )
    )u_hdmi_mixer(
        .I_clk           ( S_hdmi_pixel_clk   ),
        .I_rst_n         ( S_hdmi_rst_n       ),
        .I_logo_en       ( S_logo_en          ),
        .I_mode          ( S_mode_hdmi_sync   ),
        .I_ae_exp        ( S_ae_hdmi_sync     ),
        .I_ae_gain       ( S_ag_hdmi_sync     ),
        .I_mot_cnt       ( S_mot_sync          ),
        .I_lat_fid       ( S_lat_sync         ),
        .I_det_boxes     ( S_det_boxes_hdmi   ),
        .I_video_vsync   ( S_hdmi_vsync       ),
        .I_video_hsync   ( S_hdmi_hsync       ),
        .I_video_de      ( S_hdmi_de          ),
        .I_video_user    ( S_hdmi_user        ),
        .I_video_last    ( S_hdmi_last        ),
        .I_debug_status  ( S_hdmi_debug_status),
        .O_video_rd_en   ( S_hdmi_window_rd_en),
        .I_video_rd_data ( S_video_rd_data    ),
        .O_hdmi_vsync    ( S_hdmi_out_vsync   ),
        .O_hdmi_hsync    ( S_hdmi_out_hsync   ),
        .O_hdmi_de       ( S_hdmi_out_de      ),
        .O_hdmi_data     ( S_hdmi_out_data    )
    );

    hdmi_tx u_hdmi_tx(
        .I_pixel_clk        ( S_hdmi_pixel_clk  ),
        .I_serial_clk       ( S_hdmi_serial_clk ),
        .I_rst              ( ~S_hdmi_rst_n     ),
        .I_key_in           ( 1'b0              ),
        .I_edid_read_trig   ( 1'b0              ),
        .O_edid_read_valid  (                   ),
        .O_edid_read_data   (                   ),
        .I_video_rgb_enable ( 1'b1              ),
        .I_video_in_vs      ( S_hdmi_out_vsync  ),
        .I_video_in_de      ( S_hdmi_out_de     ),
        .I_video_in_user    ( 1'b0              ),
        .I_video_in_valid   ( 1'b0              ),
        .I_video_in_last    ( 1'b0              ),
        .O_video_in_ready   (                   ),
        .I_video_in_data    ( S_hdmi_out_data   ),
        .I_audio_valid      ( 1'b0              ),
        .I_audio_left_data  ( 24'd0             ),
        .I_audio_right_data ( 24'd0             ),
        .I_i2s_BCLK         ( 1'b0              ),
        .I_i2s_LRCK         ( 1'b0              ),
        .I_i2s_DOUT         ( 1'b0              ),
        .O_ddc_scl          (                   ),
        .O_hdmi_clk_p       (                   ),
        .O_hdmi_tx_p        (                   ),
        .O_tmds_ch0_p       ( O_tmds_ch0_p      ),
        .O_tmds_ch1_p       ( O_tmds_ch1_p      ),
        .O_tmds_ch2_p       ( O_tmds_ch2_p      ),
        .O_tmds_clk_p       ( O_tmds_clk_p      )
    );


    
endmodule
