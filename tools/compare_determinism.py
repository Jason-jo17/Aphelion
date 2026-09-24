#!/usr/bin/env python3
"""Compares the determinism reports from each operating system.

AC1 promises that the same ship, program and seed produce the identical
trajectory everywhere. This is what checks it: the same fifteen flights, run on
Windows, macOS and Linux, compared field by field. Any difference is printed
with the mission and the field that moved, because "the hashes differ" on its
own tells you nothing about which part of the physics drifted.
"""

import json
import sys

FIELDS = ["success", "ticks", "fuel_used", "instructions", "stars", "state_hash"]


def load(path):
    with open(path) as f:
        return json.load(f)


def main(paths):
    if len(paths) < 2:
        print(f"need at least two reports to compare, got {len(paths)}")
        return 1

    reports = {}
    for p in paths:
        r = load(p)
        reports[r.get("platform", p)] = r
        print(f"  {r.get('platform', '?'):10} godot {r.get('godot', '?'):10} "
              f"{len(r.get('missions', []))} missions   ({p})")
    print()

    platforms = sorted(reports)
    baseline_name = platforms[0]
    baseline = {m["id"]: m for m in reports[baseline_name]["missions"]}

    mismatches = 0
    for name in platforms[1:]:
        other = {m["id"]: m for m in reports[name]["missions"]}

        only_base = sorted(set(baseline) - set(other))
        only_other = sorted(set(other) - set(baseline))
        for mid in only_base:
            print(f"MISSING  {mid} ran on {baseline_name} but not {name}")
            mismatches += 1
        for mid in only_other:
            print(f"MISSING  {mid} ran on {name} but not {baseline_name}")
            mismatches += 1

        for mid in sorted(set(baseline) & set(other)):
            for field in FIELDS:
                a, b = baseline[mid].get(field), other[mid].get(field)
                if a != b:
                    print(f"DIFFERS  {mid}.{field}")
                    print(f"           {baseline_name:10} {a}")
                    print(f"           {name:10} {b}")
                    mismatches += 1

    n = len(baseline)
    if mismatches:
        print(f"\n{mismatches} difference(s) across {len(platforms)} platforms.")
        print("The simulation is not deterministic across operating systems, which")
        print("breaks the leaderboard and every exported solution file. The usual")
        print("cause is a transcendental function reaching libm instead of DetMath.")
        return 1

    print(f"{n} missions produced identical results on all {len(platforms)} platforms.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
