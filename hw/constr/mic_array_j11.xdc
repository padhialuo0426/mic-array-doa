set_property -dict {PACKAGE_PIN F17 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports mic_bclk]
set_property -dict {PACKAGE_PIN F16 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports mic_ws]
set_property -dict {PACKAGE_PIN G19 IOSTANDARD LVCMOS33 PULLDOWN TRUE} [get_ports {mic_sd[0]}]
set_property -dict {PACKAGE_PIN G20 IOSTANDARD LVCMOS33 PULLDOWN TRUE} [get_ports {mic_sd[1]}]
set_property -dict {PACKAGE_PIN F19 IOSTANDARD LVCMOS33 PULLDOWN TRUE} [get_ports {mic_sd[2]}]
set_property -dict {PACKAGE_PIN F20 IOSTANDARD LVCMOS33 PULLDOWN TRUE} [get_ports {mic_sd[3]}]
set_property -dict {PACKAGE_PIN H18 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports led_da]
set_property -dict {PACKAGE_PIN J18 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports led_ck]
# The first input FF is an explicit metastability boundary. SD is re-sampled
# through a second FF and consumed only 3/4 into a generated BCLK period.
# This exception applies ONLY to the pad -> first FF, not the synchronous path.
set_false_path -from [get_ports {mic_sd[*]}] -to [get_cells -hier -filter {NAME =~ */rx/sd_meta_reg*}]
# Outputs are slow GPIO waveforms, not clock inputs to internal RTL. Bound the
# register -> pad route; the cycle-accurate testbench verifies relative edges.
# Board-level I2S electrical timing still requires physical verification.
set_max_delay -datapath_only -from [get_cells -hier -filter {NAME =~ */rx/mic_bclk_reg || NAME =~ */rx/mic_ws_reg}] -to [get_ports {mic_bclk mic_ws}] 10.0
set_false_path -to [get_ports {led_da led_ck}]
