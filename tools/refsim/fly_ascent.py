"""Flies a gravity-turn ascent with the starter ship, to check that the part
catalogue is balanced such that the first missions are actually achievable.

This is a balance tool, not a test of the game's flight computer: it steers
directly rather than through the VM, to answer one question — is there enough
delta-v in the starter ship, with realistic gravity and drag losses?
"""

import json
import math
import sys

import det_math as dm
import sim
import universe as U


def load_parts():
    with open("../../data/parts.json") as f:
        return {p["id"]: p for p in json.load(f)["parts"]}


def profile_from(part_ids, parts):
    dry = fuel = thrust = flow = torque = drag = 0.0
    inert = 0.0
    for pid in part_ids:
        p = parts[pid]
        dry += p["mass"]
        fuel += p.get("fuel_capacity", 0.0)
        if p.get("thrust", 0.0) > 0:
            thrust += p["thrust"]
            flow += p["thrust"] / p["isp"]
        torque += p.get("torque", 0.0)
        drag += p.get("drag_area", 0.0)
    isp = thrust / flow if flow > 0 else 0.0
    # crude but representative: parts stacked in a column ~6 m tall
    wet = dry + fuel
    inert = wet * (1.0 + 36.0) / 12.0
    return sim.ShipProfile(dry_mass=dry, fuel_capacity=fuel, max_thrust=thrust,
                           isp=isp, max_torque=torque, inertia=inert,
                           drag_coefficient=0.8, drag_area=drag,
                           display_name="Sparrow")


def build_world():
    w = sim.SimWorld()
    w.add_body(sim.CelestialBody(
        id="halcyon", mu=U.HALCYON["mu"], radius=U.HALCYON["radius"],
        rotation_rate=U.rotation_rate(U.HALCYON["rotation_period"]),
        atmosphere=U.HALCYON["atmosphere"]))
    return w


def fly(prof, turn_start=1500.0, turn_end=48000.0, target_alt=100000.0, verbose=False):
    """Gravity turn to apoapsis, coast, circularise. Returns a result dict."""
    w = build_world()
    body = w.bodies[0]
    mu, R = body.mu, body.radius
    integ = sim.Integrator()

    st = sim.ShipState(px=R, py=0.0,
                       vx=0.0, vy=body.rotation_rate * R,
                       angle=0.0, fuel=prof.fuel_capacity)
    ctrl = sim.ControlInput()

    r_target = R + target_alt
    max_q = 0.0
    phase = "ascent"
    circ_ticks = 0

    for _ in range(4_000_000):
        t = sim.SimWorld.time_for_tick(st.tick)
        r = dm.hypot(st.px, st.py)
        alt = r - R
        if alt < -50.0:
            return dict(ok=False, why="crashed", alt=alt, fuel=st.fuel, t=t)
        el = sim.elements(mu, st.px, st.py, st.vx, st.vy)
        vertical = dm.atan2(st.py, st.px)

        v_air = dm.hypot(st.vx + body.rotation_rate * st.py,
                         st.vy - body.rotation_rate * st.px)
        max_q = max(max_q, 0.5 * body.density_at_altitude(alt) * v_air * v_air)

        if phase == "ascent":
            frac = (alt - turn_start) / (turn_end - turn_start)
            frac = max(0.0, min(1.0, frac))
            pitch = (math.pi / 2.0) * frac
            ctrl.throttle = 1.0
            st.angle = dm.wrap_angle(vertical + pitch)
            if el["apoapsis"] >= r_target or st.fuel <= 0.0:
                phase = "coast"
                ctrl.throttle = 0.0
        elif phase == "coast":
            st.angle = dm.atan2(st.vy, st.vx)          # prograde
            ctrl.throttle = 0.0
            if el["t_apo"] <= 0.5 * _circ_burn_time(prof, st, el, mu):
                phase = "circularise"
            if alt < 20000.0:
                return dict(ok=False, why="fell back", alt=alt, fuel=st.fuel, t=t,
                            apo=el["apoapsis"] - R, peri=el["periapsis"] - R)
        else:
            st.angle = dm.atan2(st.vy, st.vx)
            ctrl.throttle = 1.0
            circ_ticks += 1
            if el["periapsis"] >= r_target - 3000.0 or st.fuel <= 0.0:
                ctrl.throttle = 0.0
                el = sim.elements(mu, st.px, st.py, st.vx, st.vy)
                return dict(ok=el["periapsis"] > R + 70000.0, why="orbit",
                            apo=el["apoapsis"] - R, peri=el["periapsis"] - R,
                            ecc=el["ecc"], fuel=st.fuel, t=t, max_q=max_q,
                            dv_left=prof.delta_v(st.fuel))

        scale = w.step_scale_for(t, st, ctrl, prof, math.inf)
        integ.step(w, st, ctrl, prof, scale)
    return dict(ok=False, why="timeout")


def _circ_burn_time(prof, st, el, mu):
    """How long the circularisation burn will take, for the lead-in."""
    r_apo = el["apoapsis"]
    if math.isinf(r_apo):
        return 0.0
    v_apo = sim.vis_viva(mu, r_apo, el["sma"])
    dv = max(0.0, math.sqrt(mu / r_apo) - v_apo)
    mdot = prof.mass_flow()
    if mdot <= 0:
        return 0.0
    m = prof.dry_mass + st.fuel
    return m * (1.0 - dm.exp(-dv / prof.exhaust_velocity())) / mdot


if __name__ == "__main__":
    parts = load_parts()
    ships = {
        "Sparrow (pod + FT-32 + Kestrel + RW-4)":
            ["pod_mk1", "tank_large", "engine_main", "wheel_small"],
        "Sparrow-lite (probe + FT-32 + Kestrel + RW-4)":
            ["probe_core", "tank_large", "engine_main", "wheel_small"],
        "Heavy (pod + 2x FT-32 + Kestrel + RW-12)":
            ["pod_mk1", "tank_large", "tank_large", "engine_main", "wheel_large"],
    }
    print(f"{'ship':48} {'dv':>7} {'TWR':>5}  result")
    print("-" * 108)
    worst = 0
    for name, ids in ships.items():
        prof = profile_from(ids, parts)
        r = fly(prof)
        dv = prof.delta_v()
        twr = prof.twr(9.0)
        if r.get("ok"):
            detail = (f"orbit {r['apo']/1000:6.1f} x {r['peri']/1000:6.1f} km  "
                      f"ecc {r['ecc']:.4f}  fuel left {r['fuel']:6.0f} kg "
                      f"({r['dv_left']:5.0f} m/s)  T+{r['t']:5.0f}s  "
                      f"maxQ {r['max_q']/1000:.1f} kPa")
        else:
            detail = f"FAILED: {r['why']} {r}"
            worst = 1
        print(f"{name:48} {dv:7.0f} {twr:5.2f}  {detail}")
    sys.exit(worst)
