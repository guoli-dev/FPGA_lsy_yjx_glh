module traffic_button_ctrl(
    input            clk,
    input            rst_n,
    input            ped_btn,
    output reg [1:0] main_light,   // 0:Green 1:Yellow 2:Red
    output reg [1:0] ped_light     // 0:Red   1:Green
);

    localparam RED    = 2'd0,
               GREEN  = 2'd1,
               YELLOW = 2'd2;

    localparam RED_TIME    = 5'd9;    // 0~9  = 10 拍
    localparam GREEN_TIME  = 5'd9;
    localparam YELLOW_TIME = 5'd2;    // 0~2  = 3 拍
    localparam COOL_TIME   = 5'd18;

    reg [1:0] state;
    reg [4:0] cnt;      // 当前状态计了几拍（最大 10 → 5 位够）
    reg [4:0] cool;     // 冷却还剩几拍（最大 18 → 5 位够）

    wire btn_ok = ped_btn && (cool == 5'd0);   // 这次按键能不能用

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= RED;
            cnt   <= 5'd0;
            cool  <= 5'd0;
        end else begin
            // 冷却每拍减 1
            if (cool != 5'd0) cool <= cool - 5'd1;

            case (state)
            RED: begin
                if (cnt == RED_TIME) begin
                    state <= GREEN; cnt <= 5'd0;
                end else cnt <= cnt + 5'd1;
            end

            GREEN: begin
                if (btn_ok) begin                 // 中断：下一拍立刻变黄
                    state <= YELLOW;
                    cnt   <= 5'd0;
                    cool  <= COOL_TIME;           // 启动 18 拍冷却
                end else if (cnt == GREEN_TIME) begin
                    state <= YELLOW; cnt <= 5'd0;
                end else cnt <= cnt + 5'd1;
            end

            YELLOW: begin
                if (cnt == YELLOW_TIME) begin
                    state <= RED; cnt <= 5'd0;
                end else cnt <= cnt + 5'd1;
            end

            default: begin state <= RED; cnt <= 5'd0; end
            endcase
        end
    end

    // 输出译码：由状态直接给出（程序头里 output 声明的是 reg）
    always @(*) begin
        case (state)
            RED:    begin main_light = 2'd2; ped_light = 2'd1; end
            GREEN:  begin main_light = 2'd0; ped_light = 2'd0; end
            YELLOW: begin main_light = 2'd1; ped_light = 2'd0; end
            default:begin main_light = 2'd2; ped_light = 2'd1; end
        endcase
    end

endmodule