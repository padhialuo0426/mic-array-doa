# Vivado cross-check of the open-source top (hw/oss/top.v): the same Verilog
# the openXC7 flow builds, implemented and timed by Vivado. Verification only;
# the release hardware is still hw/build.tcl. Usage:
#   MIC_BUILD_DIR=<out> vivado -mode batch -source hw/oss/vivado_check.tcl
set root [file normalize [file join [file dirname [info script]] .. ..]]
set out [file normalize $::env(MIC_BUILD_DIR)]
file mkdir $out
set_param general.maxThreads 6
if {[catch {
    create_project -in_memory -part xc7z020clg400-2
    read_verilog [glob [file join $root hw rtl *.v]]
    foreach f [glob [file join $root hw oss *.v]] {read_verilog $f}
    synth_design -top top -part xc7z020clg400-2
    read_xdc [file join $root hw constr mic_array_j11.xdc]
    read_xdc [file join $root hw constr hdmi.xdc]
    read_xdc [file join $root hw oss vivado_check.xdc]
    opt_design
    place_design
    phys_opt_design
    route_design
    report_timing_summary -delay_type min_max -report_unconstrained -max_paths 20 -file [file join $out timing.rpt]
    report_utilization -file [file join $out utilization.rpt]
    report_utilization -hierarchical -file [file join $out utilization_hier.rpt]
    report_cdc -details -file [file join $out cdc.rpt]
    report_clocks -file [file join $out clocks.rpt]
    report_drc -file [file join $out drc.rpt]
    write_bitstream -force [file join $out top.bit]
    set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
    set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
    puts "MIC_OSS_VIVADO_OK WNS=$wns WHS=$whs"
} message]} {
    puts "MIC_OSS_VIVADO_FAILED $message"
    exit 1
}
exit 0
