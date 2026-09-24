class_name RunResult
extends RefCounted

## Everything a completed flight produced: whether it worked, what it cost, and
## enough identity to prove a replay is replaying the same thing.

var mission_id: String = ""
var success: bool = false

## Why the run ended, in the player's language.
var outcome: String = ""
var outcome_detail: String = ""

# --- the three scored metrics ---
var fuel_used: float = 0.0
var ticks: int = 0
var instruction_count: int = 0      ## static program size; the scored number

# --- supporting numbers ---
var instructions_executed: int = 0
var elapsed: float = 0.0
var fuel_remaining: float = 0.0
var delta_v_used: float = 0.0
var max_altitude: float = 0.0
var max_dynamic_pressure: float = 0.0
var touchdown_speed: float = -1.0
var spin_ticks: int = 0

## Ticks in which the flight computer ran at all. `spin_ticks` is a fraction of
## this, not of `ticks` — step scaling means one tick of the VM can cover many
## ticks of the clock.
var vm_ticks: int = 0

# --- stars ---
var stars: int = 0
var star_fuel: bool = false
var star_time: bool = false
var star_instructions: bool = false

# --- program outcome ---
var vm_status: String = ""
var fault_code: String = ""
var fault_message: String = ""
var fault_hint: String = ""
var fault_line: int = 0

# --- identity, for replay verification ---
var ship_hash: String = ""
var program_hash: String = ""
var mission_hash: String = ""
var seed: int = 0

## Hash of the final state. Two runs of the same inputs must agree on this; the
## cross-platform determinism job in CI compares it between operating systems.
var state_hash: String = ""

var log_entries: Array[Dictionary] = []

## Sampled trajectory for the map view and the scrub timeline. Groups of
## TRAJECTORY_STRIDE doubles: t, px, py, vx, vy, fuel, angle, throttle.
const TRAJECTORY_STRIDE := 8
var trajectory := PackedFloat64Array()


func sample_count() -> int:
	return trajectory.size() / TRAJECTORY_STRIDE


func sample(i: int) -> Dictionary:
	var o := i * TRAJECTORY_STRIDE
	if o < 0 or o + TRAJECTORY_STRIDE > trajectory.size():
		return {}
	return {
		"t": trajectory[o], "px": trajectory[o + 1], "py": trajectory[o + 2],
		"vx": trajectory[o + 3], "vy": trajectory[o + 4], "fuel": trajectory[o + 5],
		"angle": trajectory[o + 6], "throttle": trajectory[o + 7],
	}


## One line summarising the run, for the leaderboard and the results header.
func summary() -> String:
	if not success:
		return "Failed — %s" % outcome
	return "%s fuel · %s · %d instructions" % [
		Fmt.mass(fuel_used), Fmt.duration(elapsed), instruction_count]


func to_dict(include_trajectory: bool = false) -> Dictionary:
	var d := {
		"mission_id": mission_id,
		"success": success,
		"outcome": outcome,
		"outcome_detail": outcome_detail,
		"fuel_used": fuel_used,
		"ticks": ticks,
		"elapsed": elapsed,
		"instruction_count": instruction_count,
		"instructions_executed": instructions_executed,
		"fuel_remaining": fuel_remaining,
		"delta_v_used": delta_v_used,
		"max_altitude": max_altitude,
		"max_dynamic_pressure": max_dynamic_pressure,
		"touchdown_speed": touchdown_speed,
		"spin_ticks": spin_ticks,
		"vm_ticks": vm_ticks,
		"stars": stars,
		"star_fuel": star_fuel,
		"star_time": star_time,
		"star_instructions": star_instructions,
		"vm_status": vm_status,
		"fault_code": fault_code,
		"fault_message": fault_message,
		"fault_line": fault_line,
		"ship_hash": ship_hash,
		"program_hash": program_hash,
		"mission_hash": mission_hash,
		"state_hash": state_hash,
		"seed": seed,
		"log": log_entries,
	}
	if include_trajectory:
		d["trajectory"] = Array(trajectory)
	return d


static func from_dict(d: Dictionary) -> RunResult:
	var r := RunResult.new()
	r.mission_id = String(d.get("mission_id", ""))
	r.success = bool(d.get("success", false))
	r.outcome = String(d.get("outcome", ""))
	r.outcome_detail = String(d.get("outcome_detail", ""))
	r.fuel_used = float(d.get("fuel_used", 0.0))
	r.ticks = int(d.get("ticks", 0))
	r.elapsed = float(d.get("elapsed", 0.0))
	r.instruction_count = int(d.get("instruction_count", 0))
	r.instructions_executed = int(d.get("instructions_executed", 0))
	r.fuel_remaining = float(d.get("fuel_remaining", 0.0))
	r.delta_v_used = float(d.get("delta_v_used", 0.0))
	r.max_altitude = float(d.get("max_altitude", 0.0))
	r.max_dynamic_pressure = float(d.get("max_dynamic_pressure", 0.0))
	r.touchdown_speed = float(d.get("touchdown_speed", -1.0))
	r.spin_ticks = int(d.get("spin_ticks", 0))
	r.vm_ticks = int(d.get("vm_ticks", 0))
	r.stars = int(d.get("stars", 0))
	r.star_fuel = bool(d.get("star_fuel", false))
	r.star_time = bool(d.get("star_time", false))
	r.star_instructions = bool(d.get("star_instructions", false))
	r.vm_status = String(d.get("vm_status", ""))
	r.fault_code = String(d.get("fault_code", ""))
	r.fault_message = String(d.get("fault_message", ""))
	r.fault_line = int(d.get("fault_line", 0))
	r.ship_hash = String(d.get("ship_hash", ""))
	r.program_hash = String(d.get("program_hash", ""))
	r.mission_hash = String(d.get("mission_hash", ""))
	r.state_hash = String(d.get("state_hash", ""))
	r.seed = int(d.get("seed", 0))
	for e in d.get("log", []):
		r.log_entries.append(e)
	if d.has("trajectory"):
		r.trajectory = PackedFloat64Array(d["trajectory"])
	return r
