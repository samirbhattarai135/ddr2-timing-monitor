#!/usr/bin/env bash
# Differential test: for each memspec config, generate the VHDL net tables and
# a trace set from the upstream DRAMPyML net, then require the RTL monitor to
# reproduce the net's verdict on every command, arc for arc.
#
# Needs nvc (https://github.com/nickg/nvc) and the venv from README.md.
# N_TRACES and N_COMMANDS shrink the run (defaults 200 x 150 per config, about
# 8 minutes on an 8-core laptop, almost all of it in the Python oracle).
set -euo pipefail
cd "$(dirname "$0")"

PY=.venv/bin/python
N_TRACES=${N_TRACES:-200}
N_COMMANDS=${N_COMMANDS:-150}
CONFIGS=${CONFIGS:-"upstream upstream_8bank ddr2_800"}

for cfg in $CONFIGS; do
    out=build/$cfg
    (cd tools && ../$PY gen_vhdl.py "$cfg" "../$out" && ../$PY tracegen.py "$cfg" "../$out" "$N_TRACES" "$N_COMMANDS" 1)
    rm -rf "work/$cfg" && mkdir -p "work/$cfg"
    nvc --std=2008 --work="work/$cfg/work" -a "$out/net_pkg.vhd" rtl/petri_monitor.vhd tb/tb_monitor.vhd
    log=$(nvc --std=2008 --work="work/$cfg/work" -e tb_monitor -gTRACE_FILE="$out/trace.txt" -r 2>&1) \
        || { echo "$log" | grep -m3 -E "Failure|MISMATCH"; exit 1; }
    grep -o "RESULT.*" <<<"$log"
    if [[ $cfg == ddr2_800 ]]; then
        nvc --std=2008 --work="work/$cfg/work" -a rtl/ddr2_cmd_decode.vhd tb/tb_decode.vhd
        log=$(nvc --std=2008 --work="work/$cfg/work" -e tb_decode -r 2>&1) || { echo "$log"; exit 1; }
        grep -o "RESULT.*" <<<"$log"
    fi
done

echo
(cd tools && ../$PY coverage.py $CONFIGS)
