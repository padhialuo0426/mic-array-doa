# AX7020 2019 manual, Bank 34 at 3.3 V. Video-only DVI TMDS over HDMI.
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
# DDC/CEC remain un-driven; fixed 720p60 mode, no EDID or audio packets.
set_false_path -from [get_ports hdmi_hpd] -to [get_cells -hier -filter {NAME =~ */canvas/health_meta_reg*}]
# Only first-stage synchronizers are exempt. Bundle mode_hold is held from
# request through frame-boundary acknowledgement; two synchronizer cycles
# precede sampling and software cannot commit/write the pending buffer again.
set_false_path -to [get_cells -hier -filter {NAME =~ */canvas/req_meta_reg || NAME =~ */canvas/ack_meta_reg || NAME =~ */canvas/health_meta_reg*}]
# Async assertion is intentional on the reset synchronizer only. Its release
# propagates through three pixel-clock FFs; downstream resets remain timed.
set_false_path -to [get_pins -hier -filter {NAME =~ */reset_pipe_reg*/CLR}]
# Keep each Gray-counter bit within one source period before the first FF.
set_max_delay -datapath_only 10 -from [get_cells -hier -filter {NAME =~ */canvas/frames_gray_reg*}] -to [get_cells -hier -filter {NAME =~ */canvas/gray_meta_reg*}]
set_bus_skew 10 -from [get_cells -hier -filter {NAME =~ */canvas/frames_gray_reg*}] -to [get_cells -hier -filter {NAME =~ */canvas/gray_meta_reg*}]
set_max_delay -datapath_only 20 -from [get_cells -hier -filter {NAME =~ */canvas/mode_hold_reg}] -to [get_cells -hier -filter {NAME =~ */canvas/bars_reg}]
