"""Runs each audit case through the upstream net and prints a markdown table.

Every case is a short command sequence. The model's verdict on the last command
comes from the oracle (upstream can_fire_transition); the datasheet verdict and
its source are written here by hand from the Micron 1Gb DDR2 datasheet
(Rev. Y, 1GbDDR2.pdf). The script fails if the model's verdict ever stops
disagreeing with the datasheet, so a fixed upstream model shows up at once.
"""

from dataclasses import dataclass

from net import CONFIGS, build, describe_arc, transition_index
from oracle import Command, replay


@dataclass(frozen=True)
class Case:
    title: str
    config: str
    sequence: tuple  # (cycle, command, bank or None); the last one is judged
    datasheet_legal: bool
    source: str


CASES = [
    Case("PRE to bank 0 is blocked by an ACT to bank 1",
         "ddr2_800", ((0, "ACT", 0), (20, "ACT", 1), (26, "PRE", 0)), True,
         "Table 39, p. 76: with bank 1 row-active (tRCD met), PRECHARGE to another "
         "bank is allowed. Bank 0 has been open 26 cycles, more than tRAS = 16."),
    Case("PREA one cycle after an ACT",
         "ddr2_800", ((0, "ACT", 0), (1, "PREA", None)), False,
         "Bank 0 has been open 1 cycle; tRAS = 16 (Table 12, p. 39). The model "
         "enforces tRAS for PRE on that bank but not for PREA."),
    Case("ACT 5 cycles after PREA",
         "ddr2_800", ((0, "ACT", 0), (30, "PREA", None), (35, "ACT", 1)), False,
         "Note 36, p. 45: tRPA applies after PRECHARGE ALL; for 1 Gb parts "
         "tRPA = 15 ns = 6 cycles at -25E (Table 12, p. 39). The model uses tRP = 5."),
    Case("Second READ 2 cycles after the first, burst length 8",
         "ddr2_800", ((0, "ACT", 0), (5, "RD", 0), (7, "RD", 0)), False,
         "p. 95: the next READ is issued BL/2 = 4 cycles after the first. The "
         "model uses tCCD alone (2); upstream's tCCD = 4 hides this."),
    Case("Second WRITE 2 cycles after the first, burst length 8",
         "ddr2_800", ((0, "ACT", 0), (5, "WR", 0), (7, "WR", 0)), False,
         "p. 107: the next WRITE is issued BL/2 = 4 cycles after the first."),
    Case("READ 2 cycles after fast power-down exit",
         "ddr2_800", ((0, "ACT", 0), (1, "PDE", None), (4, "PDX", None), (6, "RD", 0)), True,
         "tXARD = 2 cycles for fast exit, MR12 = 0 (Table 12, p. 41). The model "
         "applies the slow-exit bound to every exit."),
    Case("READ 6 cycles after slow power-down exit",
         "ddr2_800", ((0, "ACT", 0), (1, "PDE", None), (4, "PDX", None), (10, "RD", 0)), False,
         "tXARDS = 8 - AL cycles at -25E for slow exit, MR12 = 1 (Table 12, "
         "p. 41). The model's 6 - AL is the DDR2-400/533 value."),
    Case("ACT 2 cycles after self-refresh exit (upstream timing)",
         "upstream", ((0, "SRE", None), (10, "SRX", None), (12, "ACT", 0)), False,
         "tXSNR = tRFC(min) + 10 ns (Table 12, p. 41), 55 cycles at -25E; "
         "upstream sets tXSNR = 2."),
    Case("WRITE 6 cycles after READ (upstream timing)",
         "upstream", ((0, "ACT", 0), (10, "RD", 0), (16, "WR", 0)), True,
         "WL = RL - 1 (p. 86), so tRL = 10 implies tWL = 9 and the model's own "
         "READ-to-WRITE bound tRL + BL/2 + tCK - tWL is 6. Upstream sets tWL = 8, "
         "which makes it 7."),
]


# DRAMSys configs/memspec, commit b43b4da (github.com/tukl-msd/DRAMSys), in cycles.
DRAMSYS_DDR3_1600 = {"tCCD": 4, "tFAW": 24, "tRAS": 28, "tRC": 38, "tRCD": 10, "tRFC": 88,
                     "tRL": 10, "tRP": 10, "tRRD": 5, "tRTP": 6, "tWL": 8, "tWR": 12,
                     "tWTR": 6, "tXP": 6, "tRTRS": 1, "tPD": 3}  # tPD is DRAMSys "CKE"
DRAMSYS_DDR2_800 = {"tCCD": 2, "tFAW": 18, "tRAS": 16, "tRC": 23, "tRCD": 5, "tRFC": 51,
                    "tRL": 5, "tRP": 5, "tRRD": 4, "tRTP": 3, "tWL": 4, "tWR": 6,
                    "tWTR": 3, "tXP": 2, "tPD": 3, "tXSNR": 55, "tXSRD": 200}  # XS, XSDLL


def memspec_table():
    upstream, sheet = CONFIGS["upstream"], CONFIGS["ddr2_800"]
    print("| Parameter | DRAMPyML DDR2 | DRAMSys DDR3-1600 | DRAMSys DDR2-800 | Micron -25E (this repo) |")
    print("|---|---|---|---|---|")
    same = differ_from_ddr2 = 0
    for k in sorted(set(DRAMSYS_DDR3_1600) | {"tXSNR", "tXSRD", "tXARD", "nbrOfBanks"}):
        d3, d2 = DRAMSYS_DDR3_1600.get(k, "-"), DRAMSYS_DDR2_800.get(k, "-")
        if k == "nbrOfBanks":
            d3 = d2 = 8
        same += d3 == upstream[k]
        differ_from_ddr2 += k in DRAMSYS_DDR3_1600 and d2 != "-" and d2 != upstream[k]
        print(f"| {k} | {upstream[k]} | {d3} | {d2} | {sheet[k]} |")
    print(f"\nAll {same} parameters DRAMPyML shares with the DDR3-1600 file are equal "
          f"(tPD compared with DRAMSys CKE); {differ_from_ddr2} of them differ from "
          f"DRAMSys's own DDR2-800 file.")


def judge(case):
    net = build(case.config)
    trace = [Command(t, transition_index(net, c, b)) for t, c, b in case.sequence]
    verdicts = replay(net, trace)
    for cmd, v in zip(case.sequence[:-1], verdicts[:-1]):
        assert v.legal, f"{case.title}: setup command {cmd} was rejected"
    last = verdicts[-1]
    why = "; ".join(describe_arc(net, e) for e in sorted(last.blocking_arcs))
    return last.legal, why


def seq_text(sequence):
    return ", ".join(f"{c}{'' if b is None else b}@{t}" for t, c, b in sequence)


def main():
    print("| # | Case | Config | Sequence (cmd@cycle) | Model | Datasheet | Why |")
    print("|---|---|---|---|---|---|---|")
    for i, case in enumerate(CASES, 1):
        legal, blocked_by = judge(case)
        assert legal != case.datasheet_legal, f"case {i} now agrees with the datasheet"
        model = "accepts" if legal else f"rejects ({blocked_by})"
        sheet = "legal" if case.datasheet_legal else "illegal"
        print(f"| {i} | {case.title} | {case.config} | {seq_text(case.sequence)} | {model} | {sheet} | {case.source} |")


if __name__ == "__main__":
    memspec_table()
    print()
    main()
