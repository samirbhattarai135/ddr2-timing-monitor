"""Summarises which timing rules the differential traces exercised.

A rule class groups the arcs that differ only by bank: (from command, to
command, scope, symbolic bound). For each class it reports whether some probe
one cycle early was blocked by it, and whether some legal command was issued
with zero slack on it. Classes never hit either way are listed by name.

Usage: coverage.py CONFIG...   (reads build/CONFIG/coverage.json)
"""

import json
import sys
from collections import defaultdict
from pathlib import Path

from net import CustomArc, TimedArc, Transition, build

BUILD = Path(__file__).resolve().parent.parent / "build"


def rule_classes(net):
    g = net.graph
    classes = defaultdict(list)  # key -> dense arc ids
    for dense, e in enumerate(sorted(g.edge_indices())):
        arc = g.get_edge_data_by_index(e)
        src, dst = g.get_edge_endpoints_by_index(e)
        if not isinstance(g[dst], Transition):
            continue
        to = g[dst].command.name
        if isinstance(arc, CustomArc):
            a, b = g[src].coordinate.bank, g[dst].coordinate.bank
            scope = "rank" if None in (a, b) else ("same bank" if a == b else "other bank")
            key = (g[src].command.name, to, scope, net.arc_expr[e], int(arc.time_constraint))
        elif isinstance(arc, TimedArc):
            key = (str(g[src].place_type), to, "pool", "timed", int(arc.lower_bound))
        else:
            continue
        classes[key].append(dense)
    return classes


def report(config):
    net = build(config)
    cov = json.loads((BUILD / config / "coverage.json").read_text())
    probed, exact = set(cov["probe_blocked"]), set(cov["issued_at_bound"])
    classes = rule_classes(net)
    rows = {"both": [], "probe only": [], "bound only": [], "neither": []}
    for key, arcs in sorted(classes.items()):
        p = any(a in probed for a in arcs)
        x = any(a in exact for a in arcs)
        rows["both" if p and x else "probe only" if p else "bound only" if x else "neither"].append(key)
    print(f"| {config} | {len(classes)} | " + " | ".join(str(len(v)) for v in rows.values()) + " |")
    return rows["neither"]


if __name__ == "__main__":
    print("Timing-rule classes (arcs grouped across banks) hit by the traces:\n")
    print("| config | classes | blocked at bound-1 and issued at bound | blocked only | issued only | neither |")
    print("|---|---|---|---|---|---|")
    never = {c: report(c) for c in sys.argv[1:]}
    for config, keys in never.items():
        if keys:
            print(f"\nNever hit in {config}:")
            for frm, to, scope, expr, bound in keys:
                print(f"- {frm} -> {to} ({scope}) >= {expr} = {bound}")
