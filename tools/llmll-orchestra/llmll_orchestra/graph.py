"""
graph.py — Topological sorting of holes by their dependency graph.

Handles cycle_warning holes by placing them last (cycles have been broken
by the compiler, but the back-edge removal means they may not have all
dependencies satisfied yet).
"""

from __future__ import annotations

from collections import defaultdict, deque
from typing import Sequence

from .compiler import HoleEntry


def topo_sort(holes: Sequence[HoleEntry]) -> list[HoleEntry]:
    """
    Topologically sort holes by their dependency graph.

    Returns holes in an order where each hole's dependencies are filled
    before it. Holes with cycle_warning=True are placed at the end.

    Uses Kahn's algorithm (BFS).
    """
    # Build pointer → HoleEntry index
    pointer_to_idx: dict[str, int] = {}
    for i, h in enumerate(holes):
        pointer_to_idx[h.pointer] = i

    n = len(holes)
    adj: dict[int, list[int]] = defaultdict(list)    # dep_idx → [dependent_idx]
    in_degree: dict[int, int] = {i: 0 for i in range(n)}

    for i, h in enumerate(holes):
        for dep in h.depends_on:
            dep_idx = pointer_to_idx.get(dep.pointer)
            if dep_idx is not None:
                adj[dep_idx].append(i)
                in_degree[i] += 1

    # Kahn's BFS — separate normal and cycle-warned holes
    queue: deque[int] = deque()
    for i in range(n):
        if in_degree[i] == 0 and not holes[i].cycle_warning:
            queue.append(i)

    result: list[HoleEntry] = []
    visited = set()

    while queue:
        idx = queue.popleft()
        visited.add(idx)
        result.append(holes[idx])
        for neighbor in adj[idx]:
            in_degree[neighbor] -= 1
            if in_degree[neighbor] == 0 and not holes[neighbor].cycle_warning:
                queue.append(neighbor)

    # Append cycle-warned holes at the end (compiler broke the cycles,
    # but they need special attention from the orchestrator)
    for i in range(n):
        if i not in visited:
            result.append(holes[i])

    return result


def scheduling_tiers(holes: Sequence[HoleEntry]) -> list[list[HoleEntry]]:
    """
    Group holes into scheduling tiers for parallel execution.

    Tier 0 = holes with no dependencies (can run in parallel).
    Tier 1 = holes whose deps are all in tier 0, etc.
    Cycle-warned holes are in the last tier.
    """
    sorted_holes = topo_sort(holes)
    pointer_to_tier: dict[str, int] = {}
    tiers: list[list[HoleEntry]] = []

    for h in sorted_holes:
        if h.cycle_warning:
            tier = len(tiers)  # Will be placed in last tier
        elif not h.depends_on:
            tier = 0
        else:
            dep_tiers = [
                pointer_to_tier.get(d.pointer, 0)
                for d in h.depends_on
            ]
            tier = max(dep_tiers) + 1

        pointer_to_tier[h.pointer] = tier

        while len(tiers) <= tier:
            tiers.append([])
        tiers[tier].append(h)

    return tiers
