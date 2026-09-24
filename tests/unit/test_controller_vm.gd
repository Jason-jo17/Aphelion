extends GutTest

## The flight computer: opcode semantics, blocking, and the bounds on a runaway
## program (AC3).

const MU := 3.6864e12
const R := 640000.0

var _world: SimWorld
var _profile: ShipProfile
var _bus: SensorBus
var _state: ShipState
var _ctrl: ControlInput


func before_each() -> void:
	_world = SimWorld.new()
	var b := CelestialBody.new()
	b.id = "halcyon"
	b.mu = MU
	b.radius = R
	_world.add_body(b)

	_profile = ShipProfile.new()
	_profile.dry_mass = 550.0
	_profile.fuel_capacity = 1100.0
	_profile.max_thrust = 40000.0
	_profile.isp = 345.0
	_profile.max_torque = 4000.0
	_profile.inertia = 4821.0

	_state = ShipState.new()
	_state.px = R + 200000.0
	_state.vy = Orbital.circular_speed(MU, _state.px)
	_state.fuel = _profile.fuel_capacity

	_bus = SensorBus.new(_world, _profile)
	_ctrl = ControlInput.new()


func _vm(source: String) -> ControllerVM:
	var program := Assembler.assemble(source)
	assert_true(program.ok(), "test program must assemble: " + program.first_error_text())
	return ControllerVM.new(program)


## Runs `ticks` steps of the VM without moving the ship, which isolates the
## flight computer from the integrator.
func _pump(vm: ControllerVM, ticks: int) -> void:
	for _i in ticks:
		_bus.begin_tick(_state, _ctrl.throttle)
		vm.tick(_bus, _state, _profile, _ctrl, SimWorld.DT_BASE)
		_state.tick += 1


# --- data ------------------------------------------------------------------

func test_arithmetic() -> void:
	var vm := _vm("""
        SET R0, 10
        ADD R0, 5
        MUL R0, 2
        SUB R0, 10
        DIV R0, 4
        SET R1, -3
        ABS R1
        SET R2, 7
        NEG R2
        SET R3, 9
        MIN R3, 4
        SET R4, 9
        MAX R4, 40
        SET R5, 17
        MOD R5, 5
        HALT
""")
	_pump(vm, 1)
	assert_eq(vm.registers[0], 5.0, "((10+5)*2-10)/4")
	assert_eq(vm.registers[1], 3.0)
	assert_eq(vm.registers[2], -7.0)
	assert_eq(vm.registers[3], 4.0)
	assert_eq(vm.registers[4], 40.0)
	assert_eq(vm.registers[5], 2.0)


func test_sense_reads_a_live_value() -> void:
	var vm := _vm("SENSE R0, ALT\nHALT")
	_pump(vm, 1)
	assert_almost_eq(vm.registers[0], 200000.0, 1.0)


func test_angles_reach_the_program_in_degrees() -> void:
	_state.angle = DetMath.PI_2   # 90 degrees
	var vm := _vm("SENSE R0, HDG\nHALT")
	_pump(vm, 1)
	assert_almost_eq(vm.registers[0], 90.0, 1.0e-9,
		"the ISA is documented in degrees, so HDG must read 90 not 1.57")


func test_divide_by_zero_faults_with_the_line_number() -> void:
	var vm := _vm("SET R0, 1\nSET R1, 0\nDIV R0, R1\nHALT")
	_pump(vm, 1)
	assert_eq(vm.status, ControllerVM.Status.FAULTED)
	assert_eq(vm.fault_code, "divide_by_zero")
	assert_eq(vm.fault_line, 3)
	assert_false(vm.fault_hint.is_empty(), "a fault should say what to do about it")


# --- flow ------------------------------------------------------------------

func test_if_skips_the_next_instruction_when_false() -> void:
	var vm := _vm("SET R0, 1\nIF R0 > 5\nSET R0, 99\nHALT")
	_pump(vm, 1)
	assert_eq(vm.registers[0], 1.0, "the guarded instruction must not have run")


func test_if_runs_the_next_instruction_when_true() -> void:
	var vm := _vm("SET R0, 10\nIF R0 > 5\nSET R0, 99\nHALT")
	_pump(vm, 1)
	assert_eq(vm.registers[0], 99.0)


func test_jmp_loops() -> void:
	var vm := _vm("SET R0, 0\nloop:\nADD R0, 1\nIF R0 < 5\nJMP loop\nHALT")
	_pump(vm, 1)
	assert_eq(vm.registers[0], 5.0)
	assert_eq(vm.status, ControllerVM.Status.HALTED)


func test_halt_stops_the_program_but_not_the_flight() -> void:
	var vm := _vm("SET R0, 1\nHALT\nSET R0, 2")
	_pump(vm, 5)
	assert_eq(vm.status, ControllerVM.Status.HALTED)
	assert_eq(vm.registers[0], 1.0, "nothing after HALT should run")


func test_falling_off_the_end_halts() -> void:
	var vm := _vm("SET R0, 1")
	_pump(vm, 2)
	assert_eq(vm.status, ControllerVM.Status.HALTED)


# --- thrust ----------------------------------------------------------------

func test_throttle_alone_does_not_light_the_engine() -> void:
	var vm := _vm("THROTTLE 1\nWAIT 10\nHALT")
	_pump(vm, 1)
	assert_eq(_ctrl.throttle, 0.0,
		"thrust is applied only during BURN; this is what makes a program readable")


func test_burn_applies_the_set_throttle_for_the_stated_time() -> void:
	var vm := _vm("THROTTLE 0.5\nBURN 1\nHALT")
	_pump(vm, 1)
	assert_eq(_ctrl.throttle, 0.5)
	# One second is 64 ticks; thrust must be on for all of them and then stop.
	_pump(vm, 63)
	assert_eq(_ctrl.throttle, 0.5, "still burning at the last tick")
	_pump(vm, 1)
	assert_eq(_ctrl.throttle, 0.0, "and off immediately afterwards")


func test_burn_defaults_to_full_throttle() -> void:
	var vm := _vm("BURN 1\nHALT")
	_pump(vm, 1)
	assert_eq(_ctrl.throttle, 1.0, "`BURN 30` should work without ceremony")


func test_throttle_is_clamped() -> void:
	var vm := _vm("THROTTLE 5\nBURN 1\nHALT")
	_pump(vm, 1)
	assert_eq(_ctrl.throttle, 1.0)


func test_burn_until_stops_when_the_condition_holds() -> void:
	var vm := _vm("BURN UNTIL ALT > 100000\nHALT")
	_pump(vm, 1)
	# Already above 100 km, so the burn should never have started.
	assert_eq(_ctrl.throttle, 0.0)
	assert_eq(vm.status, ControllerVM.Status.HALTED)


func test_burn_until_ends_at_empty_rather_than_hanging() -> void:
	var vm := _vm("BURN UNTIL ALT > 999999999\nLOG 1\nHALT")
	_state.fuel = 0.0
	_pump(vm, 3)
	assert_eq(vm.status, ControllerVM.Status.HALTED,
		"an unsatisfiable BURN UNTIL must end when the tanks do")


func test_wait_blocks_for_exactly_the_right_number_of_ticks() -> void:
	var vm := _vm("WAIT 2\nSET R0, 1\nHALT")
	_pump(vm, 128)
	assert_eq(vm.registers[0], 0.0, "two seconds is 128 ticks; not done yet")
	_pump(vm, 1)
	assert_eq(vm.registers[0], 1.0)


func test_vm_slack_lets_the_simulation_skip_a_long_wait() -> void:
	var vm := _vm("WAIT 100\nHALT")
	_pump(vm, 1)
	var slack := vm.vm_slack(_state.tick)
	assert_almost_eq(slack, 100.0 - SimWorld.DT_BASE, 0.02,
		"a timed wait should declare how long it can be left alone")


func test_a_condition_block_is_watched_rather_than_polled() -> void:
	var vm := _vm("WAIT UNTIL ALT > 999999\nHALT")
	_pump(vm, 1)
	assert_true(vm.has_watched_condition())
	assert_true(is_inf(vm.vm_slack(_state.tick)),
		"the runner refines these with rollback instead of stepping at full rate")
	assert_false(vm.watched_condition_holds(_bus))


# --- attitude --------------------------------------------------------------

func test_orient_blocks_until_it_is_pointing_there() -> void:
	_state.angle = 0.0
	var vm := _vm("ORIENT 90\nSET R0, 1\nHALT")
	_pump(vm, 1)
	assert_eq(vm.registers[0], 0.0, "still turning")
	assert_ne(_ctrl.torque, 0.0, "and the wheels should be working")


func test_point_does_not_block() -> void:
	_state.angle = 0.0
	var vm := _vm("POINT 90\nSET R0, 1\nHALT")
	_pump(vm, 1)
	assert_eq(vm.registers[0], 1.0, "POINT sets the goal and carries on")
	assert_ne(_ctrl.torque, 0.0, "but the goal is still being chased")


func test_attitude_is_held_after_halt() -> void:
	# A program that finished pointing retrograde should stay there to aerobrake.
	_state.angle = 0.0
	var vm := _vm("POINT 180\nHALT")
	_pump(vm, 4)
	assert_ne(_ctrl.torque, 0.0, "the wheels keep holding the last goal")


func test_orient_with_no_reaction_wheel_faults_instead_of_hanging() -> void:
	_profile.max_torque = 0.0
	var vm := _vm("ORIENT PROGRADE\nHALT")
	_pump(vm, 1)
	assert_eq(vm.status, ControllerVM.Status.FAULTED)
	assert_eq(vm.fault_code, "no_attitude_control")


# --- bounds on runaway programs (AC3) --------------------------------------

func test_a_tight_loop_yields_rather_than_faulting() -> void:
	# A polling loop is a legitimate way to fly a landing. It must not be
	# punished — just run at tick rate.
	var vm := _vm("loop:\nSENSE R0, ALT\nJMP loop")
	_pump(vm, 3)
	assert_eq(vm.status, ControllerVM.Status.RUNNING, "it should still be going")
	assert_gt(vm.spin_ticks, 0, "but the game should know it is spinning")


func test_the_per_tick_budget_is_respected() -> void:
	var vm := _vm("loop:\nSENSE R0, ALT\nJMP loop")
	_pump(vm, 1)
	assert_le(vm.instructions_executed, vm.tick_budget,
		"one tick must not execute more than the budget allows")


func test_a_runaway_program_ends_as_a_reported_fault() -> void:
	var vm := _vm("loop:\nSENSE R0, ALT\nJMP loop")
	vm.total_budget = 500
	_pump(vm, 60)
	assert_eq(vm.status, ControllerVM.Status.FAULTED,
		"the total cap must eventually stop it")
	assert_eq(vm.fault_code, "instruction_cap")
	assert_string_contains(vm.fault_hint.to_lower(), "loop",
		"and say what it probably is")


func test_spin_ticks_stay_zero_for_a_well_behaved_program() -> void:
	var vm := _vm("THROTTLE 1\nBURN 1\nWAIT 1\nHALT")
	_pump(vm, 200)
	assert_eq(vm.spin_ticks, 0)


# --- metrics ---------------------------------------------------------------

func test_the_scored_instruction_count_is_program_size_not_executions() -> void:
	var program := Assembler.assemble("SET R0, 0\nloop:\nADD R0, 1\nIF R0 < 50\nJMP loop\nHALT")
	var vm := ControllerVM.new(program)
	_pump(vm, 3)
	assert_eq(program.instruction_count(), 5, "five instructions were written")
	assert_gt(vm.instructions_executed, 100, "and many more than that ran")


func test_log_records_values_with_their_time() -> void:
	var vm := _vm("LOG ALT\nLOG 42\nHALT")
	_pump(vm, 1)
	assert_eq(vm.log_entries.size(), 2)
	assert_almost_eq(float(vm.log_entries[0]["value"]), 200000.0, 1.0)
	assert_eq(float(vm.log_entries[1]["value"]), 42.0)


func test_an_unassembled_program_faults_immediately() -> void:
	var vm := ControllerVM.new(Assembler.assemble("NONSENSE"))
	assert_eq(vm.status, ControllerVM.Status.FAULTED)


func test_an_empty_program_is_reported_as_such() -> void:
	var vm := ControllerVM.new(Assembler.assemble(""))
	assert_eq(vm.fault_code, "no_program")
