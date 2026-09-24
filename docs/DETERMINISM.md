# Determinism

> The same ship, the same program and the same seed produce the **identical**
> trajectory — on every run, and on every operating system.

Everything else in Aphelion rests on that. Local leaderboards compare runs
across months. Solution files are exported and re-imported and expected to
reproduce. Missions ship with three-star reference solutions that CI re-flies on
every push. None of it means anything if the simulation wanders.

This is a design constraint, not a nice-to-have, and it is why several things in
this codebase look unusual. Here is the full rule set and the reasoning.

## 1. The engine's physics is never used

The orbital simulation does not touch Godot's physics server, `_physics_process`,
`delta`, or anything else tied to frame timing. The engine renders and handles
input; that is all.

The simulation advances in `_process` only in the sense that the frame loop
decides *how many* already-fixed steps to take before drawing. A faster machine
draws more often. It does not fly differently.

## 2. Transcendental functions are ours, not libm's

This is the subtle one, and the reason `scripts/core/det_math.gd` exists.

IEEE-754 guarantees **correctly-rounded** results for `+ - * /` and `sqrt`.
Those are bit-identical on every conforming platform. It guarantees **nothing
at all** for `sin`, `cos`, `exp`, `atan`, `log` or `pow`: each platform ships its
own libm, and glibc, Apple's libm and the MSVC CRT disagree in the last couple
of ULPs.

A 1-ULP difference in the sine behind a thrust vector compounds, over a
200 000-tick flight, into a visibly different orbit.

So the simulation never calls the engine's trig. `DetMath` rebuilds it from
correctly-rounded primitives using the classic fdlibm kernels, and is measured at
**≤1 ULP against libm** over the full working range (`tests/unit/test_det_math.gd`).

**The rule:** inside `scripts/physics/`, `scripts/controller_vm/` and
`scripts/sim/`, never call the global `sin`, `cos`, `exp`, `log`, `pow`, `atan`,
`atan2`, `acos`, `asin` or `fmod`. Use `DetMath`. Rendering code may use
whichever it likes — a pixel that lands half a unit away is not a correctness
problem.

## 3. Time is derived, never accumulated

```gdscript
var t := float(tick) * SimWorld.DT_BASE    # yes
t += dt                                     # no
```

`t += dt` drifts by a few ULPs per step, and a 200 000-step flight ends at a
measurably different clock than a replay that stepped in a different pattern.

`DT_BASE` is **1/64 s**, which is exactly representable in binary floating point.
Every permitted step size is that times a power of two, so every step boundary
lands on an exactly representable instant.

## 4. Adaptive stepping is a pure function of state

An ordinary adaptive integrator picks its step size from an error estimate, which
makes the result depend on rounding and is therefore unreproducible by
construction.

`SimWorld.step_scale_for()` instead chooses from the state at the start of the
step and from what the flight computer is waiting for. Two runs from the same
state always choose the same scale. A quiet coast runs 128× faster than real
time and lands on bit-identical numbers (`test_integrator.gd`).

Where a step might skip over something that matters — a `WAIT UNTIL` condition,
ground contact — `SimRunner` takes the big step, notices, restores the state it
saved and halves until the crossing is pinned to within one base tick. Rolling
back is cheap because the state is a value object and the flight computer does
not run during an integration.

## 5. Doubles everywhere; `Vector2` nowhere

Godot's `Vector2` is **single-precision** in standard builds. Twenty-four bits of
mantissa cannot hold a position 7 000 km from the origin to sub-metre accuracy.

Positions, velocities, angles and masses are plain GDScript `float`s, which are
doubles. Conversion to `Vector2` happens at the rendering boundary and nowhere
else.

## 6. No random numbers

The simulation draws none. `test_determinism.gd` seeds the global RNG
differently between two runs and asserts the results are identical, so a stray
`randf()` in a physics path fails the build.

The `seed` on a run is carried for mission content that may want it; nothing in
the integrator or the VM reads it.

## 7. Ordering is stable

Bodies and parts are iterated as arrays, never as `Dictionary` keys. Mission
files are sorted before loading, because `DirAccess.get_files()` promises no
order and an unstable one would make the determinism check flaky for reasons
that have nothing to do with determinism.

## 8. Control inputs are held across a step

Throttle and torque are decided once per step and held (zero-order hold), so the
integrator never samples a control value that depends on where inside the step it
happened to look.

Attitude and mass are *not* frozen — both have exact closed forms under constant
torque and throttle, and evaluating them per RK4 stage keeps a long burn accurate
while the ship is still slewing. Propellant exhaustion resolves to the exact
sub-step instant the tanks run dry, so a burn ends identically whatever step
scale was active.

## How it is checked

| check | where |
| --- | --- |
| DetMath matches the Python reference bit for bit | `tests/unit/test_det_math.gd` |
| DetMath is within 1 ULP of libm | same file |
| Repeat runs are identical | `test_integrator.gd`, `test_determinism.gd` |
| Seeding the RNG changes nothing | `test_determinism.gd` |
| Fast-forwarding matches full-rate integration | `test_integrator.gd` |
| Golden trajectories match the reference | `test_integrator.gd` |
| All fifteen missions reproduce their recorded hashes | `test_reference_solutions.gd` |
| **Windows, macOS and Linux agree** | the `determinism` matrix in `ci.yml` |

The last one is the real test. `tools/determinism_check.gd` flies all fifteen
reference solutions headless on each platform; `tools/compare_determinism.py`
diffs the three reports field by field and names the mission and the field that
moved.

## If you break it

The symptom is the cross-platform job failing with a state-hash mismatch on one
platform. The cause is almost always a transcendental function reaching libm
instead of `DetMath`. Start with:

```sh
grep -nE '(^|[^.[:alnum:]_])(sin|cos|exp|log|pow|atan2?|acos|asin|fmod)\(' \
  scripts/physics/*.gd scripts/controller_vm/*.gd scripts/sim/*.gd
```

Anything that is not `DetMath.` or `sqrt(` deserves a second look.
