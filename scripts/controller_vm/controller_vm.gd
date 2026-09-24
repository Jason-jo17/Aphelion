class_name ControllerVM
extends RefCounted

## The flight computer.
##
## Runs once at the start of every simulation step, before the integrator moves
## the ship, and owns exactly two outputs: throttle and torque. See docs/ISA.md
## for the language and the execution model it promises.

enum Status { READY, RUNNING, HALTED, FAULTED }

## What the program is waiting for, if anything.
enum Block { NONE, TIMER, CONDITION, ORIENT }

## Instructions executed in one tick before the VM yields to the next one.
## Yielding rather than faulting keeps a polling loop viable — see docs/ISA.md.
const DEFAULT_TICK_BUDGET := 64

## A program that executes this many instructions in a run is looping by
## accident. Bounded so an infinite loop ends as a reported fault.
const DEFAULT_TOTAL_BUDGET := 5_000_000

const MAX_LOG_ENTRIES := 500

var program: Program = null
var attitude := AttitudeController.new()

var registers := PackedFloat64Array()
var pc: int = 0
var status: int = Status.READY

var fault_code: String = ""
var fault_message: String = ""
var fault_hint: String = ""
var fault_line: int = 0

## Metrics. `instructions_executed` is the dynamic count; the *scored* size of a
## program is its static instruction count, which lives on Program.
var instructions_executed: int = 0

## Ticks in which the program hit the per-tick budget without blocking. A high
## proportion is the signature of an unintended loop, and the results screen
## says so.
var spin_ticks: int = 0
var total_ticks: int = 0

var log_entries: Array[Dictionary] = []

var tick_budget: int = DEFAULT_TICK_BUDGET
var total_budget: int = DEFAULT_TOTAL_BUDGET

## Throttle a subsequent BURN will use. Defaults to full, so `BURN 30` works
## without ceremony.
var throttle_setting: float = 1.0

# --- blocking state ---
var _block: int = Block.NONE
var _block_thrusting: bool = false
var _block_end_tick: int = 0     ## exact tick a timed block ends on
var _cond_a: Operand = null
var _cond_b: Operand = null
var _cond_cmp: int = ISA.Cmp.LT
var _orient_deadline_tick: int = 0
var _block_line: int = 0


func _init(prog: Program = null) -> void:
	registers.resize(ISA.REGISTER_COUNT)
	load_program(prog)


func load_program(prog: Program) -> void:
	program = prog
	reset()


func reset() -> void:
	for i in registers.size():
		registers[i] = 0.0
	pc = 0
	instructions_executed = 0
	spin_ticks = 0
	total_ticks = 0
	log_entries.clear()
	throttle_setting = 1.0
	_block = Block.NONE
	_block_thrusting = false
	_block_end_tick = 0
	_cond_a = null
	_cond_b = null
	_block_line = 0
	attitude.reset()
	fault_code = ""
	fault_message = ""
	fault_hint = ""
	fault_line = 0
	if program == null or not program.ok():
		status = Status.FAULTED if program != null and not program.errors.is_empty() else Status.READY
		if program != null and program.instructions.is_empty() and program.errors.is_empty():
			_fault("no_program", "The flight computer has no program.",
				"Write at least one instruction, even if it is just HALT.", 0)
	else:
		status = Status.RUNNING


func is_running() -> bool:
	return status == Status.RUNNING


func is_finished() -> bool:
	return status == Status.HALTED or status == Status.FAULTED


# --- the per-step entry point ---------------------------------------------


## Advances the program and writes this step's control outputs into `ctrl`.
## `dt` is the duration of the step that is about to be integrated.
func tick(bus: SensorBus, state: ShipState, profile: ShipProfile, ctrl: ControlInput, dt: float) -> void:
	total_ticks += 1
	ctrl.throttle = 0.0

	if status == Status.RUNNING:
		var budget := tick_budget
		while true:
			if _block != Block.NONE:
				if not _try_unblock(bus, state, profile):
					break  # still waiting; the block decides the outputs
				# Unblocked mid-tick: carry straight on to the next instruction.
			if status != Status.RUNNING:
				break
			if budget <= 0:
				spin_ticks += 1
				break
			if instructions_executed >= total_budget:
				_fault("instruction_cap",
					"The program has executed %s instructions." % _commify(total_budget),
					"That is almost always an unintended loop. Check that every path "
					+ "through your program reaches a WAIT, a BURN or a HALT.",
					_current_line())
				break
			_execute_one(bus, state, profile)
			budget -= 1

	# A burn in progress keeps the engine lit for this step.
	if status == Status.RUNNING and _block_thrusting and state.fuel > 0.0:
		ctrl.throttle = throttle_setting

	# Attitude is held on every tick, including after HALT: a program that
	# finished pointing retrograde should stay there to aerobrake.
	ctrl.torque = attitude.torque_for(state, profile, bus, dt)


## Seconds the flight computer is certain it will not need to act for. The step
## chooser uses this to decide how far it may fast-forward, so a timed WAIT
## lands on its exact tick.
##
## A condition block returns INF: the simulation runner watches those with
## rollback refinement instead (see SimRunner), which resolves the crossing to
## within one base tick without giving up the speed-up.
func vm_slack(current_tick: int) -> float:
	if status != Status.RUNNING:
		return INF
	if _block == Block.TIMER:
		return maxf(0.0, float(_block_end_tick - current_tick) * SimWorld.DT_BASE)
	if _block == Block.CONDITION or _block == Block.ORIENT:
		return INF
	return 0.0  # about to execute: the VM must run this tick


## True when the program is parked on a condition the runner should watch.
func has_watched_condition() -> bool:
	return status == Status.RUNNING and _block == Block.CONDITION


## Evaluates the pending condition against a (possibly hypothetical) state.
## Used by the runner's event refinement; must not mutate anything.
func watched_condition_holds(bus: SensorBus) -> bool:
	if _block != Block.CONDITION or _cond_a == null or _cond_b == null:
		return false
	return _compare(_read(_cond_a, bus), _cond_cmp, _read(_cond_b, bus))


# --- blocking --------------------------------------------------------------


## Returns true when the block has cleared and execution may continue.
func _try_unblock(bus: SensorBus, state: ShipState, profile: ShipProfile) -> bool:
	match _block:
		Block.TIMER:
			if _block_thrusting and state.fuel <= 0.0:
				_clear_block()
				return true
			if state.tick >= _block_end_tick:
				_clear_block()
				return true
			return false
		Block.CONDITION:
			if _block_thrusting and state.fuel <= 0.0:
				# A BURN UNTIL whose condition never comes true ends at empty
				# rather than hanging the flight.
				_clear_block()
				return true
			if watched_condition_holds(bus):
				_clear_block()
				return true
			return false
		Block.ORIENT:
			if attitude.at_goal(state, bus):
				_clear_block()
				return true
			if state.tick >= _orient_deadline_tick:
				_fault("orient_timeout",
					"ORIENT did not settle within %d seconds." % int(AttitudeController.CONVERGENCE_TIMEOUT),
					"The tolerance may be tighter than the reaction wheels can hold, "
					+ "or the goal may be moving faster than the ship can turn.",
					_block_line)
				_clear_block()
				return false
			return false
	return true


func _clear_block() -> void:
	_block = Block.NONE
	_block_thrusting = false
	_cond_a = null
	_cond_b = null


func _begin_timer(seconds: float, thrusting: bool, state: ShipState, line: int) -> void:
	var ticks := int(maxf(0.0, seconds) / SimWorld.DT_BASE + 0.5)
	_block = Block.TIMER
	_block_thrusting = thrusting
	_block_end_tick = state.tick + maxi(0, ticks)
	_block_line = line


func _begin_condition(a: Operand, cmp: int, b: Operand, thrusting: bool, line: int) -> void:
	_block = Block.CONDITION
	_block_thrusting = thrusting
	_cond_a = a
	_cond_b = b
	_cond_cmp = cmp
	_block_line = line


# --- execution -------------------------------------------------------------


func _execute_one(bus: SensorBus, state: ShipState, profile: ShipProfile) -> void:
	if pc < 0 or pc >= program.instructions.size():
		status = Status.HALTED
		return

	var ins: Instruction = program.instructions[pc]
	instructions_executed += 1
	pc += 1

	match ins.op:
		ISA.Op.NOP:
			pass
		ISA.Op.SET, ISA.Op.SENSE:
			_write(ins.a, _read(ins.b, bus))
		ISA.Op.ADD:
			_write(ins.a, _read(ins.a, bus) + _read(ins.b, bus))
		ISA.Op.SUB:
			_write(ins.a, _read(ins.a, bus) - _read(ins.b, bus))
		ISA.Op.MUL:
			_write(ins.a, _read(ins.a, bus) * _read(ins.b, bus))
		ISA.Op.DIV:
			var d := _read(ins.b, bus)
			if d == 0.0:
				_fault("divide_by_zero", "Division by zero.",
					"Guard the divisor with an IF before dividing by it.", ins.line)
				return
			_write(ins.a, _read(ins.a, bus) / d)
		ISA.Op.MOD:
			var m := _read(ins.b, bus)
			if m == 0.0:
				_fault("divide_by_zero", "MOD by zero.",
					"Guard the divisor with an IF before using it.", ins.line)
				return
			_write(ins.a, DetMath.fmod_exact(_read(ins.a, bus), m))
		ISA.Op.MIN:
			_write(ins.a, minf(_read(ins.a, bus), _read(ins.b, bus)))
		ISA.Op.MAX:
			_write(ins.a, maxf(_read(ins.a, bus), _read(ins.b, bus)))
		ISA.Op.ABS:
			_write(ins.a, absf(_read(ins.a, bus)))
		ISA.Op.NEG:
			_write(ins.a, -_read(ins.a, bus))
		ISA.Op.JMP:
			if ins.target < 0:
				_fault("bad_jump", "Jump to an undefined label '%s'." % ins.label_name,
					"Define it with `%s:` somewhere in the program." % ins.label_name, ins.line)
				return
			pc = ins.target
		ISA.Op.IF:
			if not _compare(_read(ins.a, bus), ins.cmp, _read(ins.b, bus)):
				pc += 1  # skip the guarded instruction
		ISA.Op.HALT:
			status = Status.HALTED
		ISA.Op.THROTTLE:
			throttle_setting = clampf(_read(ins.a, bus), 0.0, 1.0)
		ISA.Op.LOG:
			_append_log(ins, _read(ins.a, bus), bus)
		ISA.Op.POINT:
			_apply_goal(ins.a, bus)
		ISA.Op.ORIENT:
			if profile.max_torque <= 0.0:
				_fault("no_attitude_control", "ORIENT with no reaction wheel.",
					"This ship has no way to turn itself. Add a reaction wheel in the "
					+ "editor, or remove the ORIENT.", ins.line)
				return
			_apply_goal(ins.a, bus)
			if ins.b != null:
				attitude.set_tolerance_deg(_read(ins.b, bus))
			else:
				attitude.set_tolerance_deg(AttitudeController.DEFAULT_TOLERANCE_DEG)
			if not attitude.at_goal(state, bus):
				_block = Block.ORIENT
				_block_thrusting = false
				_block_line = ins.line
				_orient_deadline_tick = state.tick + int(
					AttitudeController.CONVERGENCE_TIMEOUT / SimWorld.DT_BASE)
		ISA.Op.BURN:
			_begin_timer(_read(ins.a, bus), true, state, ins.line)
		ISA.Op.WAIT:
			_begin_timer(_read(ins.a, bus), false, state, ins.line)
		ISA.Op.BURN_UNTIL:
			if not _compare(_read(ins.a, bus), ins.cmp, _read(ins.b, bus)):
				_begin_condition(ins.a, ins.cmp, ins.b, true, ins.line)
		ISA.Op.WAIT_UNTIL:
			if not _compare(_read(ins.a, bus), ins.cmp, _read(ins.b, bus)):
				_begin_condition(ins.a, ins.cmp, ins.b, false, ins.line)


## Applies an ORIENT/POINT operand as an attitude goal. A goal keyword tracks
## the live vector; anything numeric is an absolute heading in degrees.
func _apply_goal(o: Operand, bus: SensorBus) -> void:
	if o.kind == Operand.Kind.GOAL:
		attitude.set_goal(o.goal)
	else:
		attitude.set_goal(ISA.Goal.ABSOLUTE, _read(o, bus) * SensorBus.DEG_TO_RAD)


func _read(o: Operand, bus: SensorBus) -> float:
	if o == null:
		return 0.0
	match o.kind:
		Operand.Kind.LITERAL:
			return o.value
		Operand.Kind.REGISTER:
			return registers[o.index]
		Operand.Kind.SENSOR:
			return bus.read(o.sensor)
		Operand.Kind.GOAL:
			# A goal used as a number reads as the heading it currently means.
			return SensorBus._to_compass(_goal_heading(o.goal, bus))
	return 0.0


func _goal_heading(goal: int, bus: SensorBus) -> float:
	match goal:
		ISA.Goal.PROGRADE: return bus.prograde_rad()
		ISA.Goal.RETROGRADE: return bus.prograde_rad() + DetMath.PI_D
		ISA.Goal.RADIAL: return bus.radial_rad()
		ISA.Goal.ANTIRADIAL: return bus.radial_rad() + DetMath.PI_D
		ISA.Goal.TARGET: return bus.target_rad()
	return 0.0


func _write(o: Operand, v: float) -> void:
	if o == null or o.kind != Operand.Kind.REGISTER:
		_fault("bad_register", "Tried to write to something that is not a register.",
			"Only R0 to R%d can be written." % (ISA.REGISTER_COUNT - 1), _current_line())
		return
	registers[o.index] = v


static func _compare(a: float, cmp: int, b: float) -> bool:
	match cmp:
		ISA.Cmp.LT: return a < b
		ISA.Cmp.LE: return a <= b
		ISA.Cmp.GT: return a > b
		ISA.Cmp.GE: return a >= b
		ISA.Cmp.EQ: return a == b
		ISA.Cmp.NE: return a != b
	return false


func _append_log(ins: Instruction, value: float, bus: SensorBus) -> void:
	if log_entries.size() >= MAX_LOG_ENTRIES:
		return
	log_entries.append({
		"t": bus.read(ISA.Sensor.T),
		"line": ins.line,
		"label": ins.a.to_text() if ins.a != null else "",
		"value": value,
	})


func _fault(code: String, message: String, hint: String, line: int) -> void:
	status = Status.FAULTED
	fault_code = code
	fault_message = message
	fault_hint = hint
	fault_line = line


func _current_line() -> int:
	if program == null:
		return 0
	var idx := clampi(pc - 1, 0, maxi(0, program.instructions.size() - 1))
	if program.instructions.is_empty():
		return 0
	return program.instructions[idx].line


static func _commify(n: int) -> String:
	var s := str(n)
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = " " + out
	return out


## A short description of why the run ended, for the results screen.
func status_text() -> String:
	match status:
		Status.READY: return "not started"
		Status.RUNNING: return "still running"
		Status.HALTED: return "program finished"
		Status.FAULTED: return "fault: %s" % fault_message
	return "?"
