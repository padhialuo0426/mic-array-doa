set root [file normalize [file join [file dirname [info script]] ..]]
set out [file normalize $::env(MIC_BUILD_DIR)]
file mkdir $out
proc ip {name instance} {
    set definitions [lsort -dictionary [get_ipdefs -all -quiet xilinx.com:ip:${name}:*]]
    if {[llength $definitions]==0} {error "IP unavailable: $name"}
    set vlnv [lindex $definitions end]
    puts "MIC_IP $instance $vlnv"
    return [create_bd_cell -type ip -vlnv $vlnv $instance]
}
proc net {args} {
    set objects {}
    foreach name $args {lappend objects [get_bd_pins $name]}
    connect_bd_net {*}$objects
}
if {[catch {
    create_project -force mic_demo [file join $out vivado] -part xc7z020clg400-2
    set_param general.maxThreads 6
    add_files [glob [file join $root hw rtl *.v]]
    add_files [glob [file join $root hw vendor rgb2dvi src *.vhd]]
    add_files -fileset constrs_1 [file join $root hw constr mic_array_j11.xdc]
    add_files -fileset constrs_1 [file join $root hw constr hdmi.xdc]
    set_property USED_IN_SYNTHESIS false [get_files mic_array_j11.xdc]
    set_property USED_IN_SYNTHESIS false [get_files hdmi.xdc]
    create_bd_design mic_system
    set ps [ip processing_system7 ps7]
    source [file join $root hw ax7020_ddr.tcl]
    configure_ax7020_ddr $ps
    set_property -dict [list \
        CONFIG.PCW_CRYSTAL_PERIPHERAL_FREQMHZ {33.333333} \
        CONFIG.PCW_APU_PERIPHERAL_FREQMHZ {666.666666} \
        CONFIG.PCW_PRESET_BANK0_VOLTAGE {LVCMOS 3.3V} \
        CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 1.8V} \
        CONFIG.PCW_USE_M_AXI_GP0 {1} CONFIG.PCW_USE_S_AXI_HP0 {1} \
        CONFIG.PCW_EN_CLK0_PORT {1} CONFIG.PCW_EN_RST0_PORT {1} \
        CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
        CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
        CONFIG.PCW_UART1_UART1_IO {MIO 48 .. 49} \
        CONFIG.PCW_UART1_BAUD_RATE {115200} \
        CONFIG.PCW_SD0_PERIPHERAL_ENABLE {1} \
        CONFIG.PCW_SD0_SD0_IO {MIO 40 .. 45} \
        CONFIG.PCW_SD0_GRP_CD_ENABLE {1} \
        CONFIG.PCW_SD0_GRP_CD_IO {MIO 47} \
        CONFIG.PCW_SD0_GRP_WP_ENABLE {0} \
    ] $ps
    make_bd_intf_pins_external [get_bd_intf_pins ps7/DDR]
    make_bd_intf_pins_external [get_bd_intf_pins ps7/FIXED_IO]
    set_property name DDR [get_bd_intf_ports DDR_0]
    set_property name FIXED_IO [get_bd_intf_ports FIXED_IO_0]
    set dma [ip axi_dma dma]
    set_property -dict [list CONFIG.c_include_sg {0} CONFIG.c_include_mm2s {0} \
        CONFIG.c_include_s2mm {1} CONFIG.c_sg_length_width {23} \
        CONFIG.c_m_axi_s2mm_data_width {64} CONFIG.c_s_axis_s2mm_tdata_width {32}] $dma
    set fifo [ip axis_data_fifo fifo]
    set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} \
        CONFIG.FIFO_DEPTH {4096} CONFIG.FIFO_MODE {1}] $fifo
    set ctrl [ip axi_interconnect ctrl_bus]
    set_property CONFIG.NUM_MI 4 $ctrl
    set mem [ip axi_interconnect mem_bus]
    set_property CONFIG.NUM_MI 1 $mem
    set reset [ip proc_sys_reset reset]
    # Reset polarity is propagated from PS FCLK_RESET0_N in current IP.
    set one [ip xlconstant one]
    set_property CONFIG.CONST_VAL 1 $one
    set capture [create_bd_cell -type module -reference mic_capture capture]
    set leds [create_bd_cell -type module -reference sk9822_driver leds]
    set video [create_bd_cell -type module -reference hdmi_display video]
    set vclock [ip clk_wiz video_clock]
    set_property -dict [list CONFIG.PRIM_IN_FREQ {100} CONFIG.PRIM_SOURCE {No_buffer} \
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {74.25} CONFIG.CLKOUT2_USED {true} \
        CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {371.25} CONFIG.USE_RESET {false}] $vclock
    net ps7/FCLK_CLK0 video_clock/clk_in1
    net video_clock/clk_out1 video/pclk
    net video_clock/clk_out2 video/sclk
    net video_clock/locked video/locked
    foreach name {hdmi_clk_p hdmi_clk_n hdmi_out_en} {
        create_bd_port -dir O $name
        connect_bd_net [get_bd_ports $name] [get_bd_pins video/$name]
    }
    foreach name {hdmi_data_p hdmi_data_n} {
        create_bd_port -dir O -from 2 -to 0 $name
        connect_bd_net [get_bd_ports $name] [get_bd_pins video/$name]
    }
    create_bd_port -dir I hdmi_hpd
    connect_bd_net [get_bd_ports hdmi_hpd] [get_bd_pins video/hdmi_hpd]
    foreach name {mic_bclk mic_ws} {
        create_bd_port -dir O $name
        connect_bd_net [get_bd_ports $name] [get_bd_pins capture/$name]
    }
    foreach name {led_da led_ck} {
        create_bd_port -dir O $name
        connect_bd_net [get_bd_ports $name] [get_bd_pins leds/$name]
    }
    create_bd_port -dir I -from 3 -to 0 mic_sd
    connect_bd_net [get_bd_ports mic_sd] [get_bd_pins capture/mic_sd]
    connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins ctrl_bus/S00_AXI]
    connect_bd_intf_net [get_bd_intf_pins ctrl_bus/M00_AXI] [get_bd_intf_pins dma/S_AXI_LITE]
    connect_bd_intf_net [get_bd_intf_pins ctrl_bus/M01_AXI] [get_bd_intf_pins capture/S_AXI]
    connect_bd_intf_net [get_bd_intf_pins ctrl_bus/M02_AXI] [get_bd_intf_pins leds/S_AXI]
    connect_bd_intf_net [get_bd_intf_pins ctrl_bus/M03_AXI] [get_bd_intf_pins video/S_AXI]
    connect_bd_intf_net [get_bd_intf_pins capture/M_AXIS] [get_bd_intf_pins fifo/S_AXIS]
    connect_bd_intf_net [get_bd_intf_pins fifo/M_AXIS] [get_bd_intf_pins dma/S_AXIS_S2MM]
    connect_bd_intf_net [get_bd_intf_pins dma/M_AXI_S2MM] [get_bd_intf_pins mem_bus/S00_AXI]
    connect_bd_intf_net [get_bd_intf_pins mem_bus/M00_AXI] [get_bd_intf_pins ps7/S_AXI_HP0]
    net ps7/FCLK_CLK0 ps7/M_AXI_GP0_ACLK ps7/S_AXI_HP0_ACLK \
        ctrl_bus/ACLK ctrl_bus/S00_ACLK ctrl_bus/M00_ACLK ctrl_bus/M01_ACLK ctrl_bus/M02_ACLK ctrl_bus/M03_ACLK \
        mem_bus/ACLK mem_bus/S00_ACLK mem_bus/M00_ACLK \
        dma/s_axi_lite_aclk dma/m_axi_s2mm_aclk fifo/s_axis_aclk capture/aclk leds/aclk video/aclk reset/slowest_sync_clk
    net ps7/FCLK_RESET0_N reset/ext_reset_in
    net one/dout reset/dcm_locked
    net reset/interconnect_aresetn ctrl_bus/ARESETN mem_bus/ARESETN
    net reset/peripheral_aresetn ctrl_bus/S00_ARESETN ctrl_bus/M00_ARESETN ctrl_bus/M01_ARESETN ctrl_bus/M02_ARESETN ctrl_bus/M03_ARESETN \
        mem_bus/S00_ARESETN mem_bus/M00_ARESETN dma/axi_resetn fifo/s_axis_aresetn capture/aresetn leds/aresetn video/aresetn
    assign_bd_address -offset 0x40400000 -range 0x10000 -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs dma/S_AXI_LITE/Reg] -force
    set capseg [get_bd_addr_segs -of_objects [get_bd_intf_pins capture/S_AXI]]
    puts "CAPTURE_ADDR_SEG=$capseg"
    assign_bd_address -offset 0x43C00000 -range 0x10000 -target_address_space [get_bd_addr_spaces ps7/Data] $capseg -force
    set ledseg [get_bd_addr_segs -of_objects [get_bd_intf_pins leds/S_AXI]]
    assign_bd_address -offset 0x43C10000 -range 0x10000 -target_address_space [get_bd_addr_spaces ps7/Data] $ledseg -force
    set videoseg [get_bd_addr_segs -of_objects [get_bd_intf_pins video/S_AXI]]
    assign_bd_address -offset 0x43C40000 -range 0x40000 -target_address_space [get_bd_addr_spaces ps7/Data] $videoseg -force
    assign_bd_address -offset 0 -range 0x40000000 -target_address_space [get_bd_addr_spaces dma/Data_S2MM] [get_bd_addr_segs ps7/S_AXI_HP0/HP0_DDR_LOWOCM] -force
    validate_bd_design
    if {[get_property CONFIG.C_EXT_RESET_HIGH $reset] != 0} {error "Reset polarity must be active-low"}
    save_bd_design
    write_bd_tcl -force [file join $out generated_bd.tcl]
    generate_target all [get_files mic_system.bd]
    set wrappers [make_wrapper -files [get_files mic_system.bd] -top]
    add_files -norecurse $wrappers
    set_property top mic_system_wrapper [current_fileset]
    update_compile_order -fileset sources_1
    launch_runs synth_1 -jobs 6
    wait_on_run synth_1
    if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed"}
    launch_runs impl_1 -to_step write_bitstream -jobs 6
    wait_on_run impl_1
    if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation failed"}
    open_run impl_1
    report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out timing.rpt]
    report_utilization -file [file join $out utilization.rpt]
    report_drc -file [file join $out drc.rpt]
    report_cdc -details -file [file join $out cdc.rpt]
    check_timing -verbose -file [file join $out check_timing.rpt]
    foreach type {max min} {
        set path [get_timing_paths -delay_type $type -max_paths 1]
        if {[llength $path]==0 || [get_property SLACK $path]<0} {error "Timing failed: $type"}
    }
    file copy -force [file join $out vivado mic_demo.runs impl_1 mic_system_wrapper.bit] [file join $out top.bit]
    write_hw_platform -fixed -include_bit -force -file [file join $out top.xsa]
    puts "MIC_HARDWARE_BUILD_OK"
} reason options]} {
    puts stderr "MIC_BUILD_FAILED: $reason"
    puts stderr [dict get $options -errorinfo]
    exit 1
}
exit 0
