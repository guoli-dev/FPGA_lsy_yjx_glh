module pulse_cnt(
    input            i_clk,
    input            i_rst_n,
    input            i_pulse_en,
    input            i_pulse,
    output reg [2:0] o_bina,
    output reg       o_ready
);

    reg       en_d;        // i_pulse_en 的上一拍值
    reg       pulse_d;     // i_pulse 的上一拍值
    reg       active;      // 1 = 正在计数
    reg [2:0] cnt;         // 已数到的脉冲个数

    wire en_rise = i_pulse_en & ~en_d;   // i_pulse_en 的上升沿
    wire p_rise  = i_pulse    & ~pulse_d;// i_pulse 的上升沿

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            en_d    <= 1'b0;
            pulse_d <= 1'b0;
            active  <= 1'b0;
            cnt     <= 3'd0;
            o_bina  <= 3'd0;
            o_ready <= 1'b0;
        end else begin
            en_d    <= i_pulse_en;       // 记下这一拍，下一拍就能看出变化
            pulse_d <= i_pulse;
            o_ready <= 1'b0;             // 默认低，只做单周期脉冲

            if (en_rise) begin
                if (!active) begin       // 第一个使能：开始
                    active <= 1'b1;
                    cnt    <= 3'd0;
                end else begin           // 第二个使能：结束
                    active  <= 1'b0;
                    o_ready <= 1'b1;
                    if      (cnt <= 3'd1) o_bina <= 3'b001;
                    else if (cnt <= 3'd3) o_bina <= 3'b010;
                    else                  o_bina <= 3'b100;
                end
          end else if (active && p_rise) begin
                cnt <= cnt + 3'd1;       // 计数窗口内，数脉冲
            end
        end
    end

endmodule