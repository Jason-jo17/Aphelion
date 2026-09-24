"""Port of scripts/controller_vm/*.gd — the flight computer.

Mirrors the GDScript line for line so that reference solutions flown here
produce exactly the numbers the game will produce. That is what makes the star
thresholds in missions/*.json trustworthy: every one of them was earned by a
program that actually flew the mission.

See docs/ISA.md for the language.
"""

import math

import det_math as dm
import sim

# Derived, not written out; see the note in scripts/controller_vm/sensor_bus.gd.
RAD_TO_DEG = 180.0 / dm.PI_D
DEG_TO_RAD = dm.PI_D / 180.0
INF = math.inf

# --- ISA --------------------------------------------------------------------

OPS_BLOCKING = {"HALT", "ORIENT", "BURN", "BURN_UNTIL", "WAIT", "WAIT_UNTIL"}

CMP_FROM_TEXT = {"<": "LT", "<=": "LE", ">": "GT", ">=": "GE",
                 "==": "EQ", "!=": "NE", "=": "EQ", "<>": "NE"}

GOALS = {"PROGRADE": "PROGRADE", "RETROGRADE": "RETROGRADE", "RADIAL": "RADIAL",
         "ANTIRADIAL": "ANTIRADIAL", "TARGET": "TARGET",
         "PRO": "PROGRADE", "RETRO": "RETROGRADE", "UP": "RADIAL", "DOWN": "ANTIRADIAL"}

SENSORS = {
    "ALT", "VEL", "VVEL", "HVEL", "APO", "PERI", "ECC", "SMA", "TAPO", "TPERI",
    "HDG", "PRO", "RETRO", "RAD", "ANTIRAD", "PITCH", "FUEL", "MASS", "DV",
    "TWR", "THR", "GRAV", "DENS", "Q", "T", "SOI", "LANDED", "TGTD", "TGTV", "TGTA",
}
ANGLE_SENSORS = {"HDG", "PRO", "RETRO", "RAD", "ANTIRAD", "PITCH", "TGTA"}

CONSTANTS = {"INF": INF, "PI": dm.PI_D, "TAU": dm.TAU_D, "TRUE": 1.0, "FALSE": 0.0}

ARITH = {"SET", "ADD", "SUB", "MUL", "DIV", "MOD", "MIN", "MAX", "SENSE"}
REGISTER_COUNT = 8


class Operand:
    __slots__ = ("kind", "value", "index", "sensor", "goal", "text")

    def __init__(self, kind, value=0.0, index=0, sensor=None, goal=None, text=""):
        self.kind = kind          # LITERAL | REGISTER | SENSOR | GOAL
        self.value = value
        self.index = index
        self.sensor = sensor
        self.goal = goal
        self.text = text

    def __repr__(self):
        return self.text


class Instruction:
    __slots__ = ("op", "a", "b", "cmp", "target", "label_name", "line", "source_text")

    def __init__(self, op, a=None, b=None):
        self.op = op
        self.a = a
        self.b = b
        self.cmp = "LT"
        self.target = -1
        self.label_name = ""
        self.line = 0
        self.source_text = ""

    def to_text(self):
        if self.op in ("HALT", "NOP"):
            return self.op
        if self.op == "JMP":
            return "JMP %s" % self.label_name
        sym = [k for k, v in CMP_FROM_TEXT.items() if v == self.cmp and k in
               ("<", "<=", ">", ">=", "==", "!=")][0]
        if self.op == "IF":
            return "IF %s %s %s" % (self.a, sym, self.b)
        if self.op == "BURN_UNTIL":
            return "BURN UNTIL %s %s %s" % (self.a, sym, self.b)
        if self.op == "WAIT_UNTIL":
            return "WAIT UNTIL %s %s %s" % (self.a, sym, self.b)
        if self.op == "ORIENT":
            return "ORIENT %s, %s" % (self.a, self.b) if self.b else "ORIENT %s" % self.a
        if self.op in ("ABS", "NEG", "POINT", "THROTTLE", "BURN", "WAIT", "LOG"):
            return "%s %s" % (self.op, self.a)
        return "%s %s, %s" % (self.op, self.a, self.b)


class Program:
    def __init__(self):
        self.instructions = []
        self.labels = {}
        self.errors = []
        self.source = ""

    def ok(self):
        return not self.errors and bool(self.instructions)

    def instruction_count(self):
        return len(self.instructions)

    def add_error(self, line, text, message, hint=""):
        self.errors.append(dict(line=line, text=text, message=message, hint=hint))

    def content_hash(self):
        import hashlib
        body = "\n".join(i.to_text() for i in self.instructions)
        return hashlib.sha256(body.encode()).hexdigest()[:16]

    def first_error_text(self):
        if not self.errors:
            return ""
        e = self.errors[0]
        return "Line %d: %s %s" % (e["line"], e["message"], e["hint"])


# --- assembler --------------------------------------------------------------

_TWO = ("<=", ">=", "==", "!=", "<>")
_ONE = ("<", ">", "=")


def _tokenize(line):
    out, i, n = [], 0, len(line)
    while i < n:
        ch = line[i]
        if ch == ";":
            break
        if ch in " \t,\r":
            i += 1
            continue
        if line[i:i + 2] in _TWO:
            out.append(line[i:i + 2])
            i += 2
            continue
        if ch in _ONE:
            out.append(ch)
            i += 1
            continue
        start = i
        while i < n:
            c = line[i]
            if c in " \t,;\r" or c in _ONE:
                break
            if c == ":":
                i += 1
                break
            i += 1
        if i > start:
            out.append(line[start:i])
        else:
            i += 1
    return out


def _operand(prog, line_no, token, allow_goal):
    up = token.upper()
    if allow_goal and up in GOALS:
        return Operand("GOAL", goal=GOALS[up], text=up)
    if len(up) >= 2 and up[0] == "R" and up[1:].isdigit():
        idx = int(up[1:])
        if not (0 <= idx < REGISTER_COUNT):
            prog.add_error(line_no, token, "There is no register %s." % token, "")
            return None
        return Operand("REGISTER", index=idx, text=up)
    if up in SENSORS:
        return Operand("SENSOR", sensor=up, text=up)
    if up in CONSTANTS:
        return Operand("LITERAL", value=CONSTANTS[up], text=up)
    try:
        return Operand("LITERAL", value=float(token), text=token)
    except ValueError:
        prog.add_error(line_no, token,
                       "'%s' is not a number, a register or a sensor." % token, "")
        return None


def assemble(source):
    prog = Program()
    prog.source = source
    pending = []
    for li, raw in enumerate(source.split("\n")):
        line_no = li + 1
        tokens = _tokenize(raw)
        if not tokens:
            continue
        while tokens and tokens[0].endswith(":"):
            name = tokens[0][:-1].upper()
            if not name:
                prog.add_error(line_no, tokens[0], "A label needs a name.", "")
            elif name in prog.labels or name in pending:
                prog.add_error(line_no, tokens[0], "Label '%s' is already defined." % name, "")
            else:
                pending.append(name)
            tokens.pop(0)
        if not tokens:
            continue
        ins = _parse(prog, line_no, raw.strip(), tokens)
        if ins is None:
            continue
        for lbl in pending:
            prog.labels[lbl] = len(prog.instructions)
        pending = []
        prog.instructions.append(ins)
    for lbl in pending:
        prog.labels[lbl] = len(prog.instructions)
    for ins in prog.instructions:
        if ins.op == "JMP":
            key = ins.label_name.upper()
            if key not in prog.labels:
                prog.add_error(ins.line, ins.label_name,
                               "No label called '%s'." % ins.label_name, "")
            else:
                ins.target = prog.labels[key]
    return prog


def _parse(prog, line_no, raw, tokens):
    mnem = tokens[0].upper()
    args = tokens[1:]
    ins = Instruction(mnem)
    ins.line = line_no
    ins.source_text = raw

    if mnem in ("BURN", "WAIT") and args and args[0].upper() == "UNTIL":
        ins.op = mnem + "_UNTIL"
        return ins if _condition(prog, ins, line_no, args[1:]) else None

    if mnem in ("HALT", "NOP", "STAGE"):
        if mnem == "STAGE":
            ins.op = "NOP"
        return ins
    if mnem in ("ABS", "NEG"):
        if len(args) != 1:
            prog.add_error(line_no, raw, "%s takes one register." % mnem, "")
            return None
        ins.a = _operand(prog, line_no, args[0], False)
        return ins if ins.a and ins.a.kind == "REGISTER" else None
    if mnem in ARITH:
        if len(args) != 2:
            prog.add_error(line_no, raw, "%s takes a register and a value." % mnem, "")
            return None
        ins.a = _operand(prog, line_no, args[0], False)
        ins.b = _operand(prog, line_no, args[1], False)
        if not ins.a or not ins.b or ins.a.kind != "REGISTER":
            prog.add_error(line_no, raw, "%s needs a writable register first." % mnem, "")
            return None
        if mnem == "SENSE" and ins.b.kind != "SENSOR":
            prog.add_error(line_no, args[1], "SENSE reads a sensor.", "")
            return None
        return ins
    if mnem == "JMP":
        if len(args) != 1:
            prog.add_error(line_no, raw, "JMP takes one label.", "")
            return None
        ins.label_name = args[0]
        return ins
    if mnem == "IF":
        return ins if _condition(prog, ins, line_no, args) else None
    if mnem in ("POINT", "THROTTLE", "BURN", "WAIT", "LOG"):
        if len(args) != 1:
            prog.add_error(line_no, raw, "%s takes one value." % mnem, "")
            return None
        ins.a = _operand(prog, line_no, args[0], mnem == "POINT")
        return ins if ins.a else None
    if mnem == "ORIENT":
        if not 1 <= len(args) <= 2:
            prog.add_error(line_no, raw, "ORIENT takes a target and optional tolerance.", "")
            return None
        ins.a = _operand(prog, line_no, args[0], True)
        if len(args) == 2:
            ins.b = _operand(prog, line_no, args[1], False)
            if not ins.b:
                return None
        return ins if ins.a else None
    prog.add_error(line_no, tokens[0], "Unknown instruction '%s'." % tokens[0], "")
    return None


def _condition(prog, ins, line_no, args):
    if len(args) != 3:
        prog.add_error(line_no, " ".join(args), "Needs value, operator, value.", "")
        return False
    if args[1] not in CMP_FROM_TEXT:
        prog.add_error(line_no, args[1], "'%s' is not a comparison." % args[1], "")
        return False
    ins.cmp = CMP_FROM_TEXT[args[1]]
    ins.a = _operand(prog, line_no, args[0], False)
    ins.b = _operand(prog, line_no, args[2], False)
    return ins.a is not None and ins.b is not None


# --- sensor bus -------------------------------------------------------------


def _to_compass(rad):
    return dm.wrap_tau(rad) * RAD_TO_DEG


class SensorBus:
    def __init__(self, world, profile):
        self.world = world
        self.profile = profile
        self.target_index = -1
        self._state = None
        self._t = 0.0
        self._soi = 0
        self._body = None
        self._elems = {}
        self._rx = self._ry = self._rvx = self._rvy = 0.0
        self._radius = 0.0
        self._throttle = 0.0

    def begin_tick(self, state, throttle):
        self._state = state
        self._throttle = throttle
        self._t = sim.SimWorld.time_for_tick(state.tick)
        self._soi = self.world.dominant_body_index(self._t, state.px, state.py)
        self._body = self.world.bodies[self._soi]
        state.soi_index = self._soi
        b, t = self._body, self._t
        self._rx = state.px - b.pos_x(t)
        self._ry = state.py - b.pos_y(t)
        self._rvx = state.vx - b.vel_x(t)
        self._rvy = state.vy - b.vel_y(t)
        self._radius = dm.hypot(self._rx, self._ry)
        self._elems = sim.elements(b.mu, self._rx, self._ry, self._rvx, self._rvy)

    def body(self):
        return self._body

    def soi_index(self):
        return self._soi

    def elements(self):
        return self._elems

    def altitude(self):
        return self._radius - self._body.radius

    def prograde_rad(self):
        if self._rvx == 0.0 and self._rvy == 0.0:
            return self._state.angle
        return dm.atan2(self._rvy, self._rvx)

    def radial_rad(self):
        if self._rx == 0.0 and self._ry == 0.0:
            return self._state.angle
        return dm.atan2(self._ry, self._rx)

    def _target(self):
        if not (0 <= self.target_index < len(self.world.targets)):
            return None
        tg = self.world.targets[self.target_index]
        return tg, self.world.bodies[tg.parent_index]

    def target_rad(self):
        got = self._target()
        if not got:
            return self._state.angle
        tg, parent = got
        dx = parent.pos_x(self._t) + tg.rel_x(self._t) - self._state.px
        dy = parent.pos_y(self._t) + tg.rel_y(self._t) - self._state.py
        if dx == 0.0 and dy == 0.0:
            return self._state.angle
        return dm.atan2(dy, dx)

    def target_distance(self):
        got = self._target()
        if not got:
            return INF
        tg, parent = got
        return dm.hypot(parent.pos_x(self._t) + tg.rel_x(self._t) - self._state.px,
                        parent.pos_y(self._t) + tg.rel_y(self._t) - self._state.py)

    def target_relative_speed(self):
        got = self._target()
        if not got:
            return INF
        tg, parent = got
        return dm.hypot(parent.vel_x(self._t) + tg.rel_vx(self._t) - self._state.vx,
                        parent.vel_y(self._t) + tg.rel_vy(self._t) - self._state.vy)

    def local_gravity(self):
        if self._radius <= 0.0:
            return 0.0
        return self._body.mu / (self._radius * self._radius)

    def dynamic_pressure(self):
        rho = self._body.density_at_altitude(self.altitude())
        if rho <= 0.0:
            return 0.0
        avx = self._body.vel_x(self._t) + self._body.surface_vel_x(self._rx, self._ry)
        avy = self._body.vel_y(self._t) + self._body.surface_vel_y(self._rx, self._ry)
        sp = dm.hypot(self._state.vx - avx, self._state.vy - avy)
        return 0.5 * rho * sp * sp

    def read(self, s):
        e, st, b = self._elems, self._state, self._body
        if s == "ALT":
            return self.altitude()
        if s == "VEL":
            return dm.hypot(self._rvx, self._rvy)
        if s == "VVEL":
            return e["v_radial"]
        if s == "HVEL":
            return abs(e["v_tangential"])
        if s == "APO":
            ap = e["apoapsis"]
            return INF if math.isinf(ap) else ap - b.radius
        if s == "PERI":
            return e["periapsis"] - b.radius
        if s == "ECC":
            return e["ecc"]
        if s == "SMA":
            return e["sma"]
        if s == "TAPO":
            return e["t_apo"]
        if s == "TPERI":
            return e["t_peri"]
        if s == "HDG":
            return _to_compass(st.angle)
        if s == "PRO":
            return _to_compass(self.prograde_rad())
        if s == "RETRO":
            return _to_compass(self.prograde_rad() + dm.PI_D)
        if s == "RAD":
            return _to_compass(self.radial_rad())
        if s == "ANTIRAD":
            return _to_compass(self.radial_rad() + dm.PI_D)
        if s == "PITCH":
            return dm.angle_delta(st.angle, self.prograde_rad()) * RAD_TO_DEG
        if s == "FUEL":
            return st.fuel
        if s == "MASS":
            return self.profile.dry_mass + st.fuel
        if s == "DV":
            return self.profile.delta_v(st.fuel)
        if s == "TWR":
            g = self.local_gravity()
            m = self.profile.dry_mass + st.fuel
            return 0.0 if (g <= 0.0 or m <= 0.0) else self.profile.max_thrust / (m * g)
        if s == "THR":
            return self._throttle
        if s == "GRAV":
            return self.local_gravity()
        if s == "DENS":
            return b.density_at_altitude(self.altitude())
        if s == "Q":
            return self.dynamic_pressure()
        if s == "T":
            return self._t
        if s == "SOI":
            return float(self._soi)
        if s == "LANDED":
            return 1.0 if st.landed else 0.0
        if s == "TGTD":
            return self.target_distance()
        if s == "TGTV":
            return self.target_relative_speed()
        if s == "TGTA":
            return _to_compass(self.target_rad())
        return 0.0


# --- attitude ---------------------------------------------------------------

DEFAULT_TOLERANCE_DEG = 0.5
CONVERGENCE_TIMEOUT = 300.0
RATE_EPSILON = 1.0e-6


class AttitudeController:
    def __init__(self):
        self.goal_kind = "ABSOLUTE"
        self.goal_angle = 0.0
        self.tolerance = DEFAULT_TOLERANCE_DEG * DEG_TO_RAD
        self.active = False

    def set_goal(self, kind, angle_rad=0.0):
        self.goal_kind = kind
        self.goal_angle = angle_rad
        self.active = True

    def set_tolerance_deg(self, deg):
        self.tolerance = max(0.01, abs(deg)) * DEG_TO_RAD

    def desired_heading(self, bus):
        k = self.goal_kind
        if k == "PROGRADE":
            return bus.prograde_rad()
        if k == "RETROGRADE":
            return bus.prograde_rad() + dm.PI_D
        if k == "RADIAL":
            return bus.radial_rad()
        if k == "ANTIRADIAL":
            return bus.radial_rad() + dm.PI_D
        if k == "TARGET":
            return bus.target_rad()
        return self.goal_angle

    def error(self, state, bus):
        return dm.angle_delta(state.angle, self.desired_heading(bus))

    def torque_for(self, state, profile, bus, dt):
        if not self.active:
            return 0.0
        alpha = self.angular_authority(profile)
        if alpha <= 0.0 or dt <= 0.0:
            return 0.0
        err = self.error(state, bus)
        w = state.ang_vel
        if abs(err) <= self.tolerance:
            return max(-1.0, min(1.0, -w / (alpha * dt)))
        stop = (w * w) / (2.0 * alpha)
        residual = err - stop if w > 0.0 else (err + stop if w < 0.0 else err)
        return 1.0 if residual > 0.0 else (-1.0 if residual < 0.0 else 0.0)

    def at_goal(self, state, bus):
        if not self.active:
            return True
        return abs(self.error(state, bus)) <= self.tolerance and abs(state.ang_vel) <= RATE_EPSILON

    @staticmethod
    def angular_authority(profile):
        if profile.inertia <= 0.0:
            return 0.0
        return profile.max_torque / profile.inertia

    def reset(self):
        self.__init__()


# --- the VM -----------------------------------------------------------------

DEFAULT_TICK_BUDGET = 64
DEFAULT_TOTAL_BUDGET = 5_000_000


def _compare(a, c, b):
    if c == "LT":
        return a < b
    if c == "LE":
        return a <= b
    if c == "GT":
        return a > b
    if c == "GE":
        return a >= b
    if c == "EQ":
        return a == b
    return a != b


class ControllerVM:
    def __init__(self, program=None):
        self.registers = [0.0] * REGISTER_COUNT
        self.attitude = AttitudeController()
        self.program = program
        self.tick_budget = DEFAULT_TICK_BUDGET
        self.total_budget = DEFAULT_TOTAL_BUDGET
        self.reset()

    def reset(self):
        self.registers = [0.0] * REGISTER_COUNT
        self.pc = 0
        self.instructions_executed = 0
        self.spin_ticks = 0
        self.total_ticks = 0
        self.log_entries = []
        self.throttle_setting = 1.0
        self._block = "NONE"
        self._block_thrusting = False
        self._block_end_tick = 0
        self._cond_a = self._cond_b = None
        self._cond_cmp = "LT"
        self._orient_deadline_tick = 0
        self._block_line = 0
        self.attitude.reset()
        self.fault_code = self.fault_message = self.fault_hint = ""
        self.fault_line = 0
        if self.program is None or not self.program.ok():
            self.status = "FAULTED" if (self.program and self.program.errors) else "READY"
            if self.program is not None and not self.program.instructions and not self.program.errors:
                self._fault("no_program", "The flight computer has no program.", "", 0)
        else:
            self.status = "RUNNING"

    def is_finished(self):
        return self.status in ("HALTED", "FAULTED")

    def status_text(self):
        return {"READY": "not started", "RUNNING": "still running",
                "HALTED": "program finished"}.get(
            self.status, "fault: %s" % self.fault_message)

    def tick(self, bus, state, profile, ctrl, dt):
        self.total_ticks += 1
        ctrl.throttle = 0.0
        if self.status == "RUNNING":
            budget = self.tick_budget
            while True:
                if self._block != "NONE":
                    if not self._try_unblock(bus, state, profile):
                        break
                if self.status != "RUNNING":
                    break
                if budget <= 0:
                    self.spin_ticks += 1
                    break
                if self.instructions_executed >= self.total_budget:
                    self._fault("instruction_cap", "Instruction cap reached.", "",
                                self._current_line())
                    break
                self._execute_one(bus, state, profile)
                budget -= 1
        if self.status == "RUNNING" and self._block_thrusting and state.fuel > 0.0:
            ctrl.throttle = self.throttle_setting
        ctrl.torque = self.attitude.torque_for(state, profile, bus, dt)

    def vm_slack(self, current_tick):
        if self.status != "RUNNING":
            return INF
        if self._block == "TIMER":
            return max(0.0, (self._block_end_tick - current_tick) * sim.DT_BASE)
        if self._block in ("CONDITION", "ORIENT"):
            return INF
        return 0.0

    def has_watched_condition(self):
        return self.status == "RUNNING" and self._block == "CONDITION"

    def watched_condition_holds(self, bus):
        if self._block != "CONDITION" or self._cond_a is None:
            return False
        return _compare(self._read(self._cond_a, bus), self._cond_cmp,
                        self._read(self._cond_b, bus))

    def _try_unblock(self, bus, state, profile):
        if self._block == "TIMER":
            if self._block_thrusting and state.fuel <= 0.0:
                self._clear()
                return True
            if state.tick >= self._block_end_tick:
                self._clear()
                return True
            return False
        if self._block == "CONDITION":
            if self._block_thrusting and state.fuel <= 0.0:
                self._clear()
                return True
            if self.watched_condition_holds(bus):
                self._clear()
                return True
            return False
        if self._block == "ORIENT":
            if self.attitude.at_goal(state, bus):
                self._clear()
                return True
            if state.tick >= self._orient_deadline_tick:
                self._fault("orient_timeout", "ORIENT did not settle.", "", self._block_line)
                self._clear()
            return False
        return True

    def _clear(self):
        self._block = "NONE"
        self._block_thrusting = False
        self._cond_a = self._cond_b = None

    def _begin_timer(self, seconds, thrusting, state, line):
        ticks = int(max(0.0, seconds) / sim.DT_BASE + 0.5)
        self._block = "TIMER"
        self._block_thrusting = thrusting
        self._block_end_tick = state.tick + max(0, ticks)
        self._block_line = line

    def _begin_condition(self, a, c, b, thrusting, line):
        self._block = "CONDITION"
        self._block_thrusting = thrusting
        self._cond_a, self._cond_cmp, self._cond_b = a, c, b
        self._block_line = line

    def _execute_one(self, bus, state, profile):
        if not (0 <= self.pc < len(self.program.instructions)):
            self.status = "HALTED"
            return
        ins = self.program.instructions[self.pc]
        self.instructions_executed += 1
        self.pc += 1
        op = ins.op
        rd = self._read

        if op == "NOP":
            return
        if op in ("SET", "SENSE"):
            self._write(ins.a, rd(ins.b, bus))
        elif op == "ADD":
            self._write(ins.a, rd(ins.a, bus) + rd(ins.b, bus))
        elif op == "SUB":
            self._write(ins.a, rd(ins.a, bus) - rd(ins.b, bus))
        elif op == "MUL":
            self._write(ins.a, rd(ins.a, bus) * rd(ins.b, bus))
        elif op == "DIV":
            d = rd(ins.b, bus)
            if d == 0.0:
                return self._fault("divide_by_zero", "Division by zero.", "", ins.line)
            self._write(ins.a, rd(ins.a, bus) / d)
        elif op == "MOD":
            m = rd(ins.b, bus)
            if m == 0.0:
                return self._fault("divide_by_zero", "MOD by zero.", "", ins.line)
            self._write(ins.a, dm.fmod_exact(rd(ins.a, bus), m))
        elif op == "MIN":
            self._write(ins.a, min(rd(ins.a, bus), rd(ins.b, bus)))
        elif op == "MAX":
            self._write(ins.a, max(rd(ins.a, bus), rd(ins.b, bus)))
        elif op == "ABS":
            self._write(ins.a, abs(rd(ins.a, bus)))
        elif op == "NEG":
            self._write(ins.a, -rd(ins.a, bus))
        elif op == "JMP":
            if ins.target < 0:
                return self._fault("bad_jump", "Undefined label.", "", ins.line)
            self.pc = ins.target
        elif op == "IF":
            if not _compare(rd(ins.a, bus), ins.cmp, rd(ins.b, bus)):
                self.pc += 1
        elif op == "HALT":
            self.status = "HALTED"
        elif op == "THROTTLE":
            self.throttle_setting = max(0.0, min(1.0, rd(ins.a, bus)))
        elif op == "LOG":
            if len(self.log_entries) < 500:
                self.log_entries.append(dict(t=bus.read("T"), line=ins.line,
                                             label=str(ins.a), value=rd(ins.a, bus)))
        elif op == "POINT":
            self._apply_goal(ins.a, bus)
        elif op == "ORIENT":
            if profile.max_torque <= 0.0:
                return self._fault("no_attitude_control", "ORIENT with no reaction wheel.",
                                   "", ins.line)
            self._apply_goal(ins.a, bus)
            self.attitude.set_tolerance_deg(
                rd(ins.b, bus) if ins.b is not None else DEFAULT_TOLERANCE_DEG)
            if not self.attitude.at_goal(state, bus):
                self._block = "ORIENT"
                self._block_thrusting = False
                self._block_line = ins.line
                self._orient_deadline_tick = state.tick + int(CONVERGENCE_TIMEOUT / sim.DT_BASE)
        elif op == "BURN":
            self._begin_timer(rd(ins.a, bus), True, state, ins.line)
        elif op == "WAIT":
            self._begin_timer(rd(ins.a, bus), False, state, ins.line)
        elif op == "BURN_UNTIL":
            if not _compare(rd(ins.a, bus), ins.cmp, rd(ins.b, bus)):
                self._begin_condition(ins.a, ins.cmp, ins.b, True, ins.line)
        elif op == "WAIT_UNTIL":
            if not _compare(rd(ins.a, bus), ins.cmp, rd(ins.b, bus)):
                self._begin_condition(ins.a, ins.cmp, ins.b, False, ins.line)

    def _apply_goal(self, o, bus):
        if o.kind == "GOAL":
            self.attitude.set_goal(o.goal)
        else:
            self.attitude.set_goal("ABSOLUTE", self._read(o, bus) * DEG_TO_RAD)

    def _goal_heading(self, goal, bus):
        if goal == "PROGRADE":
            return bus.prograde_rad()
        if goal == "RETROGRADE":
            return bus.prograde_rad() + dm.PI_D
        if goal == "RADIAL":
            return bus.radial_rad()
        if goal == "ANTIRADIAL":
            return bus.radial_rad() + dm.PI_D
        if goal == "TARGET":
            return bus.target_rad()
        return 0.0

    def _read(self, o, bus):
        if o is None:
            return 0.0
        if o.kind == "LITERAL":
            return o.value
        if o.kind == "REGISTER":
            return self.registers[o.index]
        if o.kind == "SENSOR":
            return bus.read(o.sensor)
        if o.kind == "GOAL":
            return _to_compass(self._goal_heading(o.goal, bus))
        return 0.0

    def _write(self, o, v):
        if o is None or o.kind != "REGISTER":
            return self._fault("bad_register", "Not a register.", "", self._current_line())
        self.registers[o.index] = v

    def _fault(self, code, message, hint, line):
        self.status = "FAULTED"
        self.fault_code = code
        self.fault_message = message
        self.fault_hint = hint
        self.fault_line = line

    def _current_line(self):
        if not self.program or not self.program.instructions:
            return 0
        idx = max(0, min(self.pc - 1, len(self.program.instructions) - 1))
        return self.program.instructions[idx].line
