"""Builds the upstream DRAMPyML DDR2 Petri net for one named configuration.

The net itself is never re-implemented here: it comes from
third_party/DRAMBench (pinned submodule). This module only chooses the memspec
and folds every symbolic timing into an integer once, so the oracle does not
pay for a sympy substitution on every evaluation.
"""

import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "third_party" / "DRAMBench"))

from sympy import Integer  # noqa: E402

from drampyml.components.petri_net import (  # noqa: E402
    Arc,
    CustomArc,
    InhibitorArc,
    PetriNet,
    Place,
    ResetArc,
    TimedArc,
    Transition,
)
from drampyml.memspecs.ddr2 import DDR2 as UPSTREAM_DDR2  # noqa: E402
from drampyml.standards.ddr2 import Command, Coordinate, create_petri_net  # noqa: E402

RANK_COMMANDS = {"REF", "PREA", "PDE", "PDX", "SRE", "SRX"}

# Micron MT47H64M16HR-25E (the Nexys A7 part), DDR2-800 CL5, tCK = 2.5 ns.
# Cycles are ns / 2.5 rounded up, per Micron 1Gb DDR2 datasheet Rev. Y,
# Table 12 (pp. 39-41) and p. 86 (RL = AL + CL, WL = RL - 1). They agree with
# DRAMSys configs/memspec/MICRON_1Gb_DDR2-800_16bit_H.json except tRC (22 here
# from Table 12; DRAMSys uses 23 from the IDD table). See docs/audit.md.
DDR2_800_DATASHEET = {
    "nbrOfRanks": 1, "nbrOfBanks": 8, "defaultBurstLength": 8, "dataRate": 2,
    "tCK": 1, "tAL": 0, "tRL": 5, "tWL": 4,
    "tRCD": 5, "tRP": 5, "tRAS": 16, "tRC": 22, "tRRD": 4, "tFAW": 18,
    "tWR": 6, "tWTR": 3, "tRTP": 3, "tCCD": 2, "tRFC": 51,
    "tXSNR": 55, "tXSRD": 200, "tXP": 2, "tXARD": 2, "tPD": 3, "tRTRS": 1,
}

CONFIGS = {
    # Exactly the upstream memspec.
    "upstream": dict(UPSTREAM_DDR2),
    # Upstream timing, but the 8 banks a 1 Gb DDR2 part has.
    "upstream_8bank": {**UPSTREAM_DDR2, "nbrOfBanks": 8},
    # Upstream net, datasheet timing for the board's part.
    "ddr2_800": DDR2_800_DATASHEET,
}


@dataclass(frozen=True)
class TransitionInfo:
    index: int
    command: str
    bank: int | None  # None for rank-level commands


def build(config: str) -> PetriNet:
    """Returns the upstream net for `config` with every timing folded to an int."""
    memspec = CONFIGS[config]
    net = create_petri_net(memspec)
    graph = net.graph
    net.arc_expr = {}  # edge index -> symbolic timing before folding, for reports
    for edge_index in graph.edge_indices():
        edge = graph.get_edge_data_by_index(edge_index)
        if isinstance(edge, CustomArc):
            net.arc_expr[edge_index] = str(edge.time_constraint)
            edge.time_constraint = Integer(int(edge.time_constraint.subs(memspec)))
        elif isinstance(edge, TimedArc):
            folded = TimedArc(edge.weight, Integer(int(edge.lower_bound.subs(memspec))))
            graph.update_edge_by_index(edge_index, folded)
    net.memspec = {}  # every expression is now a constant
    net.evaluate()
    return net


def transitions(net: PetriNet) -> list[TransitionInfo]:
    graph = net.graph
    out = []
    for index in sorted(graph.filter_nodes(lambda n: isinstance(n, Transition))):
        node = graph[index]
        out.append(TransitionInfo(index, node.command.name, node.coordinate.bank))
    return out


def places(net: PetriNet) -> list[int]:
    return sorted(net.graph.filter_nodes(lambda n: isinstance(n, Place)))


def transition_index(net: PetriNet, command: str, bank: int | None) -> int:
    coordinate = Coordinate(rank=0, bank=None if command in RANK_COMMANDS else bank)
    return net.transitions[(coordinate, Command[command])][0]


def describe_arc(net: PetriNet, edge_index: int) -> str:
    """Human-readable name of one arc, e.g. 'ACT[b0] -> RD[b0] >= 10'."""
    graph = net.graph
    src, dst = graph.get_edge_endpoints_by_index(edge_index)
    edge = graph.get_edge_data_by_index(edge_index)

    def name(i):
        node = graph[i]
        if isinstance(node, Transition):
            b = node.coordinate.bank
            return f"{node.command.name}" + ("" if b is None else f"[b{b}]")
        b = node.coordinate.bank
        return f"{node.place_type}" + ("" if b is None else f"[b{b}]")

    kind = type(edge).__name__
    if isinstance(edge, CustomArc):
        return f"{name(src)} -> {name(dst)} >= {edge.time_constraint}"
    if isinstance(edge, TimedArc):
        return f"{name(src)} -> {name(dst)} timed >= {edge.lower_bound}"
    return f"{name(src)} -> {name(dst)} {kind}"


__all__ = [
    "Arc", "CustomArc", "InhibitorArc", "ResetArc", "TimedArc", "Place", "Transition",
    "CONFIGS", "build", "transitions", "places", "transition_index", "describe_arc",
    "TransitionInfo",
]
