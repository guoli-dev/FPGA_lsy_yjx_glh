# Command-line full build entry for the relocatable .al project.
set alRun syn_1
set device_name ph1_35p.db
set package_name PH1P35MDG324
set speed 3
set prj_name camera_to_dsi_display
set top_model_name design_top_wrapper
set start_step read_design
set end_step bitgen
set area_option -packarea
set arr_filter false
set drHoldFix on
set ADCList {"../user_source/constraints_source/pin.adc"}
set IpADCList {ddr2 ../user_source/hdl_source/ph1p35_ddr/ddr2/src/adc/ddr2.adc}
set SDCList {"camera_to_dsi_display.sdc"}
set IpSDCList {ddr2 ../user_source/hdl_source/ph1p35_ddr/ddr2/src/sdc/ddr2.sdc w128_d512_fifo ../user_source/ip_source/w128_d512_fifo/w128_d512_fifo.tcl}

source ./OptFlow.tcl
