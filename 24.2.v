module game_count(
    input        clk,
    input        rst_n,
    input  [9:0] money,
    input        set,
    input  [1:0] boost,
    output [9:0] remain,
    output       yellow,
    output       red
);

    localparam IDLE   = 2'b00,
               NORMAL = 2'b01,
               PLAY   = 2'b10,
               TRIAL  = 2'b11;

    reg [9:0] remain_r;
    reg [1:0] state;
    reg [2:0] trial_cnt;      // 体验已用几分钟 0~4
    reg       trial_done;     // 体验机会用完了
    reg       set_q, set_qq;  // 在时钟下降沿采 set（见下面说明）

    assign remain = remain_r;

    // set 在时钟下降沿采一次（周期中间，值最稳）
    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) set_q <= 1'b0;
        else        set_q <= set;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= NORMAL;   // 复位后默认普通模式
            trial_cnt  <= 3'd0;
            trial_done <= 1'b0;     // 复位后体验次数恢复
            set_qq     <= 1'b0;
            remain_r   <= 10'd0;
        end else begin
            set_qq <= set_q;

            // ---------- 模式选择 ----------
            case (boost)
                IDLE:   begin state <= IDLE;   trial_cnt <= 3'd0; end
                NORMAL: begin state <= NORMAL; trial_cnt <= 3'd0; end
                PLAY:   begin state <= PLAY;   trial_cnt <= 3'd0; end
                TRIAL: begin
                    if (!trial_done) begin
                        if (state != TRIAL) begin
                            state     <= TRIAL;      // 进入体验
                            trial_cnt <= 3'd0;
                        end else if (trial_cnt == 3'd4) begin
                            state      <= NORMAL;    // 5 分钟到，回普通
                            trial_done <= 1'b1;      // 用掉了
                            trial_cnt  <= 3'd0;
                        end else begin
                            trial_cnt <= trial_cnt + 3'd1;
                        end
                    end
                    // 体验已用过：保持当前模式
                end
            endcase

            // ---------- 钱：先充值，否则扣一分钟 ----------
            if (set_q && !set_qq) begin
                remain_r <= remain_r + money;
            end else begin
                case (state)
                    NORMAL: if (remain_r >= 10'd1) remain_r <= remain_r - 10'd1;
                    PLAY:   if (remain_r >= 10'd2) remain_r <= remain_r - 10'd2;
                    default: ;                        // 关机/体验不扣费
                endcase
            end
        end
    end

    assign yellow = (state != IDLE) && (remain_r > 10'd0) && (remain_r < 10'd10);
    assign red    = (state != IDLE) && (remain_r == 10'd0);

endmodule
