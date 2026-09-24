"""Writes tests/fixtures/*.json — golden values the GUT suite asserts against.

These exist to stop the shipped GDScript and this Python reference drifting
apart. Both use IEEE-754 doubles and only correctly-rounded primitives, so they
must agree bit for bit; the fixtures freeze that agreement, and CI checks it on
every push.

Floats are written with Python's repr, which is the shortest string that
round-trips exactly. GDScript's String.to_float() goes through strtod and is
correctly rounded, so the value it reads back is bit-identical — which is why
the tests can compare with == rather than a tolerance.
"""

import json
import math
import os

import det_math as dm
import runner
import ships
import sim

_HERE = os.path.dirname(os.path.abspath(__file__))
_FIXTURES = os.path.normpath(os.path.join(_HERE, "..", "..", "tests", "fixtures"))


def f(x):
    """Exact, round-trippable representation."""
    if math.isinf(x):
        return "inf" if x > 0 else "-inf"
    if math.isnan(x):
        return "nan"
    return repr(x)


def det_math_fixture():
    """Every kernel, over the ranges the simulation actually exercises, plus the
    awkward arguments: tiny, huge, negative, and exactly on a quadrant boundary."""
    cases = []
    args = [0.0, 1e-8, 0.1, 0.5, 0.7853981633974483, 1.0, 1.5707963267948966,
            2.0, 3.141592653589793, 4.0, 6.283185307179586, 10.0, 100.0,
            1000.0, 12345.6789, 1e5, -0.3, -2.7, -9.9, -1234.5]
    for x in args:
        s, c = dm.sincos(x)
        cases.append({"fn": "sin", "x": f(x), "y": f(dm.sin(x))})
        cases.append({"fn": "cos", "x": f(x), "y": f(dm.cos(x))})
        cases.append({"fn": "sincos_s", "x": f(x), "y": f(s)})
        cases.append({"fn": "sincos_c", "x": f(x), "y": f(c)})
        cases.append({"fn": "atan", "x": f(x), "y": f(dm.atan(x))})
        cases.append({"fn": "wrap_angle", "x": f(x), "y": f(dm.wrap_angle(x))})
        cases.append({"fn": "wrap_tau", "x": f(x), "y": f(dm.wrap_tau(x))})
    for x in [-40.0, -10.0, -1.0, -0.001, 0.0, 0.001, 1.0, 5.0, 20.0, 40.0, 100.0]:
        cases.append({"fn": "exp", "x": f(x), "y": f(dm.exp(x))})
    for x in [1e-10, 0.001, 0.5, 1.0, 2.0, 10.0, 1000.0, 6.4e5, 3.6864e12, 1e20]:
        cases.append({"fn": "log", "x": f(x), "y": f(dm.log(x))})
    for x in [-1.0, -0.5, 0.0, 0.25, 0.5, 0.9, 1.0]:
        cases.append({"fn": "acos", "x": f(x), "y": f(dm.acos(x))})
        cases.append({"fn": "asin", "x": f(x), "y": f(dm.asin(x))})

    pairs = []
    for y, x in [(1.0, 1.0), (1.0, -1.0), (-1.0, 1.0), (-1.0, -1.0),
                 (0.0, 1.0), (0.0, -1.0), (1.0, 0.0), (-1.0, 0.0), (0.0, 0.0),
                 (1e-9, 1e9), (1e9, 1e-9), (2232.0, -740000.0), (-554.3, 12000000.0)]:
        pairs.append({"fn": "atan2", "y": f(y), "x": f(x), "r": f(dm.atan2(y, x))})
        pairs.append({"fn": "hypot", "y": f(y), "x": f(x), "r": f(dm.hypot(x, y))})
    for base, expo in [(2.0, 10.0), (0.017632, 0.4), (10.0, -3.0), (2.5, 0.5)]:
        pairs.append({"fn": "pow", "y": f(expo), "x": f(base), "r": f(dm.pow(base, expo))})

    return {"unary": cases, "binary": pairs}


def orbital_fixture():
    """Conic elements of state vectors that cover circular, elliptical,
    hyperbolic and the near-parabolic edge."""
    mu = 3.6864e12
    states = [
        ("circular_100km", mu, 740000.0, 0.0, 0.0, 2232.0),
        ("elliptical", mu, 740000.0, 0.0, 0.0, 2600.0),
        ("eccentric_at_apo", mu, 1540000.0, 0.0, 0.0, 1050.0),
        ("retrograde", mu, 740000.0, 0.0, 0.0, -2232.0),
        ("hyperbolic", mu, 740000.0, 0.0, 0.0, 3400.0),
        ("inclined_vector", mu, 523259.0, -523259.0, 1578.0, 1578.0),
        ("moon_hyperbola", 6.5e10, -1198571.429, -1844837.806, 279.1541, 266.7656),
    ]
    out = []
    for name, m, rx, ry, vx, vy in states:
        el = sim.elements(m, rx, ry, vx, vy)
        out.append({
            "name": name, "mu": f(m), "rx": f(rx), "ry": f(ry), "vx": f(vx), "vy": f(vy),
            "sma": f(el["sma"]), "ecc": f(el["ecc"]),
            "apoapsis": f(el["apoapsis"]), "periapsis": f(el["periapsis"]),
            "period": f(el["period"]), "nu": f(el["nu"]),
            "t_apo": f(el["t_apo"]), "t_peri": f(el["t_peri"]),
            "v_radial": f(el["v_radial"]), "v_tangential": f(el["v_tangential"]),
        })
    return out


def trajectory_fixture():
    """A pure coast and a powered burn, sampled at fixed tick counts.

    The coast catches any drift in gravity, the step-size chooser or the time
    base; the burn catches the closed-form mass and attitude handling inside a
    step. Both are recorded to the last bit."""
    universe = runner.load_universe()
    hb = universe["bodies"][0]

    def world():
        w = sim.SimWorld()
        w.add_body(sim.CelestialBody(
            id=hb["id"], mu=hb["mu"], radius=hb["radius"],
            rotation_rate=hb["rotation_rate"], atmosphere=hb["atmosphere"]))
        lb = universe["bodies"][1]
        w.add_body(sim.CelestialBody(
            id=lb["id"], mu=lb["mu"], radius=lb["radius"],
            rotation_rate=lb["rotation_rate"], orbit_radius=lb["orbit_radius"],
            orbit_phase0=lb["orbit_phase0"], primary_mu=hb["mu"]))
        return w

    prof = ships.stock("wren").to_profile()
    out = []

    for name, throttle, torque, scale, checkpoints in [
        ("coast_fixed", 0.0, 0.0, 1, [1, 64, 640, 6400, 64000]),
        ("coast_adaptive", 0.0, 0.0, -1, [1, 64, 640, 6400, 64000]),
        ("burn_prograde", 1.0, 0.0, 1, [1, 16, 64, 256, 1024]),
        ("burn_while_turning", 1.0, 0.35, 1, [1, 16, 64, 256, 1024]),
    ]:
        w = world()
        st = sim.ShipState(px=740000.0, py=0.0, vx=0.0, vy=2232.0,
                           angle=0.5, ang_vel=0.0, fuel=prof.fuel_capacity)
        ctrl = sim.ControlInput(throttle=throttle, torque=torque)
        integ = sim.Integrator()
        samples = []
        target = set(checkpoints)
        n = 0
        while n < max(checkpoints):
            if scale < 0:
                t = sim.SimWorld.time_for_tick(st.tick)
                s = w.step_scale_for(t, st, ctrl, prof, math.inf)
                s = min(s, max(checkpoints) - n)
                p = 1
                while p * 2 <= s:
                    p *= 2
                s = p
            else:
                s = scale
            integ.step(w, st, ctrl, prof, s)
            n += s
            if n in target:
                samples.append({
                    "tick": st.tick, "px": f(st.px), "py": f(st.py),
                    "vx": f(st.vx), "vy": f(st.vy), "angle": f(st.angle),
                    "ang_vel": f(st.ang_vel), "fuel": f(st.fuel),
                })
        out.append({
            "name": name, "ship": "wren",
            "throttle": f(throttle), "torque": f(torque), "scale": scale,
            "start": {"px": f(740000.0), "py": f(0.0), "vx": f(0.0), "vy": f(2232.0),
                      "angle": f(0.5), "ang_vel": f(0.0), "fuel": f(prof.fuel_capacity)},
            "samples": samples,
        })
    return out


def profile_fixture():
    """Derived ship properties, so a change to the part catalogue that silently
    alters delta-v is caught."""
    out = []
    for sid in ships.stock_ids():
        d = ships.stock(sid)
        p = d.to_profile()
        out.append({
            "id": sid, "dry_mass": f(p.dry_mass), "fuel_capacity": f(p.fuel_capacity),
            "max_thrust": f(p.max_thrust), "isp": f(p.isp), "max_torque": f(p.max_torque),
            "inertia": f(p.inertia), "drag_area": f(p.drag_area),
            "delta_v": f(p.delta_v()), "burn_time": f(p.burn_time()),
            "twr_halcyon": f(p.twr(9.0)),
            "centre_of_mass": [f(d.centre_of_mass()[0]), f(d.centre_of_mass()[1])],
        })
    return out


def write(name, data):
    os.makedirs(_FIXTURES, exist_ok=True)
    path = os.path.join(_FIXTURES, name)
    with open(path, "w") as fh:
        json.dump(data, fh, indent=1)
        fh.write("\n")
    print("wrote %-24s %6d bytes" % (name, os.path.getsize(path)))


if __name__ == "__main__":
    write("det_math.json", det_math_fixture())
    write("orbital.json", orbital_fixture())
    write("trajectory.json", trajectory_fixture())
    write("ship_profiles.json", profile_fixture())
    print("\nThese are asserted by tests/unit/. Regenerate them in the same commit")
    print("as any change to scripts/physics/ or scripts/core/det_math.gd.")
