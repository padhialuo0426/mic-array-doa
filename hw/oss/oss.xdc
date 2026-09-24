# Pins for the open-source flow (nextpnr-xilinx). Same locations, standards,
# drive and slew as hw/constr/*.xdc; PULLDOWN TRUE is written PULLTYPE PULLDOWN.
# Timing exceptions of the Vivado constraints are not read by nextpnr.
set_property -dict {PACKAGE_PIN F17 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports mic_bclk]
set_property -dict {PACKAGE_PIN F16 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports mic_ws]
set_property -dict {PACKAGE_PIN G19 IOSTANDARD LVCMOS33 PULLTYPE PULLDOWN} [get_ports {mic_sd[0]}]
set_property -dict {PACKAGE_PIN G20 IOSTANDARD LVCMOS33 PULLTYPE PULLDOWN} [get_ports {mic_sd[1]}]
set_property -dict {PACKAGE_PIN F19 IOSTANDARD LVCMOS33 PULLTYPE PULLDOWN} [get_ports {mic_sd[2]}]
set_property -dict {PACKAGE_PIN F20 IOSTANDARD LVCMOS33 PULLTYPE PULLDOWN} [get_ports {mic_sd[3]}]
set_property -dict {PACKAGE_PIN H18 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports led_da]
set_property -dict {PACKAGE_PIN J18 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports led_ck]
set_property -dict {PACKAGE_PIN N18 IOSTANDARD TMDS_33} [get_ports hdmi_clk_p]
set_property -dict {PACKAGE_PIN P19 IOSTANDARD TMDS_33} [get_ports hdmi_clk_n]
set_property -dict {PACKAGE_PIN V20 IOSTANDARD TMDS_33} [get_ports {hdmi_data_p[0]}]
set_property -dict {PACKAGE_PIN W20 IOSTANDARD TMDS_33} [get_ports {hdmi_data_n[0]}]
set_property -dict {PACKAGE_PIN T20 IOSTANDARD TMDS_33} [get_ports {hdmi_data_p[1]}]
set_property -dict {PACKAGE_PIN U20 IOSTANDARD TMDS_33} [get_ports {hdmi_data_n[1]}]
set_property -dict {PACKAGE_PIN N20 IOSTANDARD TMDS_33} [get_ports {hdmi_data_p[2]}]
set_property -dict {PACKAGE_PIN P20 IOSTANDARD TMDS_33} [get_ports {hdmi_data_n[2]}]
set_property -dict {PACKAGE_PIN Y19 IOSTANDARD LVCMOS33} [get_ports hdmi_hpd]
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW} [get_ports hdmi_out_en]

# Clock periods: FCLK0 100 MHz; MMCM pixel 74.25 MHz and serial 371.25 MHz
# (nextpnr-xilinx does not derive MMCM outputs; --freq only sets a default).
create_clock -period 10.0 [get_nets aclk]
create_clock -period 13.468 [get_nets pclk]
create_clock -period 2.694 [get_nets sclk]
