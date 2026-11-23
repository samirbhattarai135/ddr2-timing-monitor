# Runs vivado/synth.tcl (out-of-context place and route of ddr2_bus_monitor on
# the Nexys A7-100T part) at each clock period and collects the results in
# results_windows.txt. Finds Vivado with tools/find_vivado.ps1 if it isn't on PATH.
#
#   powershell -ExecutionPolicy Bypass -File run_synth.ps1
#   powershell -ExecutionPolicy Bypass -File run_synth.ps1 -Periods 3.077,2.5,10
#
# 3.077 ns is the board's recommended MIG clock (Digilent manual, table 3.1.1);
# 2.5 ns is DDR2-800's tCK. Achieved Fmax = 1000 / (period - WNS).

param([double[]]$Periods = @(3.077, 2.5))

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\tools\find_vivado.ps1"
$vbin = Use-Vivado
$log = Join-Path $PSScriptRoot 'results_windows.txt'
"ddr2_bus_monitor synthesis, $(Get-Date -Format s)" | Set-Content -Encoding ascii $log
if ($vbin) { "using Vivado from $vbin" | Add-Content -Encoding ascii $log }
(vivado -version | Select-Object -First 1) | Add-Content -Encoding ascii $log

Push-Location (Join-Path $PSScriptRoot 'vivado')
try {
    foreach ($p in $Periods) {
        $ps = $p.ToString([Globalization.CultureInfo]::InvariantCulture)
        "" | Add-Content -Encoding ascii $log
        "== period $ps ns" | Add-Content -Encoding ascii $log
        $vlog = "vivado_$ps.log"
        vivado -mode batch -nojournal -log $vlog -source synth.tcl -tclargs $ps |
            Select-String 'ddr2_bus_monitor:|^ERROR|CRITICAL WARNING' |
            ForEach-Object { $_.Line } | Add-Content -Encoding ascii $log
        $util = "reports\$ps\utilization.rpt"
        if (Test-Path $util) {
            Select-String -Path $util -Pattern '^\|\s*(Slice LUTs|LUT as Logic|LUT as Memory|Slice Registers|Register as Flip Flop|F7 Muxes|F8 Muxes|Block RAM Tile|DSPs)\s*\|' |
                ForEach-Object { $_.Line } | Add-Content -Encoding ascii $log
        } else {
            "no utilization report: see vivado\$vlog" | Add-Content -Encoding ascii $log
        }
    }
} finally {
    Pop-Location
}
""
Get-Content $log
""
"Send back results_windows.txt and the vivado\reports folder."
