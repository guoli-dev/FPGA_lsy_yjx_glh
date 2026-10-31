`timescale 1ns / 1ps

// UDP-only IPv4 layer used by the contest build.
//
// The vendor reference layer also implements ICMP echo. The PC application
// communicates exclusively through UDP, so the echo path and its 2 KiB FIFO
// are deliberately omitted. ARP and bidirectional UDP remain unchanged.
module uiip_layer (
    input  wire [31:0] I_ip_local_addr,
    input  wire [31:0] I_ip_dest_addr,
    input  wire        I_ip_reset,
    input  wire        I_ip_clk,
    output wire        O_ip_udp_rvalid,
    output wire [7:0]  O_ip_udp_rdata,
    output wire        O_ip_udp_tbusy,
    input  wire        I_ip_udp_treq,
    input  wire        I_ip_udp_tvalid,
    input  wire [7:0]  I_ip_udp_tdata,
    input  wire [15:0] I_ip_udp_tdata_len,
    input  wire        I_ip_tbusy,
    output wire        O_ip_treq,
    output wire        O_ip_tvalid,
    output wire [7:0]  O_ip_tdata,
    output wire [31:0] O_ip_taddr,
    input  wire        I_ip_rvalid,
    input  wire [7:0]  I_ip_rdata,
    output wire        O_ip_rerror
);

uiip_tx #(
    .VERSION         (4'h4),
    .IHL             (4'h5),
    .TOS             (8'h00),
    .ID_BASE         (16'h0000),
    .FLAG            (3'b010),
    .FRAGMENT_OFFSET (13'd0)
) ip_tx_inst (
    .I_ip_local_addr           (I_ip_local_addr),
    .I_ip_dest_addr            (I_ip_dest_addr),
    .I_reset                   (I_ip_reset),
    .I_ip_clk                  (I_ip_clk),
    .O_ip_udp_tbusy            (O_ip_udp_tbusy),
    .I_ip_udp_treq             (I_ip_udp_treq),
    .I_ip_udp_tvalid           (I_ip_udp_tvalid),
    .I_ip_udp_tdata            (I_ip_udp_tdata),
    .I_ip_udp_tdata_len        (I_ip_udp_tdata_len),
    .I_ip_tbusy                (I_ip_tbusy),
    .O_ip_treq                 (O_ip_treq),
    .O_ip_tvalid               (O_ip_tvalid),
    .O_ip_tdata                (O_ip_tdata),
    .O_ip_taddr                (O_ip_taddr),
    .I_icmp_req_en             (1'b0),
    .I_icmp_req_id             (16'd0),
    .I_icmp_req_sq_num         (16'd0),
    .I_icmp_req_checksum       (16'd0),
    .I_icmp_req_ip_addr        (32'd0),
    .I_icmp_ping_echo_data     (8'd0),
    .I_icmp_ping_echo_data_len (10'd0),
    .O_icmp_ping_echo_ren      ()
);

uiip_rx ip_rx_inst (
    .I_ip_local_addr             (I_ip_local_addr),
    .I_reset                     (I_ip_reset),
    .I_ip_clk                    (I_ip_clk),
    .I_ip_rvalid                 (I_ip_rvalid),
    .I_ip_rdata                  (I_ip_rdata),
    .O_icmp_req_ip_addr          (),
    .O_icmp_req_en               (),
    .O_icmp_req_id               (),
    .O_icmp_req_sq_num           (),
    .O_icmp_req_checksum         (),
    .O_icmp_ping_echo_data_valid (),
    .O_icmp_ping_echo_data       (),
    .O_icmp_ping_echo_data_len   (),
    .O_udp_ip_rvalid             (O_ip_udp_rvalid),
    .O_udp_ip_rdata              (O_ip_udp_rdata),
    .O_checksum_rerror           (O_ip_rerror)
);

endmodule
