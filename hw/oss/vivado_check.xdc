# Extra constraints for timing-checking the open-source top (hw/oss/top.v) in
# Vivado, read together with hw/constr/*.xdc. Not used by the openXC7 build.
# The PS7 primitive has no IP constraint file to define FCLK0 (100 MHz); the
# MMCM outputs (pixel 74.25 MHz, serial 371.25 MHz) are then derived.
create_clock -name clk_fpga_0 -period 10.000 [get_pins ps7/FCLKCLK[0]]
# rgb2dvi.v: asynchronous assertion into its pixel-clock reset synchronizer.
set_false_path -to [get_pins -hier -filter {NAME =~ */reset_sync_reg*/PRE}]
# top.v: FCLK_RESET0_N is asynchronous to aclk; first synchronizer stage.
set_false_path -to [get_cells -hier -filter {NAME =~ reset_sync_reg[0]}]
