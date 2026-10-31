`timescale 1ns / 1ps

// Frame-statistics automatic-exposure controller for SC500CS.
// The exposure unit is half a sensor line. VTS remains 1000, so the maximum
// setpoint is 1990, matching the existing sensor initialization and 60 fps.
module ae_set (
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire [3:0]  I_btn,
    input  wire        I_ae_cfg_done,
    input  wire        I_cam_cfg_done,
    input  wire        I_frame_event,
    input  wire        I_too_bright,
    input  wire        I_too_dark,
    output wire        O_ae_req,
    output wire [15:0] O_ae,
    output wire [15:0] O_ag
);

localparam [10:0] AE_BASE = 11'd1990;
localparam [10:0] AE_MAX  = 11'd1990;
localparam [10:0] AE_MIN  = 11'd800;
localparam [10:0] AE_STEP = 11'd64;
localparam [7:0]  AG_MAX  = 8'd143;
localparam [7:0]  AG_BASE = 8'd143;
localparam [7:0]  AG_MIN  = 8'd80;
localparam [7:0]  AG_STEP = 8'd2;
localparam [2:0]  SETTLE_FRAMES = 3'd4;

reg [10:0] r_ae;
reg [7:0]  r_ag;
reg        r_ae_req;
reg [2:0]  r_settle;

wire w_cfg_en = I_cam_cfg_done && I_ae_cfg_done;

assign O_ae     = {5'd0, r_ae};
assign O_ag     = {8'd0, r_ag};
assign O_ae_req = r_ae_req;

// Make one control decision per completed frame. Four settling frames allow
// the I2C write and sensor pipeline to take effect before the next decision.
always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        r_ae     <= AE_BASE;
        r_ag     <= AG_BASE;
        r_ae_req <= 1'b0;
        r_settle <= 3'd0;
    end else begin
        r_ae_req <= 1'b0;
        if (I_frame_event && w_cfg_en) begin
            if (r_settle != 3'd0) begin
                r_settle <= r_settle - 3'd1;
            end else if (I_too_bright) begin
                // Reduce gain first to lower noise, then reduce exposure.
                if (r_ag > AG_MIN) begin
                    r_ag <= (r_ag < (AG_MIN + AG_STEP)) ? AG_MIN
                                                         : (r_ag - AG_STEP);
                    r_ae_req <= 1'b1;
                    r_settle <= SETTLE_FRAMES;
                end else if (r_ae > AE_MIN) begin
                    r_ae <= (r_ae < (AE_MIN + AE_STEP)) ? AE_MIN
                                                         : (r_ae - AE_STEP);
                    r_ae_req <= 1'b1;
                    r_settle <= SETTLE_FRAMES;
                end
            end else if (I_too_dark) begin
                // Restore exposure first for SNR, then restore sensor gain.
                if (r_ae < AE_MAX) begin
                    r_ae <= (r_ae > (AE_MAX - AE_STEP)) ? AE_MAX
                                                         : (r_ae + AE_STEP);
                    r_ae_req <= 1'b1;
                    r_settle <= SETTLE_FRAMES;
                end else if (r_ag < AG_MAX) begin
                    r_ag <= (r_ag > (AG_MAX - AG_STEP)) ? AG_MAX
                                                         : (r_ag + AG_STEP);
                    r_ae_req <= 1'b1;
                    r_settle <= SETTLE_FRAMES;
                end
            end
        end
    end
end

endmodule
