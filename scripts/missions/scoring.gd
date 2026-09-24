class_name Scoring
extends RefCounted

## Three stars, one per metric, each earned by coming in at or under a threshold.
##
## They are deliberately not a single combined score. Fuel, time and program
## size pull against each other — the cheapest ascent is slow, the fastest burns
## hard, and the shortest program does neither well — and three separate targets
## make that tension visible instead of averaging it away.

const METRIC_FUEL := "fuel"
const METRIC_TIME := "time"
const METRIC_INSTRUCTIONS := "instructions"


## Fills in the star fields on `result` from the mission's thresholds.
static func apply(mission: Mission, result: RunResult) -> void:
	result.star_fuel = false
	result.star_time = false
	result.star_instructions = false
	result.stars = 0
	if not result.success:
		return

	result.star_fuel = result.fuel_used <= mission.star_fuel
	result.star_time = result.elapsed <= mission.star_time
	result.star_instructions = result.instruction_count <= mission.star_instructions
	result.stars = (
		(1 if result.star_fuel else 0)
		+ (1 if result.star_time else 0)
		+ (1 if result.star_instructions else 0)
	)


## Per-metric detail for the results screen: what you scored, what was needed,
## and how close you were.
static func breakdown(mission: Mission, result: RunResult) -> Array[Dictionary]:
	return [
		_row(
			METRIC_FUEL,
			"Fuel",
			result.fuel_used,
			mission.star_fuel,
			result.star_fuel,
			Fmt.mass(result.fuel_used),
			Fmt.mass(mission.star_fuel)
		),
		_row(
			METRIC_TIME,
			"Time",
			result.elapsed,
			mission.star_time,
			result.star_time,
			Fmt.duration(result.elapsed),
			Fmt.duration(mission.star_time)
		),
		_row(
			METRIC_INSTRUCTIONS,
			"Instructions",
			float(result.instruction_count),
			float(mission.star_instructions),
			result.star_instructions,
			str(result.instruction_count),
			str(mission.star_instructions)
		),
	]


static func _row(
	metric: String,
	label: String,
	value: float,
	target: float,
	earned: bool,
	value_text: String,
	target_text: String
) -> Dictionary:
	var over := 0.0
	if target > 0.0 and not is_inf(target):
		over = (value - target) / target
	return {
		"metric": metric,
		"label": label,
		"value": value,
		"target": target,
		"earned": earned,
		"value_text": value_text,
		"target_text": target_text,
		"over_fraction": over,
	}


## Which of a player's two runs is better. Used for personal bests, where
## "better" has to mean something specific: more stars first, then the metric
## the player is currently chasing, then the others as tie-breaks.
static func is_better(candidate: RunResult, incumbent: RunResult, metric: String = "") -> bool:
	if incumbent == null:
		return true
	if candidate.success != incumbent.success:
		return candidate.success
	if candidate.stars != incumbent.stars:
		return candidate.stars > incumbent.stars
	match metric:
		METRIC_FUEL:
			if candidate.fuel_used != incumbent.fuel_used:
				return candidate.fuel_used < incumbent.fuel_used
		METRIC_TIME:
			if candidate.elapsed != incumbent.elapsed:
				return candidate.elapsed < incumbent.elapsed
		METRIC_INSTRUCTIONS:
			if candidate.instruction_count != incumbent.instruction_count:
				return candidate.instruction_count < incumbent.instruction_count
	if candidate.fuel_used != incumbent.fuel_used:
		return candidate.fuel_used < incumbent.fuel_used
	if candidate.elapsed != incumbent.elapsed:
		return candidate.elapsed < incumbent.elapsed
	return candidate.instruction_count < incumbent.instruction_count
