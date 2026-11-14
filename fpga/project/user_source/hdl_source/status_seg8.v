// Eight-digit board display: left four digits show car mode, right four show
// the stable color. Digit and segment outputs are active low.
module status_seg8 (
    input  wire       I_clk,
    input  wire       I_rst_n,
    input  wire       I_card_mode,
    input  wire       I_red_valid,
    input  wire       I_green_valid,
    input  wire       I_blue_valid,
    input  wire [1:0] I_stable_color,
    output reg  [7:0] O_seg_sel,
    output reg  [7:0] O_seg_dig
);

    localparam [4:0] CHAR_BLANK = 5'd0;
    localparam [4:0] CHAR_DASH  = 5'd1;
    localparam [4:0] CHAR_A     = 5'd2;
    localparam [4:0] CHAR_B     = 5'd3;
    localparam [4:0] CHAR_C     = 5'd4;
    localparam [4:0] CHAR_D     = 5'd5;
    localparam [4:0] CHAR_E     = 5'd6;
    localparam [4:0] CHAR_F     = 5'd7;
    localparam [4:0] CHAR_G     = 5'd8;
    localparam [4:0] CHAR_L     = 5'd9;
    localparam [4:0] CHAR_N     = 5'd10;
    localparam [4:0] CHAR_O     = 5'd11;
    localparam [4:0] CHAR_R     = 5'd12;
    localparam [4:0] CHAR_U     = 5'd13;

    reg [16:0] R_scan_count;
    reg [2:0]  R_digit_index;
    reg [4:0]  R_char;

    wire W_multi_color = (I_red_valid & I_green_valid) |
                         (I_red_valid & I_blue_valid) |
                         (I_green_valid & I_blue_valid);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            R_scan_count  <= 17'd0;
            R_digit_index <= 3'd0;
        end else begin
            R_scan_count <= R_scan_count + 1'b1;
            if (&R_scan_count)
                R_digit_index <= R_digit_index + 1'b1;
        end
    end

    // SEL[7] is the leftmost digit and SEL[0] is the rightmost digit.
    always @(*) begin
        O_seg_sel = 8'hff;
        O_seg_sel[R_digit_index] = 1'b0;
        R_char = CHAR_BLANK;

        case (R_digit_index)
            3'd7: R_char = I_card_mode ? CHAR_C : CHAR_F;
            3'd6: R_char = I_card_mode ? CHAR_A : CHAR_O;
            3'd5: R_char = I_card_mode ? CHAR_R : CHAR_L;
            3'd4: R_char = I_card_mode ? CHAR_D : CHAR_L;
            3'd3: begin
                if (W_multi_color)
                    R_char = CHAR_A;
                else begin
                    case (I_stable_color)
                        2'd1: R_char = CHAR_R;
                        2'd2: R_char = CHAR_G;
                        2'd3: R_char = CHAR_B;
                        default: R_char = CHAR_DASH;
                    endcase
                end
            end
            3'd2: begin
                if (W_multi_color)
                    R_char = CHAR_L;
                else begin
                    case (I_stable_color)
                        2'd1: R_char = CHAR_E;
                        2'd2: R_char = CHAR_R;
                        2'd3: R_char = CHAR_L;
                        default: R_char = CHAR_DASH;
                    endcase
                end
            end
            3'd1: begin
                if (W_multi_color)
                    R_char = CHAR_L;
                else begin
                    case (I_stable_color)
                        2'd1: R_char = CHAR_D;
                        2'd2: R_char = CHAR_N;
                        2'd3: R_char = CHAR_U;
                        default: R_char = CHAR_DASH;
                    endcase
                end
            end
            3'd0: begin
                if (W_multi_color)
                    R_char = CHAR_BLANK;
                else if (I_stable_color == 2'd3)
                    R_char = CHAR_E;
                else if (I_stable_color == 2'd0)
                    R_char = CHAR_DASH;
                else
                    R_char = CHAR_BLANK;
            end
            default: R_char = CHAR_BLANK;
        endcase

        case (R_char)
            CHAR_DASH: O_seg_dig = 8'hbf;
            CHAR_A:    O_seg_dig = 8'h88;
            CHAR_B:    O_seg_dig = 8'h83;
            CHAR_C:    O_seg_dig = 8'hc6;
            CHAR_D:    O_seg_dig = 8'ha1;
            CHAR_E:    O_seg_dig = 8'h86;
            CHAR_F:    O_seg_dig = 8'h8e;
            CHAR_G:    O_seg_dig = 8'hc2;
            CHAR_L:    O_seg_dig = 8'hc7;
            CHAR_N:    O_seg_dig = 8'hab;
            CHAR_O:    O_seg_dig = 8'ha3;
            CHAR_R:    O_seg_dig = 8'haf;
            CHAR_U:    O_seg_dig = 8'hc1;
            default:   O_seg_dig = 8'hff;
        endcase
    end

endmodule
