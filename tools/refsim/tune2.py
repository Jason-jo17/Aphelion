"""Second pass: fix a physically sane drag model, then search the ascent
profile space to learn what an optimal solution costs. That number is what the
3-star fuel threshold has to be built from."""
import math, sys
import det_math as dm, sim, universe as U
from tune_ascent import build_world, fly

ATMO = dict(rho0=0.8, H=6000.0, height=70000.0)
CD = 0.35


def sparrow(thrust, isp, fuel, dry=1350.0, area=2.0):
    return sim.ShipProfile(dry_mass=dry, fuel_capacity=fuel, max_thrust=thrust,
                           isp=isp, max_torque=4000.0, inertia=14000.0,
                           drag_coefficient=CD, drag_area=area)


def best_ascent(prof, w, target_alt=100000.0):
    """Grid-search the pitch programme; returns (dv_left, params, result)."""
    best = None
    for ts in (500.0, 1000.0, 2000.0, 4000.0):
        for te in (25000.0, 32000.0, 40000.0, 50000.0, 60000.0):
            r = fly(prof, w, ts, te, target_alt)
            if r.get("ok"):
                key = r["dv_left"]
                if best is None or key > best[0]:
                    best = (key, (ts, te), r)
    return best


if __name__ == "__main__":
    w = build_world(ATMO["rho0"], ATMO["H"], ATMO["height"])
    print(f"atmosphere: rho0={ATMO['rho0']} H={ATMO['H']:.0f} top={ATMO['height']/1000:.0f} km, Cd={CD}")
    print()
    print(f"{'engine':>22} {'fuel':>6} {'wet':>6} {'TWR':>5} {'dv':>6} "
          f"{'best turn':>14} {'orbit':>20} {'dv left':>8} {'fuel left':>9} {'T+':>6}")
    print("-" * 118)
    rows = []
    for thrust, isp, fuel in [
        (90000.0, 290.0, 3200.0),
        (110000.0, 300.0, 3600.0),
        (120000.0, 300.0, 4000.0),
        (120000.0, 310.0, 4000.0),
        (135000.0, 305.0, 4200.0),
    ]:
        prof = sparrow(thrust, isp, fuel)
        b = best_ascent(prof, w)
        if b is None:
            print(f"{thrust/1000:19.0f}kN {fuel:6.0f} {prof.dry_mass+fuel:6.0f} "
                  f"{prof.twr(9.0):5.2f} {prof.delta_v():6.0f}  no profile reaches orbit")
            continue
        dvl, (ts, te), r = b
        rows.append((thrust, isp, fuel, dvl, r))
        print(f"{thrust/1000:16.0f}kN/{isp:3.0f}s {fuel:6.0f} {prof.dry_mass+fuel:6.0f} "
              f"{prof.twr(9.0):5.2f} {prof.delta_v():6.0f} "
              f"{ts/1000:5.1f}->{te/1000:5.1f}km {r['apo']/1000:8.1f}x{r['peri']/1000:7.1f}km "
              f"{dvl:8.0f} {r['fuel']:9.0f} {r['t']:6.0f}")
    print()
    if rows:
        # Pick the configuration giving ~600-900 m/s of margin: enough room for an
        # imprecise player, not so much that fuel stops being a scoring axis.
        for thrust, isp, fuel, dvl, r in rows:
            verdict = ("TOO TIGHT" if dvl < 400 else
                       "GOOD" if dvl <= 1000 else "TOO GENEROUS")
            print(f"  {thrust/1000:.0f}kN/{isp:.0f}s/{fuel:.0f}kg -> {dvl:.0f} m/s margin  {verdict}")
