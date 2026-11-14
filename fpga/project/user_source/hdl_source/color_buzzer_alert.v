// Stable single-color qualifier and one-shot buzzer alert.
// Color code: 0=none/invalid, 1=red, 2=green, 3=blue.
module color_buzzer_alert #(
    parameter [3:0]  STABLE_FRAMES  = 4'd6,
    parameter [3:0]  BEEP_FRAMES    = 4'd9,
    parameter [15:0] TONE_HALF_LAST = 16'd49_999
)(
    input  wire       I_clk,
    input  wire       I_rst_n,
    input  wire       I_frame_event,
    input  wire       I_card_mode,
    input  wire       I_red_valid,
    input  wire       I_green_valid,
    input  wire       I_blue_valid,
    output reg  [1:0] O_stable_color,
    output wire       O_buzzer
);

    wire [2:0] W_valid = {I_blue_valid, I_green_valid, I_red_valid};
    wire [1:0] W_single_color = (W_valid == 3'b001) ? 2'd1 :
                                (W_valid == 3'b010) ? 2'd2 :
                                (W_valid == 3'b100) ? 2'd3 : 2'd0;

    reg [1:0] R_candidate_color;
    reg [3:0] R_stable_count;

    // Qualify both assertion and color changes at frame boundaries. None or
    // multiple simultaneous colors invalidate the command immediately.
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            R_candidate_color <= 2'd0;
            R_stable_count    <= 4'd0;
            O_stable_color    <= 2'd0;
        end else if (I_frame_event) begin
            if (W_single_color == 2'd0) begin
                R_candidate_color <= 2'd0;
                R_stable_count    <= 4'd0;
                O_stable_color    <= 2'd0;
            end else if (W_single_color != R_candidate_color) begin
                R_candidate_color <= W_single_color;
                R_stable_count    <= 4'd1;
                O_stable_color    <= 2'd0;
            end else if (R_stable_count < STABLE_FRAMES) begin
                R_stable_count <= R_stable_count + 1'b1;
                if (R_stable_count == STABLE_FRAMES - 1'b1)
                    O_stable_color <= W_single_color;
            end else begin
                O_stable_color <= W_single_color;
            end
        end
    end

    reg        R_card_mode_d;
    reg [1:0]  R_announced_color;
    reg [3:0]  R_beep_frame_count;
    reg [15:0] R_tone_count;
    reg        R_beep_active;
    reg        R_buzzer;

    wire W_card_mode_rise = I_card_mode & ~R_card_mode_d;
    // The board buzzer is active low: high is silent, toggling creates a tone.
    assign O_buzzer = ~R_buzzer;

    // Follow mode is always silent and continuously absorbs the current color,
    // so moving the mode switch itself can never create a beep.
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            R_card_mode_d      <= 1'b0;
            R_announced_color  <= 2'd0;
            R_beep_frame_count <= 4'd0;
            R_tone_count       <= 16'd0;
            R_beep_active      <= 1'b0;
            R_buzzer           <= 1'b0;
        end else begin
            R_card_mode_d <= I_card_mode;

            if (!I_card_mode || W_card_mode_rise) begin
                R_announced_color  <= O_stable_color;
                R_beep_frame_count <= 4'd0;
                R_tone_count       <= 16'd0;
                R_beep_active      <= 1'b0;
                R_buzzer           <= 1'b0;
            end else if (W_single_color == 2'd0) begin
                R_beep_frame_count <= 4'd0;
                R_tone_count       <= 16'd0;
                R_beep_active      <= 1'b0;
                R_buzzer           <= 1'b0;
            end else if ((O_stable_color != 2'd0) &&
                         (O_stable_color != R_announced_color)) begin
                R_announced_color  <= O_stable_color;
                R_beep_frame_count <= 4'd0;
                R_tone_count       <= 16'd0;
                R_beep_active      <= 1'b1;
                R_buzzer           <= 1'b0;
            end else if (R_beep_active) begin
                if (R_tone_count == TONE_HALF_LAST) begin
                    R_tone_count <= 16'd0;
                    R_buzzer     <= ~R_buzzer;
                end else begin
                    R_tone_count <= R_tone_count + 1'b1;
                end

                if (I_frame_event) begin
                    if (R_beep_frame_count == BEEP_FRAMES - 1'b1) begin
                        R_beep_frame_count <= 4'd0;
                        R_tone_count       <= 16'd0;
                        R_beep_active      <= 1'b0;
                        R_buzzer           <= 1'b0;
                    end else begin
                        R_beep_frame_count <= R_beep_frame_count + 1'b1;
                    end
                end
            end else begin
                R_beep_frame_count <= 4'd0;
                R_tone_count       <= 16'd0;
                R_buzzer           <= 1'b0;
            end
        end
    end

endmodule
