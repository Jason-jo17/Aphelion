"""Reference implementation of Aphelion's physics, ported from scripts/physics/.

Purpose
-------
Godot is a GUI-first toolchain and is awkward to put inside a tight numerical
feedback loop.  This module is a faithful, line-by-line port of the shipped
GDScript so that mission thresholds can be tuned, star ratings sanity-checked
and golden fixtures generated from a plain Python process.

Because both sides use IEEE-754 doubles, only correctly-rounded primitives, and
the same deterministic transcendentals from ``det_math``, the two
implementations agree bit for bit.  ``generate_fixtures.py`` freezes that
agreement into ``tests/fixtures/`` and the GUT suite asserts it, so if either
side is edited without the other, CI fails.

Ported from:
    scripts/physics/celestial_body.gd
    scripts/physics/orbit_target.gd
    scripts/physics/orbital.gd
    scripts/physics/sim_world.gd
    scripts/physics/integrator.gd
"""

import math

import det_math as dm

DT_BASE = 0.015625
MAX_STEP_SCALE = 4096
MIN_STEPS_PER_ORBIT = 512.0
G0 = 9.80665
INF = math.inf


class CelestialBody:
    def __init__(self, id="", mu=0.0, radius=0.0, rotation_rate=0.0,
                 orbit_radius=0.0, orbit_phase0=0.0, orbit_direction=1.0,
                 atmosphere=None, primary_mu=0.0, name=None):
        self.id = id
        self.display_name = name or id
        self.mu = mu
        self.radius = radius
        self.rotation_rate = rotation_rate
        self.orbit_radius = orbit_radius
        self.orbit_phase0 = orbit_phase0
        self.atmo_height = 0.0
        self.atmo_sea_level_density = 0.0
        self.atmo_scale_height = 1.0
        if atmosphere:
            self.atmo_height = atmosphere["height"]
            self.atmo_sea_level_density = atmosphere["sea_level_density"]
            self.atmo_scale_height = max(1.0, atmosphere["scale_height"])
        if orbit_radius > 0.0 and primary_mu > 0.0:
            a3 = orbit_radius * orbit_radius * orbit_radius
            n = math.sqrt(primary_mu / a3)
            self.orbit_mean_motion = n * (1.0 if orbit_direction >= 0 else -1.0)
            self.soi_radius = orbit_radius * dm.pow(mu / primary_mu, 0.4)
        else:
            self.orbit_mean_motion = 0.0
            self.soi_radius = INF
        self._memo_t = None
        self._memo_x = 0.0
        self._memo_y = 0.0

    def has_atmosphere(self):
        return self.atmo_height > 0.0 and self.atmo_sea_level_density > 0.0

    def is_primary(self):
        return self.orbit_radius == 0.0

    def _position_at(self, t):
        if t == self._memo_t:
            return
        if self.orbit_radius == 0.0:
            self._memo_x = 0.0
            self._memo_y = 0.0
        else:
            s, c = dm.sincos(self.orbit_phase0 + self.orbit_mean_motion * t)
            self._memo_x = self.orbit_radius * c
            self._memo_y = self.orbit_radius * s
        self._memo_t = t

    def pos_x(self, t):
        self._position_at(t)
        return self._memo_x

    def pos_y(self, t):
        self._position_at(t)
        return self._memo_y

    def vel_x(self, t):
        if self.orbit_radius == 0.0:
            return 0.0
        s, _c = dm.sincos(self.orbit_phase0 + self.orbit_mean_motion * t)
        return -self.orbit_radius * self.orbit_mean_motion * s

    def vel_y(self, t):
        if self.orbit_radius == 0.0:
            return 0.0
        _s, c = dm.sincos(self.orbit_phase0 + self.orbit_mean_motion * t)
        return self.orbit_radius * self.orbit_mean_motion * c

    def density_at_altitude(self, altitude):
        if not self.has_atmosphere():
            return 0.0
        if altitude >= self.atmo_height:
            return 0.0
        if altitude <= 0.0:
            return self.atmo_sea_level_density
        return self.atmo_sea_level_density * dm.exp(-altitude / self.atmo_scale_height)

    def surface_vel_x(self, rel_x, rel_y):
        return -self.rotation_rate * rel_y

    def surface_vel_y(self, rel_x, rel_y):
        return self.rotation_rate * rel_x


class ShipProfile:
    def __init__(self, dry_mass=1000.0, fuel_capacity=0.0, max_thrust=0.0,
                 isp=1.0, max_torque=0.0, inertia=1.0,
                 drag_coefficient=0.8, drag_area=4.0, max_landing_speed=0.0,
                 display_name="Unnamed"):
        self.display_name = display_name
        self.dry_mass = dry_mass
        self.fuel_capacity = fuel_capacity
        self.max_thrust = max_thrust
        self.isp = isp
        self.max_torque = max_torque
        self.inertia = inertia
        self.drag_coefficient = drag_coefficient
        self.drag_area = drag_area
        self.max_landing_speed = max_landing_speed

    def exhaust_velocity(self):
        return self.isp * G0

    def mass_flow(self):
        ve = self.exhaust_velocity()
        if ve <= 0.0 or self.max_thrust <= 0.0:
            return 0.0
        return self.max_thrust / ve

    def delta_v(self, fuel=None):
        f = self.fuel_capacity if fuel is None else fuel
        if f <= 0.0 or self.max_thrust <= 0.0 or self.dry_mass <= 0.0:
            return 0.0
        return self.exhaust_velocity() * dm.log((self.dry_mass + f) / self.dry_mass)

    def burn_time(self, fuel=None):
        f = self.fuel_capacity if fuel is None else fuel
        mdot = self.mass_flow()
        return 0.0 if mdot <= 0.0 else f / mdot

    def twr(self, g, fuel=None):
        f = self.fuel_capacity if fuel is None else fuel
        w = (self.dry_mass + f) * g
        return 0.0 if w <= 0.0 else self.max_thrust / w


class ShipState:
    __slots__ = ("tick", "px", "py", "vx", "vy", "angle", "ang_vel",
                 "fuel", "landed", "crashed", "soi_index")

    def __init__(self, **kw):
        self.tick = 0
        self.px = self.py = self.vx = self.vy = 0.0
        self.angle = self.ang_vel = 0.0
        self.fuel = 0.0
        self.landed = False
        self.crashed = False
        self.soi_index = 0
        for k, v in kw.items():
            setattr(self, k, v)

    def copy(self):
        s = ShipState()
        for k in self.__slots__:
            setattr(s, k, getattr(self, k))
        return s

    def speed(self):
        return dm.hypot(self.vx, self.vy)


class ControlInput:
    __slots__ = ("throttle", "torque")

    def __init__(self, throttle=0.0, torque=0.0):
        self.throttle = throttle
        self.torque = torque


# --- Orbital (port of scripts/physics/orbital.gd) ---------------------------


def circular_speed(mu, r):
    return 0.0 if r <= 0.0 or mu <= 0.0 else math.sqrt(mu / r)


def escape_speed(mu, r):
    return 0.0 if r <= 0.0 or mu <= 0.0 else math.sqrt(2.0 * mu / r)


def vis_viva(mu, r, a):
    if r <= 0.0 or a == 0.0:
        return 0.0
    v2 = mu * (2.0 / r - 1.0 / a)
    return 0.0 if v2 <= 0.0 else math.sqrt(v2)


def period(mu, a):
    if a <= 0.0 or mu <= 0.0:
        return INF
    return dm.TAU_D * math.sqrt(a * a * a / mu)


def hohmann(mu, r1, r2):
    a_t = 0.5 * (r1 + r2)
    v1 = math.sqrt(mu / r1)
    v2 = math.sqrt(mu / r2)
    return (vis_viva(mu, r1, a_t) - v1,
            v2 - vis_viva(mu, r2, a_t),
            dm.PI_D * math.sqrt(a_t ** 3 / mu))


def period_of_state(mu, rx, ry, vx, vy):
    r = dm.hypot(rx, ry)
    if r <= 0.0 or mu <= 0.0:
        return INF
    energy = 0.5 * (vx * vx + vy * vy) - mu / r
    if energy >= 0.0:
        return INF
    return period(mu, -mu / (2.0 * energy))


def elements(mu, rx, ry, vx, vy):
    r = dm.hypot(rx, ry)
    v2 = vx * vx + vy * vy
    v = math.sqrt(v2)
    out = {"radius": r, "speed": v, "sma": 0.0, "ecc": 0.0,
           "apoapsis": INF, "periapsis": 0.0, "period": INF, "energy": 0.0,
           "h": 0.0, "nu": 0.0, "t_apo": INF, "t_peri": INF,
           "v_radial": 0.0, "v_tangential": 0.0}
    if r <= 0.0 or mu <= 0.0:
        return out
    h = rx * vy - ry * vx
    rv = rx * vx + ry * vy
    out["h"] = h
    out["v_radial"] = rv / r
    out["v_tangential"] = h / r
    energy = 0.5 * v2 - mu / r
    out["energy"] = energy
    c1 = v2 / mu - 1.0 / r
    c2 = rv / mu
    ex = c1 * rx - c2 * vx
    ey = c1 * ry - c2 * vy
    ecc = dm.hypot(ex, ey)
    out["ecc"] = ecc
    if abs(energy) < 1.0e-12:
        out["sma"] = INF
        out["periapsis"] = h * h / mu * 0.5
        return out
    a = -mu / (2.0 * energy)
    out["sma"] = a
    if ecc < 1.0:
        out["apoapsis"] = a * (1.0 + ecc)
        out["periapsis"] = a * (1.0 - ecc)
        out["period"] = period(mu, a)
    else:
        out["apoapsis"] = INF
        out["periapsis"] = a * (1.0 - ecc)
    nu = 0.0
    if ecc > 1.0e-10:
        cos_nu = (ex * rx + ey * ry) / (ecc * r)
        nu = dm.acos(max(-1.0, min(1.0, cos_nu)))
        if rv < 0.0:
            nu = dm.TAU_D - nu
    out["nu"] = nu
    if ecc < 1.0 and a > 0.0:
        n = math.sqrt(mu / (a ** 3))
        if n > 0.0:
            half = nu * 0.5
            sq1 = math.sqrt(max(0.0, 1.0 - ecc))
            sq2 = math.sqrt(max(0.0, 1.0 + ecc))
            ea = 2.0 * dm.atan2(sq1 * dm.sin(half), sq2 * dm.cos(half))
            m = dm.wrap_tau(ea - ecc * dm.sin(ea))
            out["t_peri"] = (dm.TAU_D - m) / n if m > 0.0 else 0.0
            out["t_apo"] = dm.wrap_tau(dm.PI_D - m) / n
    elif ecc > 1.0 and a < 0.0:
        n_h = math.sqrt(mu / ((-a) ** 3))
        if n_h > 0.0:
            half_h = dm.wrap_angle(nu) * 0.5
            c = dm.cos(half_h)
            if abs(c) > 1.0e-300:
                tan_half = dm.sin(half_h) / c
                k = math.sqrt((ecc - 1.0) / (ecc + 1.0)) * tan_half
                if abs(k) < 1.0:
                    h_anom = dm.log((1.0 + k) / (1.0 - k))
                    sinh_h = 0.5 * (dm.exp(h_anom) - dm.exp(-h_anom))
                    m_h = ecc * sinh_h - h_anom
                    out["t_peri"] = (-m_h / n_h) if m_h < 0.0 else INF
        out["t_apo"] = INF
    return out


# --- SimWorld ---------------------------------------------------------------


class SimWorld:
    def __init__(self):
        self.primary = None
        self.bodies = []
        self.targets = []
        self.seed = 0

    @staticmethod
    def time_for_tick(tick):
        return float(tick) * DT_BASE

    def add_body(self, b):
        self.bodies.append(b)
        if b.is_primary() and self.primary is None:
            self.primary = b
        return len(self.bodies) - 1

    def body_index_by_id(self, bid):
        for i, b in enumerate(self.bodies):
            if b.id == bid:
                return i
        return -1

    def dominant_body_index(self, t, px, py):
        best, best_soi = 0, INF
        for i, b in enumerate(self.bodies):
            if math.isinf(b.soi_radius):
                continue
            d = dm.hypot(px - b.pos_x(t), py - b.pos_y(t))
            if d <= b.soi_radius and b.soi_radius < best_soi:
                best, best_soi = i, b.soi_radius
        return best

    def altitude_above(self, bi, t, px, py):
        b = self.bodies[bi]
        return dm.hypot(px - b.pos_x(t), py - b.pos_y(t)) - b.radius

    def elements_for(self, bi, t, st):
        b = self.bodies[bi]
        return elements(b.mu, st.px - b.pos_x(t), st.py - b.pos_y(t),
                        st.vx - b.vel_x(t), st.vy - b.vel_y(t))

    def step_scale_for(self, t, st, ctrl, prof, vm_slack):
        if ctrl.throttle > 0.0 or st.landed or st.crashed:
            return 1
        if abs(ctrl.torque) > 0.0 or abs(st.ang_vel) > 1.0e-6:
            return 1
        soi = self.dominant_body_index(t, st.px, st.py)
        body = self.bodies[soi]
        alt = self.altitude_above(soi, t, st.px, st.py)
        if body.has_atmosphere() and alt < body.atmo_height * 1.25:
            return 1
        if alt < body.radius * 0.05:
            return 1
        limit = float(MAX_STEP_SCALE)
        per = period_of_state(body.mu,
                              st.px - body.pos_x(t), st.py - body.pos_y(t),
                              st.vx - body.vel_x(t), st.vy - body.vel_y(t))
        if not math.isinf(per) and per > 0.0:
            limit = min(limit, per / (MIN_STEPS_PER_ORBIT * DT_BASE))
        if vm_slack < INF:
            limit = min(limit, max(1.0, vm_slack / DT_BASE))
        closing = st.speed()
        if closing > 0.0 and alt > 0.0:
            limit = min(limit, (alt * 0.05) / (closing * DT_BASE))
        if limit <= 1.0:
            return 1
        scale = 1
        while scale * 2 <= MAX_STEP_SCALE and float(scale * 2) <= limit:
            scale *= 2
        return scale


# --- Integrator -------------------------------------------------------------


class Integrator:
    def __init__(self):
        self._m0 = self._mdot = self._t_cut = self._thrust = 0.0
        self._alpha = self._angle0 = self._w0 = 0.0
        self._ax = self._ay = 0.0

    def step(self, world, st, ctrl, prof, scale=1):
        if st.crashed:
            return
        h = DT_BASE * float(scale)
        t0 = SimWorld.time_for_tick(st.tick)
        self._m0 = prof.dry_mass + st.fuel
        self._angle0 = st.angle
        self._w0 = st.ang_vel
        self._alpha = 0.0
        if prof.inertia > 0.0 and prof.max_torque > 0.0:
            self._alpha = max(-1.0, min(1.0, ctrl.torque)) * prof.max_torque / prof.inertia
        self._thrust = prof.max_thrust * max(0.0, min(1.0, ctrl.throttle))
        self._mdot = 0.0
        self._t_cut = 0.0
        if self._thrust > 0.0 and st.fuel > 0.0:
            ve = prof.exhaust_velocity()
            if ve > 0.0:
                self._mdot = self._thrust / ve
                self._t_cut = h if self._mdot <= 0.0 else min(h, st.fuel / self._mdot)
            else:
                self._thrust = 0.0
        else:
            self._thrust = 0.0

        if st.landed and not self._can_lift_off(world, st, prof, t0):
            self._advance_attitude(st, h, scale)
            return

        px, py, vx, vy = st.px, st.py, st.vx, st.vy
        h2 = h * 0.5
        t_half = t0 + h2
        t_end = t0 + h

        self._accel(world, prof, t0, 0.0, px, py, vx, vy)
        k1px, k1py, k1vx, k1vy = vx, vy, self._ax, self._ay

        self._accel(world, prof, t_half, h2, px + h2 * k1px, py + h2 * k1py,
                    vx + h2 * k1vx, vy + h2 * k1vy)
        k2px, k2py = vx + h2 * k1vx, vy + h2 * k1vy
        k2vx, k2vy = self._ax, self._ay

        self._accel(world, prof, t_half, h2, px + h2 * k2px, py + h2 * k2py,
                    vx + h2 * k2vx, vy + h2 * k2vy)
        k3px, k3py = vx + h2 * k2vx, vy + h2 * k2vy
        k3vx, k3vy = self._ax, self._ay

        self._accel(world, prof, t_end, h, px + h * k3px, py + h * k3py,
                    vx + h * k3vx, vy + h * k3vy)
        k4px, k4py = vx + h * k3vx, vy + h * k3vy
        k4vx, k4vy = self._ax, self._ay

        h6 = h / 6.0
        st.px = px + h6 * (k1px + 2.0 * k2px + 2.0 * k3px + k4px)
        st.py = py + h6 * (k1py + 2.0 * k2py + 2.0 * k3py + k4py)
        st.vx = vx + h6 * (k1vx + 2.0 * k2vx + 2.0 * k3vx + k4vx)
        st.vy = vy + h6 * (k1vy + 2.0 * k2vy + 2.0 * k3vy + k4vy)

        if self._mdot > 0.0:
            st.fuel = max(0.0, st.fuel - self._mdot * self._t_cut)

        self._advance_attitude(st, h, scale)
        if st.landed:
            st.landed = False

    def _advance_attitude(self, st, h, scale):
        st.angle = dm.wrap_angle(st.angle + st.ang_vel * h + 0.5 * self._alpha * h * h)
        st.ang_vel += self._alpha * h
        st.tick += scale

    def _can_lift_off(self, world, st, prof, t):
        if self._thrust <= 0.0:
            return False
        soi = world.dominant_body_index(t, st.px, st.py)
        body = world.bodies[soi]
        dx = st.px - body.pos_x(t)
        dy = st.py - body.pos_y(t)
        r = dm.hypot(dx, dy)
        if r <= 0.0:
            return False
        s, c = dm.sincos(st.angle)
        up = (c * dx + s * dy) / r
        g = body.mu / (r * r)
        return (self._thrust * up) > (self._m0 * g)

    def _accel(self, world, prof, t, s, px, py, vx, vy):
        self._ax = 0.0
        self._ay = 0.0
        for b in world.bodies:
            dx = b.pos_x(t) - px
            dy = b.pos_y(t) - py
            r2 = dx * dx + dy * dy
            if r2 <= 0.0:
                continue
            r = math.sqrt(r2)
            if r < b.radius:
                r = b.radius
                r2 = r * r
            f = b.mu / (r2 * r)
            self._ax += f * dx
            self._ay += f * dy

        mass = self._m0
        if self._mdot > 0.0:
            mass = self._m0 - self._mdot * min(s, self._t_cut)
        if mass <= 0.0:
            mass = 1.0e-6

        for b in world.bodies:
            if not b.has_atmosphere():
                continue
            rx = px - b.pos_x(t)
            ry = py - b.pos_y(t)
            alt = dm.hypot(rx, ry) - b.radius
            if alt >= b.atmo_height:
                continue
            rho = b.density_at_altitude(alt)
            if rho <= 0.0:
                continue
            avx = b.vel_x(t) + b.surface_vel_x(rx, ry)
            avy = b.vel_y(t) + b.surface_vel_y(rx, ry)
            rvx = vx - avx
            rvy = vy - avy
            sp = dm.hypot(rvx, rvy)
            if sp <= 0.0:
                continue
            k = 0.5 * rho * prof.drag_coefficient * prof.drag_area * sp / mass
            self._ax -= k * rvx
            self._ay -= k * rvy

        if self._thrust > 0.0 and self._t_cut > 0.0 and s <= self._t_cut:
            ang = self._angle0 + self._w0 * s + 0.5 * self._alpha * s * s
            sn, cs = dm.sincos(ang)
            at = self._thrust / mass
            self._ax += at * cs
            self._ay += at * sn
