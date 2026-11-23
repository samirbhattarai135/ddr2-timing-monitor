# DDR2 command-bus timing monitor, generated from DRAMPyML

[DRAMPyML](https://github.com/normal-computing-oss/DRAMBench) (Ernst et al., [*Autoformalizing Memory Specifications with Agents*](https://arxiv.org/abs/2605.00058), Normal Computing and Fraunhofer IESE, ICLR 2026 Verif-AI) writes JEDEC DRAM standards as timed Petri nets. These nets are the ground truth for the DRAMBench benchmark. This project does three things with the DDR2 net:

1. **Compiles it into hardware.** A generator turns every place, arc and timing bound of the upstream net into VHDL constant tables. One generic VHDL entity runs those tables at one clock per tCK. With a pin decoder in front, it becomes a monitor that sits on a DDR2 command bus and flags each command the net would reject. No DDR2 rule is written by hand.
2. **Checks the hardware against the model.** The same command traces go through the upstream Python net and through the RTL in `nvc`. The two must agree on every command, down to the set of arcs that blocked it.
3. **Checks the model against the datasheet.** With the net executable on both sides, short command sequences show where the model and the Micron DDR2 datasheet disagree.

**Status:** simulation only. The RTL is meant to be synthesizable, and `vivado/synth.tcl` is ready, but no synthesis tool has read it yet and nothing has run on a board. This repository was built on a machine without Vivado.

## Results

Run `./run_sim.sh` (about 8 minutes on an 8-core laptop, almost all of it in the Python oracle). Every number in this section comes from that script or from `tools/audit.py`.

### The RTL agrees with the net on every command

200 random traces of 150 commands per configuration. Each trace is a random walk on the net: pick a command the net could fire, find the earliest legal cycle, sometimes probe one cycle earlier first (must be illegal), sometimes add a random command (noise). Even seeds favour bank commands; odd seeds weight all commands equally, to reach refresh, power-down and self-refresh.

| Config | Banks | Commands | Legal | Illegal | Cycles | Disagreements |
|---|---|---|---|---|---|---|
| `upstream` (the memspec as published) | 2 | 30,043 | 20,787 | 9,256 | 282,341 | 0 |
| `upstream_8bank` (same timing, 8 banks) | 8 | 30,035 | 21,783 | 8,252 | 194,750 | 0 |
| `ddr2_800` (Micron -25E datasheet timing) | 8 | 30,041 | 22,177 | 7,864 | 133,566 | 0 |

"Disagreements" compares the legal/illegal verdict and the exact set of blocking arcs. The testbench stops on the first difference. To check that it would, three deliberate faults were each caught on the first trace: a corrupted expected verdict, an off-by-one in the timing comparison (`<=` for `<`), and a monitor that skips reset arcs.

The pin decoder (`rtl/ddr2_cmd_decode.vhd`) is checked separately against Table 37 of the datasheet: the 6 bank commands on each of the 8 banks, the 6 rank commands, NOP and DESELECT silent, LOAD MODE and a command on a CKE edge flagged (60 checks).

### Timing-rule coverage

A rule class is one timing bound between two commands, grouped across banks (for example "ACT -> RD, same bank, tRCD - tAL"). A class is covered when a probe one cycle early was blocked by it, or a legal command went out with zero slack on it.

| config | classes | blocked at bound-1 and issued at bound | blocked only | issued only | neither |
|---|---|---|---|---|---|
| upstream | 99 | 69 | 0 | 15 | 15 |
| upstream_8bank | 99 | 69 | 0 | 16 | 14 |
| ddr2_800 | 99 | 70 | 0 | 15 | 14 |

Each class never hit (15, 14 and 14) is one that cannot bind in that net, for these reasons:
- RDA/WRA -> RD, RDA, WR, WRA on the same bank: auto-precharge closes the bank, so the next access waits for ACT plus tRCD, which is longer.
- ACT -> ACT on the same bank at tRRD: tRC is longer. PDX -> RD/RDA at tXARD: the parallel tXARDS arc is longer.
- SRX -> SRE, WR, WRA at tXSNR: SRE needs a REF first and then tRFC; WR needs an ACT first and then tRCD. Both are longer.
- The command bus before PDX and REF: its bound is one cycle, and every legal command before PDX or REF already needs two cycles or more.
- The four-activate pool in `upstream`: with 2 banks it cannot bind (see below).

`tools/coverage.py` lists each class by name.

### Where the model and the datasheet disagree

Source for every datasheet value: Micron *1Gb: x4, x8, x16 DDR2 SDRAM*, 1GbDDR2.pdf Rev. Y 02/14. The Nexys A7 carries the MT47H64M16HR-25 part (Digilent reference manual, section 3.1), and Digilent's MIG settings name the -25E grade.

**The timing values are DDR3-1600's.** `drampyml/timing_params/ddr2.py` and DRAMSys's `MICRON_1Gb_DDR3-1600_8bit_G.json` share 16 parameters: 15 by name, plus tPD, which this table compares with DRAMSys `CKE`. All 16 are equal, and 14 of them differ from DRAMSys's own `MICRON_1Gb_DDR2-800_16bit_H.json`. The self-refresh and power-down exit values (tXSNR 2, tXSRD 200, tXARD 2) do not come from the DDR3 file, whose `XS` is 96 and `XSDLL` 512; they look like DDR2 cycle counts. `nbrOfBanks` is 2; a 1 Gb DDR2 part has 8.

| Parameter | DRAMPyML DDR2 | DRAMSys DDR3-1600 | DRAMSys DDR2-800 | Micron -25E (this repo) |
|---|---|---|---|---|
| nbrOfBanks | 2 | 8 | 8 | 8 |
| tCCD | 4 | 4 | 2 | 2 |
| tFAW | 24 | 24 | 18 | 18 |
| tPD | 3 | 3 | 3 | 3 |
| tRAS | 28 | 28 | 16 | 16 |
| tRC | 38 | 38 | 23 | 22 |
| tRCD | 10 | 10 | 5 | 5 |
| tRFC | 88 | 88 | 51 | 51 |
| tRL | 10 | 10 | 5 | 5 |
| tRP | 10 | 10 | 5 | 5 |
| tRRD | 5 | 5 | 4 | 4 |
| tRTP | 6 | 6 | 3 | 3 |
| tRTRS | 1 | 1 | - | 1 |
| tWL | 8 | 8 | 4 | 4 |
| tWR | 12 | 12 | 6 | 6 |
| tWTR | 6 | 6 | 3 | 3 |
| tXARD | 2 | - | - | 2 |
| tXP | 6 | 6 | 2 | 2 |
| tXSNR | 2 | - | 55 | 55 |
| tXSRD | 200 | - | 200 | 200 |

tRC is 22 in this repo (55 ns, Table 12) and 23 in DRAMSys (57.5 ns, the IDD table). Every other value both columns define is the same.

With 2 banks the four-activate window can never bind: four ACTs need two to the same bank, and tRC = 38 is longer than tFAW = 24. The coverage run agrees: the pool's arc is never hit in `upstream`.

**Rule-level disagreements.** Each row is a command sequence run through the upstream net. The `ddr2_800` rows use datasheet timing, so they test the net's structure, not its numbers. `tools/audit.py` fails if any row stops disagreeing, so an upstream fix shows up at once.

| # | Case | Config | Sequence (cmd@cycle) | Model | Datasheet | Why |
|---|---|---|---|---|---|---|
| 1 | PRE to bank 0 is blocked by an ACT to bank 1 | ddr2_800 | ACT0@0, ACT1@20, PRE0@26 | rejects (ACT[b1] -> PRE[b0] >= 16) | legal | Table 39, p. 76: with bank 1 row-active (tRCD met), PRECHARGE to another bank is allowed. Bank 0 has been open 26 cycles, more than tRAS = 16. |
| 2 | PREA one cycle after an ACT | ddr2_800 | ACT0@0, PREA@1 | accepts | illegal | Bank 0 has been open 1 cycle; tRAS = 16 (Table 12, p. 39). The model enforces tRAS for PRE on that bank but not for PREA. |
| 3 | ACT 5 cycles after PREA | ddr2_800 | ACT0@0, PREA@30, ACT1@35 | accepts | illegal | Note 36, p. 45: tRPA applies after PRECHARGE ALL; for 1 Gb parts tRPA = 15 ns = 6 cycles at -25E (Table 12, p. 39). The model uses tRP = 5. |
| 4 | Second READ 2 cycles after the first, burst length 8 | ddr2_800 | ACT0@0, RD0@5, RD0@7 | accepts | illegal | p. 95: the next READ is issued BL/2 = 4 cycles after the first. The model uses tCCD alone (2); upstream's tCCD = 4 hides this. |
| 5 | Second WRITE 2 cycles after the first, burst length 8 | ddr2_800 | ACT0@0, WR0@5, WR0@7 | accepts | illegal | p. 107: the next WRITE is issued BL/2 = 4 cycles after the first. |
| 6 | READ 2 cycles after fast power-down exit | ddr2_800 | ACT0@0, PDE@1, PDX@4, RD0@6 | rejects (PDX -> RD[b0] >= 6) | legal | tXARD = 2 cycles for fast exit, MR12 = 0 (Table 12, p. 41). The model applies the slow-exit bound to every exit. |
| 7 | READ 6 cycles after slow power-down exit | ddr2_800 | ACT0@0, PDE@1, PDX@4, RD0@10 | accepts | illegal | tXARDS = 8 - AL cycles at -25E for slow exit, MR12 = 1 (Table 12, p. 41). The model's 6 - AL is the DDR2-400/533 value. |
| 8 | ACT 2 cycles after self-refresh exit (upstream timing) | upstream | SRE@0, SRX@10, ACT0@12 | accepts | illegal | tXSNR = tRFC(min) + 10 ns (Table 12, p. 41), 55 cycles at -25E; upstream sets tXSNR = 2. |
| 9 | WRITE 6 cycles after READ (upstream timing) | upstream | ACT0@0, RD0@10, WR0@16 | rejects (RD[b0] -> WR[b0] >= 7; RD[b0] -> WR[b0] >= 7) | legal | WL = RL - 1 (p. 86), so tRL = 10 implies tWL = 9 and the model's own READ-to-WRITE bound tRL + BL/2 + tCK - tWL is 6. Upstream sets tWL = 8, which makes it 7. |

Rows 1 and 2 come from the same line, `CommandTimingConstraint(intra_rank, [ACT], [PRE], p.tRAS)`: it ties PRE on one bank to ACT on any bank, and no rule ties PREA to ACT. Row 1 waits for tRCD on bank 1 so that Table 39 (bank n row-active, command to bank m) covers it. Rows 6 and 7 come from the model listing both `tXARD` and `tXARDS` for every exit, so the larger one always wins. The datasheet has no sentence that says PREA must wait tRAS (row 2); the row rests on tRAS being the ACTIVATE-to-PRECHARGE period and on the model already applying it to PRE.

## How it works

```
upstream DRAMPyML ──► tools/net.py ──► tools/gen_vhdl.py ──► build/<config>/net_pkg.vhd ─┐
  (pinned submodule)   build net,       one table row per                                 │
                       fold timings     arc                                               ▼
                           │                                     rtl/ddr2_cmd_decode.vhd ──► rtl/petri_monitor.vhd
                           │                                       pins ─► transition id      runs the tables
                           ▼                                                                  │
                    tools/oracle.py ──► tools/tracegen.py ──► trace.txt ──► tb/tb_monitor.vhd ◄┘
                    upstream verdict    random walks +        command +     compares every
                    + blocking arcs     probes + noise        expected      verdict
```

- **One clock is one tCK.** Petri-net time and clock cycles are the same thing; the net's timing values are already in tCK.
- **Ages, not timestamps.** Each transition keeps a counter of cycles since it last fired, saturating above the largest bound. A timing arc A -> B blocks B while `age(A) < bound`. A counter that never fired sits at the top, which matches upstream's initial timestamp of -2^32.
- **Token FIFOs only where needed.** Places read by a timed arc (the four-activate pool, the command bus) keep token ages, oldest first. Every other place is a counter.
- **Firing order** follows upstream `fire_transition`: consume tokens (oldest first), then clear reset-arc places, then produce.
- **Illegal commands are flagged and ignored.** The net cannot fire a disabled transition, so the RTL does not either. Both sides stay in step after a violation.
- **Timing is folded once.** `tools/net.py` replaces each symbolic bound with its integer value for the chosen memspec before any use. The oracle's verdict is still upstream `can_fire_transition`; the oracle only adds the list of blocking arcs, and checks that list against the upstream verdict on every command.

## Limits

- The monitor checks exactly what the net checks. The net has only lower bounds, so a missing refresh (tREFI) or a row left open past tRAS(max) goes unflagged.
- Single rank, AL = 0, burst length 8. LOAD MODE is outside the net; the decoder flags it on `unmodelled` and the monitor ignores it.
- The decoder reads CKE, CS#, RAS#, CAS#, WE#, A10 and BA. It does not check row or column addresses.
- Power-down exit mode (MR12) is not tracked, because the net does not distinguish fast and slow exit.
- Simulation only, as above. Fmax and utilization are unknown until `vivado/synth.tcl` runs.

## Reproduce

```bash
git clone --recursive <this repo>
python3.13 -m venv .venv && .venv/bin/pip install rustworkx sympy frozendict
./run_sim.sh                               # differential test, decoder test, coverage
(cd tools && ../.venv/bin/python audit.py) # memspec table and datasheet disagreements
N_TRACES=20 N_COMMANDS=60 ./run_sim.sh     # quick run
```

Needs [nvc](https://github.com/nickg/nvc) (tested with 1.23.1) and Python 3.13. Upstream is pinned at commit `4ab21b5`.

On Windows with Vivado: `powershell -ExecutionPolicy Bypass -File run_synth.ps1` places and routes at 3.077 ns (the board's MIG clock) and 2.5 ns (DDR2-800 tCK) and writes `results_windows.txt`. Elsewhere: `cd vivado && vivado -mode batch -source synth.tcl [-tclargs PERIOD_NS]`.

## Files

| File | Purpose |
|---|---|
| `third_party/DRAMBench` | Upstream DRAMPyML, git submodule pinned at `4ab21b5` |
| `tools/net.py` | Builds the upstream net for a config and folds its timings; holds the three memspecs |
| `tools/oracle.py` | Replays a trace through the upstream net; verdict plus blocking arcs |
| `tools/gen_vhdl.py` | Writes `net_pkg.vhd` (arc, place and command tables) and `arcs.tsv` (arc names) |
| `tools/tracegen.py` | Random-walk traces with expected verdicts, and rule coverage |
| `tools/coverage.py` | Coverage summary per config |
| `tools/audit.py` | Memspec provenance table and the datasheet disagreement cases |
| `rtl/petri_monitor.vhd` | Generic executor for the generated tables |
| `rtl/ddr2_cmd_decode.vhd` | DDR2 pins to transition id, per datasheet Table 37 |
| `rtl/ddr2_bus_monitor.vhd` | Decoder plus monitor: pins in, violation and first blocking arc out |
| `tb/tb_monitor.vhd` | Differential testbench, reads `trace.txt` |
| `tb/tb_decode.vhd` | Decoder testbench |
| `build/<config>/net_pkg.vhd`, `arcs.tsv` | Generated tables, kept in git so Vivado needs no Python |
| `vivado/synth.tcl` | Out-of-context place and route on the Nexys A7-100T part (not yet run) |
| `run_synth.ps1`, `tools/find_vivado.ps1` | Windows: runs `synth.tcl` at each period and collects `results_windows.txt` |
| `run_sim.sh` | Runs everything above |

## Related work

[DRAMDelta](https://github.com/agocharbhatia/dramdelta) also builds on DRAMBench. It mutates protocol models in software and finds the shortest command sequence that tells two models apart. This project takes the ground-truth net to RTL and checks the net itself against a datasheet.

## License

Apache-2.0, the same as upstream DRAMPyML.
