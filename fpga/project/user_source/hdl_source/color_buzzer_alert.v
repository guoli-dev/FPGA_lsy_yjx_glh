// Color target first-frame buzzer alert.
// Detection and frame-event inputs are synchronous to the 100 MHz clock.
module color_buzzer_alert #(
    parameter [3:0]  FRAME_SLOT_LAST = 4'd8,
    parameter [14:0] TONE_HALF_LAST  = 15'd24_999
)(
    input  wire I_clk,
    input  wire I_rst_n,
    input  wire I_frame_event,
    input  wire I_red_valid,
    input  wire I_blue_valid,
    input  wire I_green_valid,
    output wire O_buzzer
);

    reg R_red_seen;
    reg R_blue_seen;
    reg R_green_seen;

    wire W_red_rise   = I_red_valid   & ~R_red_seen;
    wire W_blue_rise  = I_blue_valid  & ~R_blue_seen;
    wire W_green_rise = I_green_valid & ~R_green_seen;

    // Simultaneous first detections use the longest audible code.
    wire [1:0] W_new_beeps = W_green_rise ? 2'd3 :
                             W_blue_rise  ? 2'd2 :
                             W_red_rise   ? 2'd1 : 2'd0;

    reg [3:0]  R_frame_count;
    reg [14:0] R_tone_count;
    reg [2:0]  R_slots_left;
    reg        R_tone_enable;
    reg        R_buzzer;

    assign O_buzzer = R_buzzer;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            R_red_seen    <= 1'b0;
            R_blue_seen   <= 1'b0;
            R_green_seen  <= 1'b0;
            R_frame_count <= 4'd0;
            R_tone_count  <= 15'd0;
            R_slots_left  <= 3'd0;
            R_tone_enable <= 1'b0;
            R_buzzer      <= 1'b0;
        end else begin
            if (I_frame_event) begin
                R_red_seen   <= I_red_valid;
                R_blue_seen  <= I_blue_valid;
                R_green_seen <= I_green_valid;
            end

            if (R_slots_left == 3'd0) begin
                R_frame_count <= 4'd0;
                R_tone_count  <= 15'd0;
                R_tone_enable <= 1'b0;
                R_buzzer      <= 1'b0;

                if (I_frame_event && (W_new_beeps != 2'd0)) begin
                    R_slots_left  <= {W_new_beeps, 1'b0} - 3'd1;
                    R_tone_enable <= 1'b1;
                end
            end else begin
                if (R_tone_enable) begin
                    if (R_tone_count == TONE_HALF_LAST) begin
                        R_tone_count <= 15'd0;
                        R_buzzer     <= ~R_buzzer;
                    end else begin
                        R_tone_count <= R_tone_count + 15'd1;
                    end
                end else begin
                    R_tone_count <= 15'd0;
                    R_buzzer     <= 1'b0;
                end

                if (I_frame_event) begin
                    if (R_frame_count == FRAME_SLOT_LAST) begin
                        R_frame_count <= 4'd0;
                        R_tone_count  <= 15'd0;
                        R_buzzer      <= 1'b0;

                        if (R_slots_left == 3'd1) begin
                            R_slots_left  <= 3'd0;
                            R_tone_enable <= 1'b0;
                        end else begin
                            R_slots_left  <= R_slots_left - 3'd1;
                            R_tone_enable <= ~R_tone_enable;
                        end
                    end else begin
                        R_frame_count <= R_frame_count + 4'd1;
                    end
                end
            end
        end
    end

endmodule
