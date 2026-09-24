"""Iteration harness for one mission at a time: fly variants, print what
happened, and trace the flight when it goes wrong."""
import math, sys
import det_math as dm, runner, ships, sim, vm as vmod

U = runner.load_universe()


def fly(spec, source, ship=None, trace_every=0):
    m = runner.Mission(spec)
    w = m.build_world(U)
    prof = ships.stock(ship or m.stock_ship_id).to_profile()
    prog = vmod.assemble(source)
    if prog.errors:
        return None, prog, None, None, m
    r = runner.SimRunner()
    r.setup(m, w, prof, prog, seed=0)
    trace = []
    n = 0
    while not r.finished and n < runner.MAX_STEPS:
        r.step(); n += 1
        if trace_every and n % trace_every == 0:
            b = r.bus
            trace.append((b.read("T"), b.read("ALT"), b.read("APO"), b.read("PERI"),
                          b.read("VEL"), b.read("VVEL"), r.state.fuel, b.read("SOI"),
                          b.read("TGTD"), r.vm.pc))
    if not r.finished:
        r._fail("cut short", "")
    return r.result, prog, prof, trace, m


def show(name, res, prof, m):
    if res is None:
        print(f"{name}: ASSEMBLY ERRORS")
        return False
    tag = "ok " if res.success else "XX "
    left = prof.fuel_capacity * m.start_fuel_fraction - res.fuel_used
    print(f"{tag}{name:34} {res.outcome[:40]:42} fuel {res.fuel_used:8.1f} "
          f"(left {left:7.1f})  T+{res.elapsed:9.1f}  instr {res.instruction_count:3d}")
    if not res.success and res.outcome_detail:
        print(f"      {res.outcome_detail}")
    return res.success


def trace_table(trace, cols=("T", "ALT", "APO", "PERI", "VEL", "VVEL", "FUEL", "SOI", "TGTD", "pc")):
    print("   " + " ".join(f"{c:>10}" for c in cols))
    for row in trace:
        print("   " + " ".join(
            ("%10.1f" % v) if not math.isinf(v) else f"{'inf':>10}" for v in row))
