# Reference simulation

A line-by-line Python port of `scripts/physics/`, kept alongside the shipped
GDScript for two reasons.

**Tuning.** Mission thresholds, star ratings and ship balance need a fast
numerical feedback loop. Driving Godot for that is slow and awkward; a plain
Python process is not.

**Parity.** Both implementations use IEEE-754 doubles, only correctly-rounded
primitives, and the same deterministic transcendentals, so they agree bit for
bit. `generate_fixtures.py` freezes that agreement into `tests/fixtures/`, and
the GUT suite asserts against those fixtures. If one side is edited without the
other, CI fails.

## Layout

| file | mirrors |
| --- | --- |
| `det_math.py` | `scripts/core/det_math.gd` |
| `sim.py` | `scripts/physics/*.gd` |
| `universe.py` | `missions/universe.json` |
| `validate_physics.py` | conservation / closure / accuracy checks |
| `generate_fixtures.py` | writes `tests/fixtures/*.json` |

## Running

```sh
python3 tools/refsim/validate_physics.py    # 13 numerical checks
python3 tools/refsim/generate_fixtures.py   # regenerate golden fixtures
```

Both are pure stdlib — no dependencies, no virtualenv.

## The rule

If you change anything under `scripts/physics/` or `scripts/core/det_math.gd`,
make the matching change here and regenerate the fixtures in the same commit.
The parity test exists precisely to make forgetting that impossible.
