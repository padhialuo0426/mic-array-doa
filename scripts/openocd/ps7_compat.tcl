# Source the generated ps7_init.tcl BEFORE this adapter, so these bounded
# OpenOCD implementations replace the XSCT-specific helper procedures.
proc mwr {args} {
    mww phys [lindex $args end-1] [lindex $args end]
}
proc mask_write {addr mask value} {
    set old [lindex [read_memory $addr 32 1 phys] 0]
    mww phys $addr [expr {($old & ~$mask) | ($value & $mask)}]
}
proc mask_poll {addr mask} {
    for {set i 0} {$i<1000} {incr i} {
        set value [lindex [read_memory $addr 32 1 phys] 0]
        if {($value & $mask)!=0} {return}
        sleep 1
    }
    error "PS7 initialization timeout: address=$addr mask=$mask"
}
proc mask_delay {addr milliseconds} {sleep $milliseconds}
proc ps_version {} {
    return [expr {[lindex [read_memory 0xf8007080 32 1 phys] 0] >> 28}]
}
proc configparams {args} {return 0}
