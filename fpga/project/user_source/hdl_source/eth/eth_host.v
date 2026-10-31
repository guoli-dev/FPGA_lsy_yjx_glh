`timescale 1ns / 1ps
// eth_host: Ethernet(UDP) host-computer interface for HX1P35A.
// Downlink (host -> FPGA, udp dst port 6002):
//   [0]=cmd, [1]=arg
//     0x01 = set display mode, arg = 0..4
//     0x02 = request status now
//     0x03 = request compact color telemetry now
//     0x04 = request motion bounding-box telemetry now
// Uplink status (FPGA -> host, udp dst port 6001), 12 bytes:
//   AA mode fps_lo fps_hi link frame_lo frame_hi latency_lo latency_hi motion_lo motion_hi 55
// Uplink color telemetry, 11 bytes:
//   AB red_dev red_width red_y4 green_dev green_width green_y4 blue_dev blue_width blue_y4 55
// Uplink motion-box telemetry, 12 bytes:
//   AC box[7:0] .. box[63:56] motion_lo motion_hi 55
//   box bit layout (isp_top O_mot_box): [42]=valid [41:31]=left
//   [30:20]=right [19:10]=top [9:0]=bottom  (coords in 1280x720)
// Owns: ethernet PLL(50M->125/125_90/25M), PHY reset, uiudp_stack, rgmii_interface.
// Self-contained: only needs I_sys_clk + RGMII pins. Reset chain = own PLL lock.

module eth_host (
    input  wire        I_sys_clk,        // 50MHz (C4)
    input  wire [3:0]  I_rgmii_rxd,
    input  wire        I_rgmii_rx_ctl,
    input  wire        I_rgmii_rxc,
    output wire [3:0]  O_rgmii_txd,
    output wire        O_rgmii_tx_ctl,
    output wire        O_rgmii_txc,
    output wire        O_phy_rst,

    input  wire [2:0]  I_mode,           // current display mode (csi domain, async)
    input  wire [15:0] I_frame_id,       // frame counter (ddr domain, async)
    input  wire [15:0] I_latency_frames,  // capture-to-display latency in frames
    input  wire [14:0] I_motion_count,    // motion-region slice count
    input  wire [71:0] I_color_data,      // 3 colors x {y/4, width/8, deviation/8}
    input  wire [63:0] I_mot_box,         // motion bounding box (isp_top O_mot_box)

    output reg         O_mode_toggle,    // toggles on each set-mode cmd (clk_125)
    output reg  [2:0]  O_mode_val        // mode value (clk_125)
);

// ---------------------------------------------------------------------------
// Ethernet PLL + PHY reset + reset chain
// ---------------------------------------------------------------------------
wire clk_125, clk_125_90, clk_25;
wire pll_locked;
wire phy_rst;
assign O_phy_rst = phy_rst;
wire reset = ~phy_rst;                    // active high, held during PHY reset window

pll u_eth_pll(
    .refclk    (I_sys_clk),
    .reset     (1'b0),
    .lock      (pll_locked),
    .clk0_out  (clk_125),
    .clk1_out  (clk_125_90),
    .clk2_out  (clk_25)
);

uiphyrst #(.CLK_FREQ(32'd25_000_000)) u_phyrst(
    .I_CLK    (clk_25),
    .I_rstn   (pll_locked),
    .I_phyrst (pll_locked),
    .O_phyrst (phy_rst)
);

// ---------------------------------------------------------------------------
// uiudp_stack + rgmii_interface
// ---------------------------------------------------------------------------
wire [7:0]  gmii_tdata;
wire        gmii_tvalid;
wire [7:0]  gmii_rdata;
wire        gmii_rvalid;
wire        gmii_rclk;

wire        R_udp_valid;
wire [7:0]  R_udp_data;
wire [15:0] R_udp_len;
wire [15:0] R_udp_src_port;

wire        W_udp_busy;
reg         W_udp_req;
reg         W_udp_valid;
reg  [7:0]  W_udp_data;
reg  [1:0]  tx_kind;                       // 0=status 1=color 2=motbox
wire [15:0] W_udp_len = (tx_kind == 2'd1) ? 16'd11 : 16'd12;

uiudp_stack #(
    .CRC_GEN_EN        (1'b1),
    .INTER_FRAME_GAP   (4'd12)
) udp_stack_inst (
    .I_uclk            (clk_125),
    .I_reset           (reset),
    .I_mac_local_addr  (48'h0223456789ab), // locally administered unicast MAC
    .I_udp_local_port  (16'd6002),
    .I_ip_local_addr   (32'hc0a88902),    // 192.168.137.2
    .I_udp_dest_port   (16'd6001),
    .I_ip_dest_addr    (32'hc0a88901),    // 192.168.137.1
    .O_W_udp_busy      (W_udp_busy),
    .I_W_udp_req       (W_udp_req),
    .I_W_udp_valid     (W_udp_valid),
    .I_W_udp_data      (W_udp_data),
    .I_W_udp_len       (W_udp_len),
    .O_R_udp_valid     (R_udp_valid),
    .O_R_udp_data      (R_udp_data),
    .O_R_udp_len       (R_udp_len),
    .O_R_udp_src_port  (R_udp_src_port),
    .I_gmii_rclk       (gmii_rclk),
    .I_gmii_rvalid     (gmii_rvalid),
    .I_gmii_rdata      (gmii_rdata),
    .I_gmii_tclk       (clk_125),
    .O_gmii_tvalid     (gmii_tvalid),
    .O_gmii_tdata      (gmii_tdata),
    .O_ip_rerror       (),
    .O_mac_rerror      ()
);

wire link_status;

rgmii_interface rgmii_interface_inst(
    .speed_10_100 (1'b0),
    .gmii_tx_clk_d(clk_125),
    .gmii_tx_reset_d(reset),
    .gmii_tx_reset(reset),
    .gmii_tx_clk  (clk_125),
    .gmii_txd     (gmii_tdata),
    .gmii_tx_en   (gmii_tvalid),
    .gmii_tx_er   (1'b0),
    .gmii_rx_reset(reset),
    .gmii_rx_clk  (gmii_rclk),
    .gmii_rxd     (gmii_rdata),
    .gmii_rx_dv   (gmii_rvalid),
    .gmii_rx_er   (),
    .rgmii_txd    (O_rgmii_txd),
    .rgmii_tx_ctl (O_rgmii_tx_ctl),
    .rgmii_txc    (O_rgmii_txc),
    .rgmii_rxd    (I_rgmii_rxd),
    .rgmii_rx_ctl (I_rgmii_rx_ctl),
    .rgmii_rxc    (I_rgmii_rxc),
    .gmii_crs     (),
    .gmii_col     (),
    .link_status  (link_status),
    .clock_speed  (),
    .duplex_status()
);

// ---------------------------------------------------------------------------
// status inputs: 2-stage sync; all source values change at frame rate or slower
// ---------------------------------------------------------------------------
reg [2:0]  mode_s1, mode_s2;
reg [15:0] fid_s1, fid_s2;
reg [15:0] latency_s1, latency_s2;
reg [14:0] motion_s1, motion_s2;
reg [71:0] color_s1, color_s2;
reg [63:0] mot_box_s1, mot_box_s2;
always @(posedge clk_125 or posedge reset) begin
    if(reset) begin
        mode_s1 <= 3'd0; mode_s2 <= 3'd0;
        fid_s1  <= 16'd0; fid_s2  <= 16'd0;
        latency_s1 <= 16'd0; latency_s2 <= 16'd0;
        motion_s1 <= 15'd0; motion_s2 <= 15'd0;
        color_s1 <= 72'd0; color_s2 <= 72'd0;
        mot_box_s1 <= 64'd0; mot_box_s2 <= 64'd0;
    end else begin
        mode_s1 <= I_mode;  mode_s2 <= mode_s1;
        fid_s1  <= I_frame_id; fid_s2 <= fid_s1;
        latency_s1 <= I_latency_frames; latency_s2 <= latency_s1;
        motion_s1 <= I_motion_count; motion_s2 <= motion_s1;
        color_s1 <= I_color_data; color_s2 <= color_s1;
        mot_box_s1 <= I_mot_box; mot_box_s2 <= mot_box_s1;
    end
end
wire [2:0]  mode_sync = mode_s2;
wire [15:0] fid_sync  = fid_s2;

// ---------------------------------------------------------------------------
// frame rate: 1s tick, fps = frame counter delta
// ---------------------------------------------------------------------------
reg [26:0] tick_cnt;
reg        tick;              // 1-cycle pulse every 1s
reg [15:0] fid_prev;
reg [15:0] fps;
always @(posedge clk_125 or posedge reset) begin
    if(reset) begin
        tick_cnt <= 27'd0; tick <= 1'b0;
        fid_prev <= 16'd0; fps <= 16'd0;
    end else begin
        tick <= 1'b0;
        if(tick_cnt == 27'd125_000_000 - 27'd1) begin
            tick_cnt <= 27'd0;
            tick     <= 1'b1;
            fps      <= fid_sync - fid_prev;
            fid_prev <= fid_sync;
        end else
            tick_cnt <= tick_cnt + 27'd1;
    end
end

// ---------------------------------------------------------------------------
// RX: parse downlink command
// ---------------------------------------------------------------------------
reg rudp_valid_d;
reg [7:0] rx_b0;
reg [1:0] rx_cnt;
wire sop = R_udp_valid & ~rudp_valid_d;
wire rx_req_stat  = sop & (R_udp_data == 8'h02);
wire rx_req_color = sop & (R_udp_data == 8'h03);
wire rx_req_motbox= sop & (R_udp_data == 8'h04);

always @(posedge clk_125 or posedge reset) begin
    if(reset) begin
        rudp_valid_d <= 1'b0;
        rx_b0        <= 8'd0;
        rx_cnt       <= 2'd0;
        O_mode_val   <= 3'd0;
        O_mode_toggle<= 1'b0;
    end else begin
        rudp_valid_d <= R_udp_valid;
        if(sop) begin
            rx_b0  <= R_udp_data;         // cmd byte
            rx_cnt <= 2'd1;
        end else if(R_udp_valid && rx_cnt == 2'd1) begin
            // byte1 = arg; execute set-mode
            if(rx_b0 == 8'h01 && R_udp_data <= 8'd4) begin
                O_mode_val    <= R_udp_data[2:0];
                O_mode_toggle <= ~O_mode_toggle;
            end
            rx_cnt <= 2'd2;
        end
    end
end

// ---------------------------------------------------------------------------
// TX: periodic status plus on-demand status/color/motion telemetry
// ---------------------------------------------------------------------------
localparam TX_IDLE = 3'd0, TX_REQ = 3'd1, TX_WAIT_BUSY = 3'd2,
           TX_SEND = 3'd3, TX_DONE = 3'd4;
reg [2:0] tx_state;
reg [4:0] tx_cnt;
wire tx_go = tick | rx_req_stat | rx_req_color | rx_req_motbox;

always @(posedge clk_125 or posedge reset) begin
    if(reset) begin
        tx_state   <= TX_IDLE;
        W_udp_req  <= 1'b0;
        W_udp_valid<= 1'b0;
        W_udp_data <= 8'd0;
        tx_cnt     <= 5'd0;
        tx_kind    <= 2'd0;
    end else begin
        W_udp_req <= 1'b0;                 // req is a 1-cycle pulse
        case(tx_state)
        TX_IDLE: begin
            W_udp_valid <= 1'b0;
            if(tx_go && !W_udp_busy) begin
                tx_kind   <= rx_req_motbox ? 2'd2 : rx_req_color ? 2'd1 : 2'd0;
                W_udp_req <= 1'b1;
                tx_state  <= TX_REQ;
            end
        end
        TX_REQ: tx_state <= TX_WAIT_BUSY;
        TX_WAIT_BUSY: begin
            if(W_udp_busy) begin
                tx_cnt   <= 5'd0;
                tx_state <= TX_SEND;
            end
        end
        TX_SEND: begin
            W_udp_valid <= 1'b1;
            tx_cnt      <= tx_cnt + 5'd1;
            if(tx_kind == 2'd1) begin
                case(tx_cnt)
                5'd0: W_udp_data <= 8'hAB;
                5'd1: W_udp_data <= color_s2[7:0];
                5'd2: W_udp_data <= color_s2[15:8];
                5'd3: W_udp_data <= color_s2[23:16];
                5'd4: W_udp_data <= color_s2[31:24];
                5'd5: W_udp_data <= color_s2[39:32];
                5'd6: W_udp_data <= color_s2[47:40];
                5'd7: W_udp_data <= color_s2[55:48];
                5'd8: W_udp_data <= color_s2[63:56];
                5'd9: W_udp_data <= color_s2[71:64];
                default: W_udp_data <= 8'h55;
                endcase
            end else if(tx_kind == 2'd2) begin
                case(tx_cnt)
                5'd0: W_udp_data <= 8'hAC;
                5'd1: W_udp_data <= mot_box_s2[7:0];
                5'd2: W_udp_data <= mot_box_s2[15:8];
                5'd3: W_udp_data <= mot_box_s2[23:16];
                5'd4: W_udp_data <= mot_box_s2[31:24];
                5'd5: W_udp_data <= mot_box_s2[39:32];
                5'd6: W_udp_data <= mot_box_s2[47:40];
                5'd7: W_udp_data <= mot_box_s2[55:48];
                5'd8: W_udp_data <= mot_box_s2[63:56];
                5'd9: W_udp_data <= motion_s2[7:0];
                5'd10: W_udp_data <= {1'b0, motion_s2[14:8]};
                default: W_udp_data <= 8'h55;
                endcase
            end else begin
                case(tx_cnt)
                5'd0: W_udp_data <= 8'hAA;
                5'd1: W_udp_data <= {5'd0, mode_sync};
                5'd2: W_udp_data <= fps[7:0];
                5'd3: W_udp_data <= fps[15:8];
                5'd4: W_udp_data <= {7'd0, link_status};
                5'd5: W_udp_data <= fid_sync[7:0];
                5'd6: W_udp_data <= fid_sync[15:8];
                5'd7: W_udp_data <= latency_s2[7:0];
                5'd8: W_udp_data <= latency_s2[15:8];
                5'd9: W_udp_data <= motion_s2[7:0];
                5'd10: W_udp_data <= {1'b0, motion_s2[14:8]};
                default: W_udp_data <= 8'h55;
                endcase
            end
            if((tx_kind == 2'd1 && tx_cnt == 5'd10) || (tx_kind != 2'd1 && tx_cnt == 5'd11))
                tx_state <= TX_DONE;
        end
        TX_DONE: begin
            W_udp_valid <= 1'b0;
            tx_state    <= TX_IDLE;
        end
        default: tx_state <= TX_IDLE;
        endcase
    end
end

endmodule
