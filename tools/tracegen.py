"""Generates differential test traces with the oracle's verdict on every command.

Each trace is a random walk on the upstream net (even seeds favour bank
commands, odd seeds pick every enabled command equally often, which reaches
the refresh, power-down and self-refresh rules):
  - pick a command (weighted) that the net could fire if timing were ignored,
  - find the earliest cycle at which it is legal,
  - sometimes first issue it one cycle early (a boundary probe: must be illegal),
  - issue it at the earliest cycle, or a few cycles later,
  - sometimes insert a random command at the next free cycle (noise; whatever
    the net says about it is the expected verdict).
Every command, legal or not, goes through oracle.step, which fires only legal
ones, so the walk and the expected verdicts can never disagree.

Also records rule coverage: for every timing arc, whether a probe was blocked by
it at bound - 1 and whether a legal command was issued exactly at its bound.

Usage: tracegen.py CONFIG OUT_DIR [N_TRACES] [COMMANDS_PER_TRACE] [SEED]
Writes OUT_DIR/trace.txt and OUT_DIR/coverage.json.
"""

import json
import random
import sys
from multiprocessing import Pool
from pathlib import Path

from net import CustomArc, TimedArc, build, places, transitions  # sets up the upstream path
from drampyml.algorithms.state import current_state, restore_state  # noqa: E402
from oracle import Command, step

WEIGHTS = {"ACT": 4, "RD": 3, "WR": 3, "RDA": 1, "WRA": 1, "PRE": 2, "PREA": 0.5,
           "REF": 0.5, "PDE": 0.3, "PDX": 1, "SRE": 0.2, "SRX": 1}
P_PROBE, P_NOISE, P_SLACK = 0.5, 0.1, 0.3
MAX_SCAN = 400  # longest bound in any config is tXSRD = 200

_net = None
_initial = None


def _init(config):
    global _net, _initial
    _net = build(config)
    _initial = current_state(_net)


def _earliest(net, t, after):
    saved = net.current_time
    found = None
    for time in range(after, after + MAX_SCAN):
        net.current_time = time
        if net.can_fire_transition(t):
            found = time
            break
    net.current_time = saved
    return found


def _binding_arcs(net, t, now):
    """Timing arcs into t that would be satisfied with zero slack at cycle `now`."""
    g, out = net.graph, []
    for e in g.in_edge_indices(t):
        arc = g.get_edge_data_by_index(e)
        if isinstance(arc, CustomArc) and now - arc.timestamp == int(arc.time_constraint):
            out.append(e)
        elif isinstance(arc, TimedArc):
            # Binding iff enough tokens are ready now but not one cycle earlier.
            src, _ = g.get_edge_endpoints_by_index(e)
            ages = [now - tok.timestamp for tok in g[src].tokens]
            bound = int(arc.lower_bound)
            ready_now = sum(a >= bound for a in ages)
            ready_before = sum(a - 1 >= bound for a in ages)
            if ready_now >= arc.weight > ready_before:
                out.append(e)
    return out


def _check_safe(net, caps):
    for p, cap in caps.items():
        assert len(net.graph[p].tokens) <= cap, f"place {p} holds more than {cap} tokens"


def _one_trace(args):
    seed, n_commands = args
    rng = random.Random(seed)
    net = _net
    restore_state(net, _initial)
    trans = transitions(net)
    tid = {t.index: i for i, t in enumerate(trans)}
    caps = {p: max(1, len(net.graph[p].tokens)) for p in places(net)}
    edge_ids = {e: i for i, e in enumerate(sorted(net.graph.edge_indices()))}
    lines, probe_hits, exact_hits = ["R"], set(), set()
    last = -1

    def emit(time, t):
        nonlocal last
        binding = _binding_arcs(net, t, time)
        v = step(net, Command(time, t))
        _check_safe(net, caps)
        arcs = sorted(edge_ids[e] for e in v.blocking_arcs)
        lines.append(f"C {time} {tid[t]} {int(v.legal)} {len(arcs)} " + " ".join(map(str, arcs)))
        last = time
        return v, [edge_ids[e] for e in binding]

    while len(lines) - 1 < n_commands:
        if rng.random() < P_NOISE:
            emit(last + 1, rng.choice(trans).index)
            continue
        net.ignore_timing_constraints = True
        candidates = [t for t in trans if net.can_fire_transition(t.index)]
        net.ignore_timing_constraints = False
        weights = [WEIGHTS[t.command] if seed % 2 == 0 else 1 for t in candidates]
        pick = rng.choices(candidates, weights)[0]
        earliest = _earliest(net, pick.index, last + 1)
        if earliest is None:
            continue
        if earliest - 1 > last and rng.random() < P_PROBE:
            v, _ = emit(earliest - 1, pick.index)
            assert not v.legal, "a probe one cycle before the earliest legal time passed"
            probe_hits.update(edge_ids[e] for e in v.blocking_arcs)
        slack = rng.randint(1, 5) if rng.random() < P_SLACK else 0
        v, binding = emit(earliest + slack, pick.index)
        assert v.legal, "a command at or after its earliest legal time failed"
        if slack == 0:
            exact_hits.update(binding)
    return lines, probe_hits, exact_hits


def main(config, out_dir, n_traces=200, n_commands=150, seed=1):
    out_dir.mkdir(parents=True, exist_ok=True)
    jobs = [(seed * 100_003 + i, n_commands) for i in range(n_traces)]
    with Pool(initializer=_init, initargs=(config,)) as pool:
        results = pool.map(_one_trace, jobs)
    probe, exact = set(), set()
    with open(out_dir / "trace.txt", "w") as f:
        for lines, p, e in results:
            f.write("\n".join(lines) + "\n")
            probe |= p
            exact |= e
    (out_dir / "coverage.json").write_text(json.dumps(
        {"probe_blocked": sorted(probe), "issued_at_bound": sorted(exact)}))


if __name__ == "__main__":
    a = sys.argv
    main(a[1], Path(a[2]), *(int(x) for x in a[3:6]))
