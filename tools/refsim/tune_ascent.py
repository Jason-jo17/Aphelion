"""Sweeps atmosphere and drag parameters to find a balance where the starter
ship reaches a 100 km orbit with a workable margin."""
import math, itertools, sys
import det_math as dm, sim, universe as U
from fly_ascent import _circ_burn_time


def build_world(rho0, H, height):
    w = sim.SimWorld()
    w.add_body(sim.CelestialBody(
        id="halcyon", mu=U.HALCYON["mu"], radius=U.HALCYON["radius"],
        rotation_rate=U.rotation_rate(U.HALCYON["rotation_period"]),
        atmosphere=dict(height=height, sea_level_density=rho0, scale_height=H)))
    return w


def fly(prof, w, turn_start, turn_end, target_alt=100000.0, trace=False):
    body = w.bodies[0]; mu, R = body.mu, body.radius
    integ = sim.Integrator()
    st = sim.ShipState(px=R, py=0.0, vx=0.0, vy=body.rotation_rate*R,
                       angle=0.0, fuel=prof.fuel_capacity)
    ctrl = sim.ControlInput()
    r_target = R + target_alt
    max_q = 0.0; drag_loss = 0.0; grav_loss = 0.0; phase = "ascent"
    prev_t = 0.0; tr = []
    for _ in range(3_000_000):
        t = sim.SimWorld.time_for_tick(st.tick)
        dt = t - prev_t; prev_t = t
        r = dm.hypot(st.px, st.py); alt = r - R
        if alt < -50.0:
            return dict(ok=False, why="crash", alt=alt)
        el = sim.elements(mu, st.px, st.py, st.vx, st.vy)
        vertical = dm.atan2(st.py, st.px)
        avx = -body.rotation_rate*st.py; avy = body.rotation_rate*st.px
        vair = dm.hypot(st.vx-avx, st.vy-avy)
        rho = body.density_at_altitude(alt)
        q = 0.5*rho*vair*vair
        max_q = max(max_q, q)
        m = prof.dry_mass + st.fuel
        if dt > 0:
            drag_loss += (q*prof.drag_coefficient*prof.drag_area/m)*dt
            # gravity loss = g * sin(flight path above horizon) * dt
            fpa = math.sin(dm.wrap_angle(dm.atan2(st.vy, st.vx) - vertical - math.pi/2))
            grav_loss += (mu/(r*r))*(-fpa)*dt if st.speed() > 1 else (mu/(r*r))*dt
        if trace and st.tick % 1280 == 0:
            tr.append((t, alt/1000, st.speed(), q/1000, el["apoapsis"]-R))
        if phase == "ascent":
            frac = max(0.0, min(1.0, (alt-turn_start)/(turn_end-turn_start)))
            st.angle = dm.wrap_angle(vertical + (math.pi/2.0)*frac)
            ctrl.throttle = 1.0
            if el["apoapsis"] >= r_target or st.fuel <= 0.0:
                phase = "coast"; ctrl.throttle = 0.0
        elif phase == "coast":
            st.angle = dm.atan2(st.vy, st.vx); ctrl.throttle = 0.0
            if el["t_apo"] <= 0.5*_circ_burn_time(prof, st, el, mu):
                phase = "circ"
            if alt < 15000.0:
                return dict(ok=False, why="fellback", apo=el["apoapsis"]-R)
        else:
            st.angle = dm.atan2(st.vy, st.vx); ctrl.throttle = 1.0
            if el["periapsis"] >= r_target-3000.0 or st.fuel <= 0.0:
                el = sim.elements(mu, st.px, st.py, st.vx, st.vy)
                return dict(ok=el["periapsis"] > R+70000.0, why="done",
                            apo=el["apoapsis"]-R, peri=el["periapsis"]-R,
                            ecc=el["ecc"], fuel=st.fuel, t=t, max_q=max_q,
                            dv_left=prof.delta_v(st.fuel), drag_loss=drag_loss,
                            grav_loss=grav_loss, trace=tr)
        integ.step(w, st, ctrl, prof, w.step_scale_for(t, st, ctrl, prof, math.inf))
    return dict(ok=False, why="timeout")


def sparrow(cd, area):
    return sim.ShipProfile(dry_mass=1350.0, fuel_capacity=3200.0, max_thrust=90000.0,
                           isp=290.0, max_torque=4000.0, inertia=14000.0,
                           drag_coefficient=cd, drag_area=area)


if __name__ == "__main__":
    print("baseline diagnosis (old numbers: Cd 0.8, A 6.9, rho0 1.2, H 6500):")
    w = build_world(1.2, 6500.0, 70000.0)
    r = fly(sparrow(0.8, 6.9), w, 1500.0, 48000.0, trace=True)
    print("   ", {k: (round(v,1) if isinstance(v,float) else v) for k,v in r.items() if k!='trace'})
    if r.get("trace"):
        print("     t      alt km   speed   q kPa   apo km")
        for row in r["trace"][:14]:
            print("    %5.0f  %7.1f %7.0f %7.1f %8.1f" % row)
    print()
    print("sweep: which (Cd, A, rho0, H, turn_end) gets Sparrow to orbit with margin?")
    print(f"{'Cd':>4} {'A':>4} {'rho0':>5} {'H':>6} {'turn_end':>8}  {'result':>44}  {'dv left':>8}")
    best = []
    for cd, area, rho0, H, te in itertools.product(
            [0.3, 0.45], [1.5, 2.5], [0.6, 1.0], [5500.0, 7000.0], [40000.0, 55000.0]):
        w = build_world(rho0, H, 70000.0)
        r = fly(sparrow(cd, area), w, 1200.0, te)
        if r.get("ok"):
            s = (f"{r['apo']/1000:6.1f} x {r['peri']/1000:6.1f} km ecc {r['ecc']:.3f} "
                 f"maxQ {r['max_q']/1000:4.1f}kPa T+{r['t']:4.0f}s")
            best.append((r['dv_left'], cd, area, rho0, H, te, s))
        else:
            s = f"FAIL {r['why']}"
        print(f"{cd:4.2f} {area:4.1f} {rho0:5.2f} {H:6.0f} {te:8.0f}  {s:>44}  "
              f"{r.get('dv_left',0):8.0f}")
    print()
    if best:
        best.sort(reverse=True)
        print("most margin:", best[0])
        print("least margin that still works:", best[-1])
