# Dot-source this file. It puts Vivado's bin folder on PATH if xvhdl/vivado are
# not there already, and returns that folder (or $null if Vivado was on PATH).
function Use-Vivado {
    if (Get-Command vivado -ErrorAction SilentlyContinue) { return $null }
    $bin = Get-ChildItem -Path 'C:\Xilinx\Vivado\*\bin', 'C:\Xilinx\*\Vivado\bin', 'C:\AMDDesignTools\*\Vivado\bin', 'D:\Xilinx\Vivado\*\bin' `
               -Filter vivado.bat -ErrorAction SilentlyContinue |
           Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $bin) { throw 'Vivado not found. Run settings64.bat from your Vivado install, or add its bin folder to PATH.' }
    $env:PATH = "$($bin.DirectoryName);$env:PATH"
    return $bin.DirectoryName
}
