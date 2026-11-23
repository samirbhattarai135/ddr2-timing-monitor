"""Replays a command trace through the upstream DRAMPyML Petri net.

Policy for an illegal command (shared with the RTL monitor): flag it and do not
fire it. The net cannot fire a disabled transition, so this is the only policy
under which both sides stay in step after a violation.

The legal/illegal verdict is the upstream `can_fire_transition`. The set of
blocking arcs is recomputed edge by edge only to name the reason, and is checked
against the upstream verdict on every command.
"""

from dataclasses import dataclass

from net import Arc, CustomArc, InhibitorArc, PetriNet, TimedArc


@dataclass(frozen=True)
class Command:
    time: int
    transition: int  # node index in the net


@dataclass(frozen=True)
class Verdict:
    legal: bool
    blocking_arcs: frozenset[int]  # edge indices


def _blocking_arcs(net: PetriNet, transition: int) -> frozenset[int]:
    graph = net.graph
    now = net.current_time
    blocking = set()
    for edge_index in graph.in_edge_indices(transition):
        src, _ = graph.get_edge_endpoints_by_index(edge_index)
        edge = graph.get_edge_data_by_index(edge_index)
        if isinstance(edge, CustomArc):
            if edge.active(now, net.memspec):
                blocking.add(edge_index)
            continue
        tokens = graph[src].tokens
        if isinstance(edge, TimedArc):
            ready = sum(1 for t in tokens if edge.lower_bound <= now - t.timestamp)
            if ready < edge.weight:
                blocking.add(edge_index)
        elif isinstance(edge, Arc) and len(tokens) < edge.weight:
            blocking.add(edge_index)
        elif isinstance(edge, InhibitorArc) and len(tokens) >= edge.weight:
            blocking.add(edge_index)
    return frozenset(blocking)


def step(net: PetriNet, command: Command) -> Verdict:
    """Applies one command at its time. Times must not decrease."""
    if command.time < net.current_time:
        raise ValueError(f"time went backwards: {command.time} < {net.current_time}")
    net.current_time = command.time
    net.evaluate()
    legal = net.can_fire_transition(command.transition)
    blocking = _blocking_arcs(net, command.transition)
    if legal == bool(blocking):
        raise AssertionError(
            f"reason set disagrees with upstream verdict at t={command.time}: "
            f"legal={legal}, blocking={sorted(blocking)}"
        )
    if legal:
        net.fire_transition(command.transition)
    return Verdict(legal, blocking)


def replay(net: PetriNet, trace: list[Command]) -> list[Verdict]:
    return [step(net, c) for c in trace]
