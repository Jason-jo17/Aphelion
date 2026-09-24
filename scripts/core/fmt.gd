class_name Fmt
extends RefCounted

## Shared number formatting. One place, so a distance reads the same in the
## objectives panel, the instrument strip, the results screen and a tooltip.


## Distance with a sensible unit. 1234.0 -> "1.23 km".
static func distance(m: float) -> String:
	if is_inf(m):
		return "∞"
	if is_nan(m):
		return "—"
	var a := absf(m)
	if a >= 1.0e6:
		return "%.3f Mm" % (m / 1.0e6)
	if a >= 1000.0:
		return "%.2f km" % (m / 1000.0)
	if a >= 1.0:
		return "%.0f m" % m
	return "%.2f m" % m


## Distance rounded for objectives text, where precision is noise. -> "95 km".
static func distance_coarse(m: float) -> String:
	if is_inf(m):
		return "∞"
	var a := absf(m)
	if a >= 1.0e6:
		return "%.1f Mm" % (m / 1.0e6)
	if a >= 1000.0:
		return "%s km" % _trim_zero(m / 1000.0)
	return "%s m" % _trim_zero(snappedf(m, 1.0))


## One decimal place with a pointless ".0" dropped: 95.0 -> "95", 95.4 -> "95.4".
##
## This is what `%g` would do in C, and `%g` is what this used to say — but
## GDScript's `%` operator has no `g` conversion. It does not fail loudly; it
## pushes an engine error and returns the literal string "%g", so every apsis
## marker on the flight map was labelled "%g km" until someone rendered the
## game and looked at it. `String.num()` is no help either: it keeps the
## trailing zero.
static func _trim_zero(v: float) -> String:
	var s := "%.1f" % v
	if s.ends_with(".0"):
		s = s.substr(0, s.length() - 2)
	return "0" if s == "-0" else s


static func speed(mps: float) -> String:
	if is_inf(mps):
		return "∞"
	if absf(mps) >= 1000.0:
		return "%.2f km/s" % (mps / 1000.0)
	return "%.1f m/s" % mps


## Duration as h/m/s, dropping units that are zero. 3725 -> "1h 02m 05s".
static func duration(s: float) -> String:
	if is_inf(s):
		return "∞"
	if s < 0.0:
		return "—"
	var total := int(s)
	var h := total / 3600
	var m := (total % 3600) / 60
	var sec := total % 60
	if h > 0:
		return "%dh %02dm %02ds" % [h, m, sec]
	if m > 0:
		return "%dm %02ds" % [m, sec]
	if s < 10.0:
		return "%.1fs" % s
	return "%ds" % sec


## Mission-clock style, always the same width so it does not jitter. -> "T+01:02:05".
static func clock(s: float) -> String:
	var total := int(maxf(0.0, s))
	return "T+%02d:%02d:%02d" % [total / 3600, (total % 3600) / 60, total % 60]


static func mass(kg: float) -> String:
	if absf(kg) >= 1000.0:
		return "%.2f t" % (kg / 1000.0)
	return "%.0f kg" % kg


static func force(n: float) -> String:
	if absf(n) >= 1000.0:
		return "%.0f kN" % (n / 1000.0)
	return "%.0f N" % n


static func pressure(pa: float) -> String:
	if absf(pa) >= 1000.0:
		return "%.1f kPa" % (pa / 1000.0)
	return "%.0f Pa" % pa


static func degrees(deg: float) -> String:
	return "%.1f°" % deg


## A plain number with a sensible number of digits for its magnitude.
## A whole number of things — instructions, parts, attempts. Grouped in threes
## and never given a decimal point: number() is for measurements, where 3665.0
## means "to one decimal place", and a count has no decimal place to speak of.
## The results screen read "Instructions executed  3665.0" until someone looked
## at a screenshot of it.
static func count(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	var seen := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		seen += 1
		if seen % 3 == 0 and i > 0:
			out = "," + out
	return ("-" + out) if n < 0 else out


static func number(v: float, unit: String = "") -> String:
	if is_inf(v):
		return "∞" + ("" if unit.is_empty() else " " + unit)
	var a := absf(v)
	var s: String
	if a >= 10000.0:
		s = "%.0f" % v
	elif a >= 100.0:
		s = "%.1f" % v
	elif a >= 1.0:
		s = "%.2f" % v
	else:
		s = "%.3f" % v
	return s if unit.is_empty() else s + " " + unit


## Formats a sensor reading in the sensor's own unit.
##
## `coarse` is for objectives and briefings, where the extra digits are noise
## and sometimes a lie: "periapsis at least 90.00 km" reads like a tolerance
## somebody measured, when the mission author simply typed ninety.
static func sensor_value(sensor: int, v: float, coarse: bool = false) -> String:
	match sensor:
		ISA.Sensor.ALT, ISA.Sensor.APO, ISA.Sensor.PERI, ISA.Sensor.SMA, ISA.Sensor.TGTD:
			return distance_coarse(v) if coarse else distance(v)
		ISA.Sensor.VEL, ISA.Sensor.VVEL, ISA.Sensor.HVEL, ISA.Sensor.DV, ISA.Sensor.TGTV:
			return speed(v)
		ISA.Sensor.TAPO, ISA.Sensor.TPERI, ISA.Sensor.T:
			return duration(v)
		# The angles, split over two arms only because the list of them does
		# not fit on one line and a match pattern cannot be wrapped.
		ISA.Sensor.HDG, ISA.Sensor.PRO, ISA.Sensor.RETRO, ISA.Sensor.RAD:
			return degrees(v)
		ISA.Sensor.ANTIRAD, ISA.Sensor.PITCH, ISA.Sensor.TGTA:
			return degrees(v)
		ISA.Sensor.FUEL, ISA.Sensor.MASS:
			return mass(v)
		ISA.Sensor.Q:
			return pressure(v)
		_:
			return number(v)
