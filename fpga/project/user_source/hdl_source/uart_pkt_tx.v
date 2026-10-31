// 多字节 UART 帧发送器 (8N1)。I_send 脉冲触发, 从 I_pkt[7:0] 开始逐字节发送,
// 共 NBYTE 字节, 每字节完整 10 位: 起始位 + 8 数据(LSB 先) + 停止位。忙时忽略新 I_send。
// 100MHz / 115200 -> DIV=868, 实际波特率 115207, 误差 +0.006%。
module uart_pkt_tx #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD     = 115200,
    parameter NBYTE    = 4
)(
    input                 I_clk,
    input                 I_rst_n,
    input                 I_send,     // 1 拍脉冲启动一次发送; 忙时忽略
    input  [NBYTE*8-1:0] I_pkt,      // [7:0] 先发
    output reg            O_tx,       // 空闲为高
    output reg            O_busy
);
    localparam [15:0] DIV = CLK_FREQ / BAUD;   // 每 bit 的时钟周期数

    reg [15:0] cnt;        // bit 内分频计数
    reg [3:0]  bit_pos;    // 当前正在发的位: 0=起始 1..8=数据 9=停止
    reg [7:0]  cur_byte;   // 当前字节
    reg [NBYTE*8-1:0] pkt; // 待发字节队列, 每发完一个右移 8 位
    reg [7:0]  byte_cnt;   // 已发完的字节数

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tx     <= 1'b1;
            O_busy   <= 1'b0;
            cnt      <= 16'd0;
            bit_pos  <= 4'd0;
            cur_byte <= 8'd0;
            pkt      <= {NBYTE*8{1'b0}};
            byte_cnt <= 8'd0;
        end else if (O_busy) begin
            if (cnt == DIV - 1) begin
                cnt <= 16'd0;
                if (bit_pos == 4'd9) begin        // 停止位刚发完
                    if (byte_cnt == NBYTE - 1) begin
                        O_busy <= 1'b0;           // 全部发完, 回空闲(线保持高)
                        O_tx   <= 1'b1;
                    end else begin
                        byte_cnt <= byte_cnt + 1'b1;
                        bit_pos  <= 4'd0;
                        O_tx     <= 1'b0;         // 下一字节起始位
                        cur_byte <= pkt[15:8];
                        pkt      <= pkt >> 8;
                    end
                end else begin
                    bit_pos <= bit_pos + 1'b1;
                    O_tx    <= (bit_pos == 4'd8) ? 1'b1 : cur_byte[bit_pos];
                end
            end else begin
                cnt <= cnt + 1'b1;
            end
        end else if (I_send) begin
            O_busy   <= 1'b1;
            O_tx     <= 1'b0;                     // 起始位
            cnt      <= 16'd0;
            bit_pos  <= 4'd0;
            byte_cnt <= 8'd0;
            cur_byte <= I_pkt[7:0];
            pkt      <= I_pkt;
        end
    end
endmodule
