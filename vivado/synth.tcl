# Out-of-context synthesis and implementation of ddr2_bus_monitor on the
# Nexys A7-100T part, for the ddr2_800 config (8 banks, Micron -25E timing).
# Reports go to vivado/reports/<period>/. On Windows, run_synth.ps1 runs both
# periods below and collects the results.
#
#   cd vivado
#   vivado -mode batch -source synth.tcl                 # 3.077 ns: the board's MIG clock
#   vivado -mode batch -source synth.tcl -tclargs 2.5    # DDR2-800 tCK
#
# Achieved Fmax = 1000 / (PERIOD_NS - WNS).

set part      xc7a100tcsg324-1
set period_ns [expr {$argc > 0 ? [lindex $argv 0] : 3.077}]
set here      [file dirname [file normalize [info script]]]
set root      [file normalize "$here/.."]
set out       "$here/reports/$period_ns"
file mkdir $out

create_project -in_memory -part $part
read_vhdl -vhdl2008 [list \
    $root/build/ddr2_800/net_pkg.vhd \
    $root/rtl/petri_monitor.vhd \
    $root/rtl/ddr2_cmd_decode.vhd \
    $root/rtl/ddr2_bus_monitor.vhd]
synth_design -top ddr2_bus_monitor -part $part -mode out_of_context
create_clock -period $period_ns -name clk [get_ports clk]
opt_design
place_design
route_design

report_utilization    -file "$out/utilization.rpt"
report_timing_summary -file "$out/timing.rpt"
set wns  [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set fmax [format %.1f [expr {1000.0 / ($period_ns - $wns)}]]
set line "ddr2_bus_monitor: period=${period_ns} ns  WNS=${wns} ns  Fmax=${fmax} MHz"
puts $line
set f [open "$out/summary.txt" w]
puts $f $line
close $f
