---
name: deterministic-sim-rules
description: The rules that keep Aphelion's simulation bit-identical across runs and operating systems. Load before editing scripts/physics/, scripts/controller_vm/, scripts/sim/ or scripts/core/det_math.gd, or when a determinism test fails.
---

# Deterministic simulation rules

Full reasoning: `docs/DETERMINISM.md`. This is the checklist.

## Never, inside `scripts/physics/`, `controller_vm/`, `sim/`

| do not | do instead | why |
| --- | --- | --- |
| `sin cos exp log pow atan atan2 acos asin` | `DetMath.*` | libm differs by ULPs between platforms; it compounds into a different orbit |
| `fmod(x, y)` | `DetMath.fmod_exact` | exact and safe, but wrapped so the rule stays a clean grep |
| `t += dt` | `t = tick * DT_BASE` | accumulation drifts a few ULPs per step |
| `Vector2` for position/velocity | plain `float` (double) | Vector2 is single-precision; 24 bits cannot hold 7 000 km to the metre |
| `randf()`, `randi()` | nothing | the simulation draws no random numbers |
| iterating a `Dictionary` | an `Array` | key order is not guaranteed stable |
| error-controlled adaptive steps | `SimWorld.step_scale_for()` | the step must be a pure function of state |

`sqrt` is fine — IEEE-754 specifies it exactly.

## Facts worth remembering

- `DT_BASE` is 1/64 s, exactly representable. Every step size is that times a
  power of two, so every boundary is exact.
- Throttle and torque are held across a step. Attitude and mass are *not* — both
  have exact closed forms under constant torque and throttle.
- Propellant exhaustion resolves to the exact sub-step instant, so a burn ends
  identically at any step scale.
- `SimRunner` refines by rollback-and-halve when a watched condition or ground
  contact happens mid-step.

## After any change

```sh
python3 tools/refsim/generate_fixtures.py    # regenerate — CI fails if stale
python3 tools/refsim/validate_physics.py     # 13 numerical checks
python3 tools/refsim/author_missions.py      # all fifteen must still fly
```

`scripts/physics/` and `tools/refsim/` are the same algorithm in two languages.
Change both, in the same commit.

## When a determinism test fails

The symptom is one platform's state hash differing. The cause is almost always a
libm call that slipped in:

```sh
grep -nE '(^|[^.[:alnum:]_])(sin|cos|exp|log|pow|atan2?|acos|asin|fmod)\(' \
  scripts/physics/*.gd scripts/controller_vm/*.gd scripts/sim/*.gd
```

Anything not prefixed `DetMath.` deserves a second look.
