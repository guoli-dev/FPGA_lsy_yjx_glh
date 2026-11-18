module serial_lock(
    input        clk,
    input        rst_n,
    input  [3:0] key_val,
    input        key_valid,
    input        backspace,
    input        confirm,
    output       unlock,
    output       alarm,
    output [1:0] retry_cnt,
    output [2:0] input_len
);

    localparam IDLE = 2'd0, OPEN = 2'd1, LOCK = 2'd2;

    reg [3:0] d0, d1, d2, d3;   // 缓冲
    reg [2:0] len;              // 长度 0~4
    reg [1:0] state;
    reg [1:0] retry;            // 剩余机会
    reg [6:0] cnt;              // 倒计时
    reg       unlock_r, alarm_r;

    assign unlock    = unlock_r;
    assign alarm     = alarm_r;
    assign retry_cnt = retry;
    assign input_len = len;

    wire buf_ok = (len == 3'd4) &&
                  (d0 == 4'd1) && (d1 == 4'd2) &&
                  (d2 == 4'd3) && (d3 == 4'd4);
 
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; len <= 0; retry <= 2'd2; cnt <= 0;
            unlock_r <= 0; alarm_r <= 0;
            d0 <= 0; d1 <= 0; d2 <= 0; d3 <= 0;
        end else begin
            case (state)

            IDLE: begin
                if (confirm) begin
                   ·                      // 确认后一律清缓冲
                    if (buf_ok) begin
                        state <= OPEN; unlock_r <= 1;
                        cnt <= 7'd10; retry <= 2'd2;
                    end else if (retry <= 2'd1) begin
                        state <= LOCK; alarm_r <= 1;
                        cnt <= 7'd50; retry <= 2'd0;
                    end else begin
                        retry <= retry - 2'd1;
                    end
                end else if (key_valid) begin
                    if (len < 3'd4) begin
                        case (len)
                            3'd0: d0 <= key_val;
                            3'd1: d1 <= key_val;
                            3'd2: d2 <= key_val;
                            3'd3: d3 <= key_val;
                        endcase
                        len <= len + 3'd1;
                    end
                end else if (backspace) begin
                    if (len > 0) len <= len - 3'd1;
                end
            end

            OPEN: begin
                if (cnt <= 7'd1) begin
                    unlock_r <= 0; cnt <= 0; state <= IDLE;
                end else cnt <= cnt - 7'd1;
            end

            LOCK: begin
                if (cnt <= 7'd1) begin
                    alarm_r <= 0; cnt <= 0; retry <= 2'd2; state <= IDLE;
                end else cnt <= cnt - 7'd1;
            end

            endcase
        end
    end

endmodule