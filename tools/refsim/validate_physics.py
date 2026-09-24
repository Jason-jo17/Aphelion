"""Numerical checks on the reference sim: conservation, closure, and the cost
of deterministic step scaling. Run directly; prints a pass/fail table."""

import math
import det_math as dm
import sim
import universe as U

INF = math.inf


def build_world(with_moon=True):
    w = sim.SimWorld()
    h = sim.CelestialBody(
        id=U.HALCYON["id"], mu=U.HALCYON["mu"], radius=U.HALCYON["radius"],
        rotation_period=U.HALCYON["rotation_period"],
        atmosphere=U.HALCYON["atmosphere"])
    w.add_body(h)
    if with_moon:
        w.add_body(sim.CelestialBody(
            id=U.LYRA["id"], mu=U.LYRA["mu"], radius=U.LYRA["radius"],
            tidally_locked=U.LYRA["tidally_locked"],
            orbit_radius=U.LYRA["orbit_radius"], orbit_phase0=U.LYRA["orbit_phase0"],
            primary_mu=U.HALCYON["mu"]))
    return w


def coasting_profile():
    return sim.ShipProfile(dry_mass=1300.0, fuel_capacity=0.0, max_thrust=0.0,
                           isp=290.0, max_torque=0.0, inertia=8000.0)


def circular_state(mu, r, fuel=0.0):
    return sim.ShipState(px=r, py=0.0, vx=0.0, vy=math.sqrt(mu / r), fuel=fuel)


def energy(mu, st):
    r = dm.hypot(st.px, st.py)
    return 0.5 * (st.vx ** 2 + st.vy ** 2) - mu / r


def run(world, st, prof, ticks, ctrl=None, adaptive=False, fixed_scale=1):
    integ = sim.Integrator()
    ctrl = ctrl or sim.ControlInput()
    remaining = ticks
    while remaining > 0:
        t = sim.SimWorld.time_for_tick(st.tick)
        scale = world.step_scale_for(t, st, ctrl, prof, INF) if adaptive else fixed_scale
        scale = min(scale, remaining)
        # keep power-of-two discipline when clamping to the remaining budget
        p = 1
        while p * 2 <= scale:
            p *= 2
        scale = p
        integ.step(world, st, ctrl, prof, scale)
        remaining -= scale
    return st


results = []


def check(name, ok, detail):
    results.append((ok, name, detail))


def main():
  # --- 1.   Circular orbit stays circular, 10 revolutions, vacuum, no moon ------
  w = build_world(with_moon=False)
  mu = U.HALCYON["mu"]
  r0 = U.HALCYON["radius"] + 100_000.0
  prof = coasting_profile()
  st = circular_state(mu, r0)
  e0 = energy(mu, st)
  T = 2 * math.pi * r0 / math.sqrt(mu / r0)
  ticks = int(round(10 * T / sim.DT_BASE))
  st = run(w, st, prof, ticks, fixed_scale=1)
  e1 = energy(mu, st)
  el = sim.elements(mu, st.px, st.py, st.vx, st.vy)
  check("energy conserved, 10 orbits @ dt=1/64",
        abs((e1 - e0) / e0) < 1e-12,
        f"rel drift {abs((e1-e0)/e0):.3e}")
  check("orbit stays circular (ecc)",
        el["ecc"] < 1e-9, f"ecc={el['ecc']:.3e}")
  check("apoapsis holds to <1 mm",
        abs(el["apoapsis"] - r0) < 1e-3,
        f"apo err {abs(el['apoapsis']-r0)*1000:.4f} mm")

  # --- 2. Closure: after exactly one period the ship returns to its start -----
  st = circular_state(mu, r0)
  one_period_ticks = int(round(T / sim.DT_BASE))
  st = run(w, st, prof, one_period_ticks, fixed_scale=1)
  pos_err = dm.hypot(st.px - r0, st.py)
  # The period is 2083.2 s, which is not a whole number of 1/64 s ticks, so the
  # ship necessarily stops up to half a tick short of where it started. At
  # 2232 m/s that is ~17 m and it is discretisation, not integration error.
  one_tick_of_travel = math.sqrt(mu / r0) * sim.DT_BASE
  check("closure after 1 period (within one tick of travel)",
        pos_err < one_tick_of_travel,
        f"position error {pos_err:.3f} m vs one-tick bound {one_tick_of_travel:.3f} m")

  # --- 3. Deterministic step scaling vs full-rate integration -----------------
  st_fine = circular_state(mu, r0)
  st_warp = circular_state(mu, r0)
  n = int(round(5 * T / sim.DT_BASE))
  run(w, st_fine, prof, n, fixed_scale=1)
  run(w, st_warp, prof, n, adaptive=True)
  d = dm.hypot(st_fine.px - st_warp.px, st_fine.py - st_warp.py)
  el_w = sim.elements(mu, st_warp.px, st_warp.py, st_warp.vx, st_warp.vy)
  check("step scaling keeps orbit shape", abs(el_w["apoapsis"] - r0) < 1.0,
        f"apo err {abs(el_w['apoapsis']-r0):.4f} m; pos diff vs full-rate {d:.2f} m")

  # --- 4. Repeatability: identical inputs -> identical bits -------------------
  a = circular_state(mu, r0)
  b = circular_state(mu, r0)
  run(w, a, prof, 60000, adaptive=True)
  run(w, b, prof, 60000, adaptive=True)
  same = (a.px == b.px and a.py == b.py and a.vx == b.vx and a.vy == b.vy
          and a.tick == b.tick and a.fuel == b.fuel)
  check("bit-identical across repeat runs", same, "exact float equality on all fields")

  # --- 5. Vis-viva agreement on an eccentric orbit ----------------------------
  r_peri = U.HALCYON["radius"] + 100_000.0
  r_apo = U.HALCYON["radius"] + 900_000.0
  a_e = 0.5 * (r_peri + r_apo)
  v_peri = sim.vis_viva(mu, r_peri, a_e)
  st = sim.ShipState(px=r_peri, py=0.0, vx=0.0, vy=v_peri)
  el = sim.elements(mu, st.px, st.py, st.vx, st.vy)
  check("vis-viva -> predicted apoapsis", abs(el["apoapsis"] - r_apo) < 1e-6,
        f"apo {el['apoapsis']:.3f} vs {r_apo:.3f}")
  half = int(round(0.5 * el["period"] / sim.DT_BASE))
  run(w, st, prof, half, adaptive=True)
  r_reached = dm.hypot(st.px, st.py)
  check("coasts to apoapsis within 1 m", abs(r_reached - r_apo) < 1.0,
        f"reached r={r_reached:.3f}, target {r_apo:.3f}")

  # --- 6. Time to apoapsis sensor agrees with the integration ----------------
  st = sim.ShipState(px=r_peri, py=0.0, vx=0.0, vy=v_peri)
  el = sim.elements(mu, st.px, st.py, st.vx, st.vy)
  predicted = el["t_apo"]
  check("t_apo at periapsis == half period",
        abs(predicted - el["period"] * 0.5) < 1e-6,
        f"t_apo {predicted:.4f}s, T/2 {el['period']*0.5:.4f}s")

  # quarter-way check: t_apo must shrink by exactly the elapsed time on a coast
  st2 = sim.ShipState(px=r_peri, py=0.0, vx=0.0, vy=v_peri)
  elapsed_ticks = 20000
  run(w, st2, prof, elapsed_ticks, fixed_scale=1)
  el2 = sim.elements(mu, st2.px, st2.py, st2.vx, st2.vy)
  elapsed = elapsed_ticks * sim.DT_BASE
  check("t_apo decreases by elapsed time",
        abs((predicted - elapsed) - el2["t_apo"]) < 1e-3,
        f"expected {predicted-elapsed:.4f}, got {el2['t_apo']:.4f}")

  # --- 7. Moon gravity is felt, and the SOI hand-off happens ------------------
  wm = build_world(with_moon=True)
  lyra = wm.bodies[1]
  near = sim.ShipState(px=lyra.pos_x(0.0) + lyra.radius + 50_000.0, py=0.0,
                       vx=0.0, vy=lyra.vel_y(0.0) + math.sqrt(lyra.mu / (lyra.radius + 50_000.0)))
  check("SOI hand-off to moon",
        wm.dominant_body_index(0.0, near.px, near.py) == 1,
        f"soi index {wm.dominant_body_index(0.0, near.px, near.py)}")
  e_rel0 = 0.5 * ((near.vx - lyra.vel_x(0.0)) ** 2 + (near.vy - lyra.vel_y(0.0)) ** 2) \
      - lyra.mu / dm.hypot(near.px - lyra.pos_x(0.0), near.py - lyra.pos_y(0.0))
  Tm = 2 * math.pi * (lyra.radius + 50_000.0) / math.sqrt(lyra.mu / (lyra.radius + 50_000.0))
  run(wm, near, prof, int(round(2 * Tm / sim.DT_BASE)), adaptive=True)
  tf = sim.SimWorld.time_for_tick(near.tick)
  alt = dm.hypot(near.px - lyra.pos_x(tf), near.py - lyra.pos_y(tf)) - lyra.radius
  check("two orbits of the moon stay bound",
        20_000.0 < alt < 120_000.0, f"altitude above Lyra {alt/1000:.2f} km")

  # --- 8. Atmospheric drag actually decays an orbit --------------------------
  wa = build_world(with_moon=False)
  prof_drag = sim.ShipProfile(dry_mass=1300.0, drag_coefficient=0.8, drag_area=6.0,
                              isp=290.0, inertia=8000.0)
  r_low = U.HALCYON["radius"] + 68_000.0
  st = circular_state(mu, r_low)
  apo0 = sim.elements(mu, st.px, st.py, st.vx, st.vy)["apoapsis"]
  run(wa, st, prof_drag, int(round(3000.0 / sim.DT_BASE)), adaptive=True)
  apo1 = sim.elements(mu, st.px, st.py, st.vx, st.vy)["apoapsis"]
  check("drag lowers apoapsis inside the atmosphere", apo1 < apo0 - 100.0,
        f"apoapsis {apo0/1000:.1f} km -> {apo1/1000:.1f} km over 3000 s")

  print(f"{'':2} {'check':52} detail")
  print("-" * 100)
  for ok, name, detail in results:
      print(f"{'ok' if ok else 'XX'} {name:52} {detail}")
  bad = [r for r in results if not r[0]]
  print("-" * 100)
  print(f"{len(results)-len(bad)}/{len(results)} passed")
  return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
