"""Port of scripts/missions/*.gd and scripts/sim/sim_runner.gd.

Lets a mission definition be flown end to end from Python, which is how the
star thresholds in missions/*.json are derived: a reference solution is written,
flown here, and the thresholds set from what it actually achieved.
"""

import hashlib
import json
import math
import os
import struct

import det_math as dm
import sim
import ships
import vm as vmod

INF = math.inf
_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.normpath(os.path.join(_HERE, "..", ".."))

MAX_TRAJECTORY_SAMPLES = 4096
MAX_STEPS = 4_000_000
FLAGS = ["landed", "crashed", "out_of_fuel", "program_done", "escaped"]


def load_universe():
    with open(os.path.join(_ROOT, "data", "universe.json")) as f:
        return json.load(f)


# --- predicates -------------------------------------------------------------


class Predicate:
    def __init__(self):
        self.kind = "ALWAYS"
        self.children = []
        self.sensor = None
        self.cmp = "GE"
        self.value = 0.0
        self.lo = self.hi = 0.0
        self.flag = ""
        self.sustain_seconds = 0.0
        self._held = 0.0

    def reset(self):
        self._held = 0.0
        for c in self.children:
            c.reset()

    def check(self, bus, state, vm_, dt):
        k = self.kind
        if k == "ALWAYS":
            return True
        if k == "NEVER":
            return False
        if k == "ALL":
            return all(c.check(bus, state, vm_, dt) for c in self.children)
        if k == "ANY":
            return any(c.check(bus, state, vm_, dt) for c in self.children)
        if k == "NOT":
            return not (not self.children or self.children[0].check(bus, state, vm_, dt))
        if k == "COMPARE":
            return vmod._compare(bus.read(self.sensor), self.cmp, self.value)
        if k == "BETWEEN":
            v = bus.read(self.sensor)
            return self.lo <= v <= self.hi
        if k == "FLAG":
            return self._flag(bus, state, vm_)
        if k == "SUSTAIN":
            inner = bool(self.children) and self.children[0].check(bus, state, vm_, dt)
            self._held = self._held + dt if inner else 0.0
            return self._held >= self.sustain_seconds
        return False

    def _flag(self, bus, state, vm_):
        if self.flag == "landed":
            return state.landed
        if self.flag == "crashed":
            return state.crashed
        if self.flag == "out_of_fuel":
            return state.fuel <= 0.0
        if self.flag == "program_done":
            return vm_ is not None and vm_.is_finished()
        if self.flag == "escaped":
            return math.isinf(bus.read("APO"))
        return False

    def describe(self):
        k = self.kind
        if k == "ALL":
            return " and ".join(c.describe() for c in self.children)
        if k == "ANY":
            return " or ".join(c.describe() for c in self.children)
        if k == "NOT":
            return "not (%s)" % self.children[0].describe()
        if k == "COMPARE":
            words = {"LT": "below", "LE": "at most", "GT": "above",
                     "GE": "at least", "EQ": "exactly", "NE": "not"}
            return "%s %s %g" % (self.sensor.lower(), words[self.cmp], self.value)
        if k == "BETWEEN":
            return "%s between %g and %g" % (self.sensor.lower(), self.lo, self.hi)
        if k == "FLAG":
            return self.flag
        if k == "SUSTAIN":
            return "%s, held for %gs" % (self.children[0].describe(), self.sustain_seconds)
        return k.lower()

    def parts(self):
        return self.children if self.kind == "ALL" else [self]


def _num(v):
    if isinstance(v, str):
        s = v.strip().lower()
        if s in ("inf", "+inf", "infinity"):
            return INF
        if s in ("-inf", "-infinity"):
            return -INF
        return float(s)
    return float(v)


def predicate_from(d, errors):
    p = Predicate()
    if not isinstance(d, dict):
        errors.append("Predicate must be an object.")
        p.kind = "NEVER"
        return p
    for key in ("all", "any"):
        if key in d:
            p.kind = key.upper()
            p.children = [predicate_from(s, errors) for s in d[key]]
            return p
    if "not" in d:
        p.kind = "NOT"
        p.children = [predicate_from(d["not"], errors)]
        return p
    if "sustain" in d:
        p.kind = "SUSTAIN"
        p.sustain_seconds = float(d["sustain"])
        p.children = [predicate_from(d.get("of", {}), errors)]
        return p
    if "flag" in d:
        p.kind = "FLAG"
        p.flag = str(d["flag"])
        if p.flag not in FLAGS:
            errors.append("Unknown flag '%s'." % p.flag)
            p.kind = "NEVER"
        return p
    if "sensor" in d:
        name = str(d["sensor"]).upper()
        if name not in vmod.SENSORS:
            errors.append("Unknown sensor '%s'." % name)
            p.kind = "NEVER"
            return p
        p.sensor = name
        if "between" in d:
            r = d["between"]
            p.kind = "BETWEEN"
            p.lo, p.hi = _num(r[0]), _num(r[1])
            return p
        p.kind = "COMPARE"
        op = str(d.get("op", ">="))
        if op not in vmod.CMP_FROM_TEXT:
            errors.append("'%s' is not a comparison." % op)
            p.kind = "NEVER"
            return p
        p.cmp = vmod.CMP_FROM_TEXT[op]
        p.value = _num(d.get("value", 0.0))
        return p
    errors.append("Predicate has no recognised key.")
    p.kind = "NEVER"
    return p


# --- mission ----------------------------------------------------------------

DEFAULT_TIME_LIMIT = 14400.0


class Mission:
    def __init__(self, d):
        self.errors = []
        self.raw = d
        self.id = d.get("id", "")
        self.title = d.get("title", self.id)
        self.order = int(d.get("order", 0))
        self.brief = d.get("brief", "")
        self.teaches = d.get("teaches", "")
        self.hints = d.get("hints", [])
        self.primary_id = d.get("primary", "halcyon")
        self.body_ids = list(d.get("bodies", [self.primary_id]))
        if self.primary_id not in self.body_ids:
            self.body_ids.append(self.primary_id)
        ship = d.get("ship", {})
        self.ship_policy = ship.get("policy", "stock")
        self.stock_ship_id = ship.get("id", "sparrow")
        self.start_fuel_fraction = float(ship.get("fuel_fraction", 1.0))
        self.start = d.get("start", {})
        self.target_defs = d.get("targets", [])
        self.active_target_id = d.get("active_target", "")
        self.time_limit = float(d.get("time_limit", DEFAULT_TIME_LIMIT))
        self.success = predicate_from(d["success"], self.errors) if "success" in d else None
        if self.success is None:
            self.errors.append("No success predicate.")
        self.failures = [
            dict(predicate=predicate_from(f.get("when", {}), self.errors),
                 message=f.get("message", "Mission failed."))
            for f in d.get("failure", [])]
        stars = d.get("stars", {})
        self.star_fuel = float(stars.get("fuel", INF))
        self.star_time = float(stars.get("time", INF))
        self.star_instructions = int(stars.get("instructions", 1 << 30))

    def ok(self):
        return not self.errors and self.success is not None

    def min_sustain_seconds(self):
        def walk(p):
            if p is None:
                return INF
            best = p.sustain_seconds if (p.kind == "SUSTAIN" and p.sustain_seconds > 0) else INF
            for c in p.children:
                best = min(best, walk(c))
            return best
        return walk(self.success)

    def reset_predicates(self):
        if self.success:
            self.success.reset()
        for f in self.failures:
            f["predicate"].reset()

    def build_world(self, universe):
        world = sim.SimWorld()
        templates = {b["id"]: b for b in universe.get("bodies", [])}
        pd = templates.get(self.primary_id)
        if pd is None:
            self.errors.append("Unknown primary '%s'." % self.primary_id)
            return world
        world.add_body(_body(pd, 0.0))
        for bid in self.body_ids:
            if bid == self.primary_id:
                continue
            if bid not in templates:
                self.errors.append("Unknown body '%s'." % bid)
                continue
            world.add_body(_body(templates[bid], pd["mu"]))
        for td in self.target_defs:
            pid = td.get("body", self.primary_id)
            pi = world.body_index_by_id(pid)
            if pi < 0:
                self.errors.append("Target parent '%s' not in world." % pid)
                continue
            world.targets.append(_target(td, world.bodies[pi], pi))
        return world

    def active_target_index(self, world):
        if not self.active_target_id:
            return 0 if len(world.targets) == 1 else -1
        for i, t in enumerate(world.targets):
            if t.id == self.active_target_id:
                return i
        return -1

    def initial_state(self, world, profile):
        st = sim.ShipState()
        st.fuel = profile.fuel_capacity * max(0.0, min(1.0, self.start_fuel_fraction))
        kind = self.start.get("kind", "surface")
        bi = max(0, world.body_index_by_id(self.start.get("body", self.primary_id)))
        body = world.bodies[bi]
        bx, by = body.pos_x(0.0), body.pos_y(0.0)

        if kind == "state":
            st.px = float(self.start.get("px", 0.0))
            st.py = float(self.start.get("py", 0.0))
            st.vx = float(self.start.get("vx", 0.0))
            st.vy = float(self.start.get("vy", 0.0))
            st.angle = float(self.start.get("angle", 0.0))
            st.landed = bool(self.start.get("landed", False))
        elif kind == "orbit":
            peri = float(self.start.get("periapsis", self.start.get("altitude", 100000.0)))
            apo = float(self.start.get("apoapsis", peri))
            nu = float(self.start.get("true_anomaly", 0.0)) * vmod.DEG_TO_RAD
            arg = float(self.start.get("argument", 0.0)) * vmod.DEG_TO_RAD
            direction = 1.0 if float(self.start.get("direction", 1.0)) >= 0 else -1.0
            rp = body.radius + min(peri, apo)
            ra = body.radius + max(peri, apo)
            a = 0.5 * (rp + ra)
            e = 0.0 if ra + rp <= 0 else (ra - rp) / (ra + rp)
            p = a * (1.0 - e * e)
            r = p / (1.0 + e * dm.cos(nu))
            theta = arg + nu
            s, c = dm.sincos(theta)
            ux, uy = c, s
            tx, ty = -s * direction, c * direction
            k = math.sqrt(body.mu / p) if p > 0 else 0.0
            vr = k * e * dm.sin(nu)
            vt = k * (1.0 + e * dm.cos(nu))
            st.px = bx + r * ux
            st.py = by + r * uy
            st.vx = body.vel_x(0.0) + vr * ux + vt * tx
            st.vy = body.vel_y(0.0) + vr * uy + vt * ty
            st.angle = dm.atan2(st.vy - body.vel_y(0.0), st.vx - body.vel_x(0.0))
        else:
            ang = float(self.start.get("surface_angle", 0.0)) * vmod.DEG_TO_RAD
            s, c = dm.sincos(ang)
            rx, ry = body.radius * c, body.radius * s
            st.px = bx + rx
            st.py = by + ry
            st.vx = body.vel_x(0.0) + body.surface_vel_x(rx, ry)
            st.vy = body.vel_y(0.0) + body.surface_vel_y(rx, ry)
            st.angle = ang
            st.landed = True
        st.soi_index = world.dominant_body_index(0.0, st.px, st.py)
        return st

    def objective_lines(self):
        return [p.describe() for p in self.success.parts()] if self.success else []


def _body(d, primary_mu):
    return sim.CelestialBody(
        id=d["id"], name=d.get("name"), mu=d["mu"], radius=d["radius"],
        rotation_rate=d.get("rotation_rate", 0.0),
        rotation_period=d.get("rotation_period", 0.0),
        orbit_radius=d.get("orbit_radius", 0.0),
        orbit_phase0=d.get("orbit_phase0", 0.0),
        orbit_direction=d.get("orbit_direction", 1),
        tidally_locked=d.get("tidally_locked", False),
        atmosphere=d.get("atmosphere"), primary_mu=primary_mu)


class _Target:
    def __init__(self, d, parent, parent_index):
        self.id = d.get("id", "target")
        self.display_name = d.get("name", self.id)
        self.parent_index = parent_index
        self.orbit_radius = float(d.get("orbit_radius", 0.0))
        self.orbit_phase0 = float(d.get("orbit_phase0", 0.0))
        direction = 1.0 if float(d.get("orbit_direction", 1.0)) >= 0 else -1.0
        self.orbit_mean_motion = (math.sqrt(parent.mu / self.orbit_radius ** 3) * direction
                                  if self.orbit_radius > 0 and parent.mu > 0 else 0.0)
        self._memo_t = None

    def _eval(self, t):
        if t == self._memo_t:
            return
        s, c = dm.sincos(self.orbit_phase0 + self.orbit_mean_motion * t)
        self._rel_x = self.orbit_radius * c
        self._rel_y = self.orbit_radius * s
        self._rel_vx = -self.orbit_radius * self.orbit_mean_motion * s
        self._rel_vy = self.orbit_radius * self.orbit_mean_motion * c
        self._memo_t = t

    def rel_x(self, t):
        self._eval(t)
        return self._rel_x

    def rel_y(self, t):
        self._eval(t)
        return self._rel_y

    def rel_vx(self, t):
        self._eval(t)
        return self._rel_vx

    def rel_vy(self, t):
        self._eval(t)
        return self._rel_vy


def _target(d, parent, pi):
    return _Target(d, parent, pi)


# --- result and scoring -----------------------------------------------------


class RunResult:
    def __init__(self):
        self.mission_id = ""
        self.success = False
        self.outcome = ""
        self.outcome_detail = ""
        self.fuel_used = 0.0
        self.ticks = 0
        self.elapsed = 0.0
        self.instruction_count = 0
        self.instructions_executed = 0
        self.fuel_remaining = 0.0
        self.delta_v_used = 0.0
        self.max_altitude = 0.0
        self.max_dynamic_pressure = 0.0
        self.touchdown_speed = -1.0
        self.spin_ticks = 0
        self.stars = 0
        self.star_fuel = self.star_time = self.star_instructions = False
        self.vm_status = ""
        self.fault_code = self.fault_message = self.fault_hint = ""
        self.fault_line = 0
        self.state_hash = ""
        self.program_hash = ""
        self.log_entries = []
        self.trajectory = []


def apply_scoring(mission, result):
    result.star_fuel = result.star_time = result.star_instructions = False
    result.stars = 0
    if not result.success:
        return
    result.star_fuel = result.fuel_used <= mission.star_fuel
    result.star_time = result.elapsed <= mission.star_time
    result.star_instructions = result.instruction_count <= mission.star_instructions
    result.stars = sum((result.star_fuel, result.star_time, result.star_instructions))


# --- the runner -------------------------------------------------------------


class SimRunner:
    def __init__(self):
        self.integrator = sim.Integrator()
        self.ctrl = sim.ControlInput()
        self.finished = False

    def setup(self, mission, world, profile, program, ship_hash="", seed=0):
        self.mission = mission
        self.world = world
        self.profile = profile
        world.seed = seed
        self.state = mission.initial_state(world, profile)
        self.vm = vmod.ControllerVM(program)
        self.bus = vmod.SensorBus(world, profile)
        self.bus.target_index = mission.active_target_index(world)
        mission.reset_predicates()
        self.result = RunResult()
        self.result.mission_id = mission.id
        self.result.instruction_count = program.instruction_count() if program else 0
        self.result.program_hash = program.content_hash() if program else ""
        self.finished = False
        self._steps = 0
        self._sample_stride = 1
        self._last_throttle = 0.0
        self._snapshot = self.state.copy()
        ms = mission.min_sustain_seconds()
        self._sustain_slack = INF if math.isinf(ms) else max(sim.DT_BASE, ms * 0.25)
        self._escape_distance = world.primary.radius * 100.0
        for b in world.bodies:
            if b.orbit_radius > 0:
                self._escape_distance = max(self._escape_distance, b.orbit_radius * 5.0)
        if program is not None and not program.ok():
            self._fail("The program did not assemble.", program.first_error_text())
        self._record(True)

    def step(self):
        if self.finished:
            return False
        self.bus.begin_tick(self.state, self._last_throttle)
        self.vm.tick(self.bus, self.state, self.profile, self.ctrl, sim.DT_BASE)

        t = sim.SimWorld.time_for_tick(self.state.tick)
        slack = min(self.vm.vm_slack(self.state.tick), self._sustain_slack)
        scale = self.world.step_scale_for(t, self.state, self.ctrl, self.profile, slack)

        self._snapshot = self.state.copy()
        self.integrator.step(self.world, self.state, self.ctrl, self.profile, scale)
        while scale > 1 and self._event_fired():
            self.state = self._snapshot.copy()
            scale //= 2
            self.integrator.step(self.world, self.state, self.ctrl, self.profile, scale)

        dt = sim.DT_BASE * scale
        self._steps += 1
        self._last_throttle = self.ctrl.throttle
        self.bus.begin_tick(self.state, self.ctrl.throttle)
        self._observe()
        self._record(False)
        self._check_surface()
        self._check_limits()
        if not self.finished:
            self._check_mission(dt)
        if self._steps >= MAX_STEPS and not self.finished:
            self._fail("The flight ran too long to finish.", "")
        return not self.finished

    def run(self, step_limit=MAX_STEPS):
        n = 0
        while not self.finished and n < step_limit:
            self.step()
            n += 1
        if not self.finished:
            self._fail("The flight was cut short.", "Step limit reached.")
        return self.result

    def _event_fired(self):
        self.bus.begin_tick(self.state, self.ctrl.throttle)
        if self.vm.has_watched_condition() and self.vm.watched_condition_holds(self.bus):
            return True
        return self.bus.altitude() <= 0.0

    def _check_surface(self):
        st = self.state
        if self.finished or st.crashed or st.landed or self.bus.altitude() > 0.0:
            return
        body = self.bus.body()
        t = sim.SimWorld.time_for_tick(st.tick)
        rx, ry = st.px - body.pos_x(t), st.py - body.pos_y(t)
        r = dm.hypot(rx, ry) or body.radius
        gvx = body.vel_x(t) + body.surface_vel_x(rx, ry)
        gvy = body.vel_y(t) + body.surface_vel_y(rx, ry)
        impact = dm.hypot(st.vx - gvx, st.vy - gvy)
        self.result.touchdown_speed = impact
        s, c = dm.sincos(st.angle)
        upright = (c * rx + s * ry) / r
        gear = self.profile.max_landing_speed
        if gear > 0.0 and impact <= gear and upright >= 0.7071:
            st.landed = True
            k = body.radius / r
            st.px = body.pos_x(t) + rx * k
            st.py = body.pos_y(t) + ry * k
            st.vx, st.vy = gvx, gvy
            st.ang_vel = 0.0
            self.bus.begin_tick(st, self.ctrl.throttle)
            return
        st.crashed = True
        self._fail("Destroyed on contact with %s." % body.display_name,
                   "Touchdown at %.1f m/s (gear rated %.0f)." % (impact, gear))

    def _check_limits(self):
        if self.finished:
            return
        if self.vm.status == "FAULTED":
            self._fail(self.vm.fault_message, self.vm.fault_hint)
            return
        if sim.SimWorld.time_for_tick(self.state.tick) > self.mission.time_limit:
            self._fail("Out of time.", "")
            return
        if dm.hypot(self.state.px, self.state.py) > self._escape_distance:
            self._fail("Lost.", "")

    def _check_mission(self, dt):
        for f in self.mission.failures:
            if f["predicate"].check(self.bus, self.state, self.vm, dt):
                self._fail(f["message"], "")
                return
        if self.mission.success and self.mission.success.check(self.bus, self.state, self.vm, dt):
            self._finalise()
            self.result.success = True
            self.result.outcome = "Objective complete."
            apply_scoring(self.mission, self.result)
            self.finished = True

    def _fail(self, outcome, detail):
        if self.finished:
            return
        self._finalise()
        self.result.success = False
        self.result.outcome = outcome
        self.result.outcome_detail = detail
        apply_scoring(self.mission, self.result)
        self.finished = True

    def _finalise(self):
        r, st = self.result, self.state
        r.ticks = st.tick
        r.elapsed = sim.SimWorld.time_for_tick(st.tick)
        r.fuel_remaining = st.fuel
        start_fuel = self.profile.fuel_capacity * self.mission.start_fuel_fraction
        r.fuel_used = max(0.0, start_fuel - st.fuel)
        r.delta_v_used = self.profile.delta_v(start_fuel) - self.profile.delta_v(st.fuel)
        r.instructions_executed = self.vm.instructions_executed
        r.spin_ticks = self.vm.spin_ticks
        r.vm_status = self.vm.status_text()
        r.fault_code = self.vm.fault_code
        r.fault_message = self.vm.fault_message
        r.fault_line = self.vm.fault_line
        r.log_entries = list(self.vm.log_entries)
        r.state_hash = self.state_hash()
        self._record(True)

    def _observe(self):
        r = self.result
        r.max_altitude = max(r.max_altitude, self.bus.altitude())
        r.max_dynamic_pressure = max(r.max_dynamic_pressure, self.bus.dynamic_pressure())

    def _record(self, force):
        if not force and (self._steps % self._sample_stride) != 0:
            return
        st = self.state
        self.result.trajectory.append((
            sim.SimWorld.time_for_tick(st.tick), st.px, st.py, st.vx, st.vy,
            st.fuel, st.angle, self.ctrl.throttle))
        if len(self.result.trajectory) > MAX_TRAJECTORY_SAMPLES:
            self.result.trajectory = self.result.trajectory[::2]
            self._sample_stride *= 2

    def state_hash(self):
        st = self.state
        raw = struct.pack("<7d", st.px, st.py, st.vx, st.vy, st.angle, st.ang_vel, st.fuel)
        raw += struct.pack("<q", st.tick)
        return hashlib.sha256(raw).hexdigest()[:16]


def fly(mission_dict, source, ship_id=None, seed=0, universe=None):
    """Convenience: assemble `source`, fly `mission_dict`, return (result, mission)."""
    m = Mission(mission_dict)
    world = m.build_world(universe or load_universe())
    design = ships.stock(ship_id or m.stock_ship_id)
    profile = design.to_profile()
    prog = vmod.assemble(source)
    r = SimRunner()
    r.setup(m, world, profile, prog, seed=seed)
    return r.run(), m, prog
