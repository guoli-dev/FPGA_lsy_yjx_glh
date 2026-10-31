create_clock -name {sys_clk_50m} -period 20.000 -waveform {0.000 10.000} [get_ports {I_sys_clk}]
create_clock -name {mipi_rx_ck_pad} -period 4.167 -waveform {0.000 2.083} [get_nets {IO_rx_clk_pad_p}]

derive_clocks

rename_clock -name {pll_clk_100m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name {pll_clk_24m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[1]}]
rename_clock -name {HDMI_PIXEL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}]
rename_clock -name {HDMI_SERIAL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[5]}]

rename_clock -name {MIPI_RX_BYTE_CLK} [get_clocks {u_mipi_dphy_rx_ph1p_mipiio_wrapper/u_ph1p_mipiio_rx_wrapper/u_PH1P_LOGIC_DPHY_MIPI_RX.o_fabric_div4_8_clk}]

# ---- Ethernet RGMII (2026-10-22) -------------------------------------------
# Define Ethernet clocks before they are referenced by set_clock_groups.
rename_clock -name {a_tx_clk} [get_clocks {u_eth_host/u_eth_pll/ph1p_phy_pll_wrapper_d2616deaaa79_Inst/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name {clk_25m}   [get_clocks {u_eth_host/u_eth_pll/ph1p_phy_pll_wrapper_d2616deaaa79_Inst/u_PH1P_PHY_PLL.clkc[2]}]

create_clock -name {I_a_rgmii_rxc} -period 8.000 -waveform {0.000 4.000} [get_ports {I_a_rgmii_rxc}]
create_generated_clock -name {O_a_tx_clk} -source [get_pins {u_eth_host/u_eth_pll/ph1p_phy_pll_wrapper_d2616deaaa79_Inst/u_PH1P_PHY_PLL.clkc[0]}] -master_clock {a_tx_clk} -multiply_by 1.000 -phase 0.000 [get_ports {O_a_rgmii_txc}]

set_clock_groups -asynchronous \
    -group [get_clocks {mipi_rx_ck_pad MIPI_RX_BYTE_CLK}] \
    -group [get_clocks {sys_clk_50m pll_clk_100m pll_clk_24m HDMI_PIXEL_CLK HDMI_SERIAL_CLK}] \
    -group [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}] \
    -group [get_clocks {I_a_rgmii_rxc}] \
    -group [get_clocks {a_tx_clk O_a_tx_clk}] \
    -group [get_clocks {clk_25m}]

# AE readout uses two-flop 24 MHz -> HDMI synchronizers. Exempt only the
# metastability-capturing first stage; the second stage remains timed.
set_false_path -from [get_clocks {pll_clk_24m}] -to [get_regs -nowarn {S_a?_hdmi_meta*}]

set_input_delay -clock [get_clocks {I_a_rgmii_rxc}] -max 2.500 [get_ports {{I_a_rgmii_rxd[*]} I_a_rgmii_rx_ctl}]
set_input_delay -clock [get_clocks {I_a_rgmii_rxc}] -min 2.500 [get_ports {{I_a_rgmii_rxd[*]} I_a_rgmii_rx_ctl}]
set_input_delay -clock [get_clocks {I_a_rgmii_rxc}] -max -clock_fall -add_delay 2.500 [get_ports {{I_a_rgmii_rxd[*]} I_a_rgmii_rx_ctl}]
set_input_delay -clock [get_clocks {I_a_rgmii_rxc}] -min -clock_fall -add_delay 2.500 [get_ports {{I_a_rgmii_rxd[*]} I_a_rgmii_rx_ctl}]

set_output_delay -clock [get_clocks O_a_tx_clk] -max 2.800 [get_ports {O_a_rgmii_tx_ctl {O_a_rgmii_txd[*]}}]
set_output_delay -clock [get_clocks O_a_tx_clk] -min 1.200 [get_ports {O_a_rgmii_tx_ctl {O_a_rgmii_txd[*]}}]
set_output_delay -clock [get_clocks O_a_tx_clk] -clock_fall -max -add_delay 2.800 [get_ports {O_a_rgmii_tx_ctl {O_a_rgmii_txd[*]}}]
set_output_delay -clock [get_clocks O_a_tx_clk] -clock_fall -min -add_delay 1.200 [get_ports {O_a_rgmii_tx_ctl {O_a_rgmii_txd[*]}}]

set_false_path -rise_from [get_clocks a_tx_clk] -rise_to [get_clocks O_a_tx_clk] -setup
set_false_path -fall_from [get_clocks a_tx_clk] -fall_to [get_clocks O_a_tx_clk] -setup
set_false_path -rise_from [get_clocks a_tx_clk] -fall_to [get_clocks O_a_tx_clk] -hold
set_false_path -fall_from [get_clocks a_tx_clk] -rise_to [get_clocks O_a_tx_clk] -hold
