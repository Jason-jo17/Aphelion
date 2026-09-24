class_name ControlInput
extends RefCounted

## What the flight computer is asking the ship to do for the duration of one
## step. Held constant across the step (zero-order hold), which is what makes
## the control loop reproducible: the integrator never samples a value that
## depends on when inside the step it happened to look.

## Fraction of maximum thrust, 0..1.
var throttle: float = 0.0

## Fraction of maximum reaction-wheel torque, -1..1. Positive is
## counter-clockwise.
var torque: float = 0.0


func clear() -> void:
	throttle = 0.0
	torque = 0.0


func set_from(t: float, q: float) -> void:
	throttle = clampf(t, 0.0, 1.0)
	torque = clampf(q, -1.0, 1.0)
