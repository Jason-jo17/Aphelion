# Contributing

Thank you for looking. Aphelion is small enough to hold in your head and
deliberately documented so you do not have to.

## The quickest useful contribution: a mission

A mission is one JSON file. It needs no GDScript, and `good first issue` on this
repository is nearly always exactly that.

Read [docs/MISSIONS.md](docs/MISSIONS.md) — it covers the format, the predicate
language, and the part that matters most: **every mission ships with a reference
solution that actually solves it**, and the star thresholds are derived from
what that flight achieved. You write the mission *and* the program that beats
it, the tool flies it, and the thresholds fall out.

```sh
# add your mission to MISSIONS in tools/refsim/author_missions.py
python3 tools/refsim/author_missions.py            # fly it, see what happened
python3 tools/refsim/author_missions.py --write    # regenerate missions/
```

Commit the mission file and the authoring entry together.

What makes a mission worth playing is in that document too, but the short
version: teach exactly one thing, make the wrong answer instructive rather than
just wrong, and check the numbers before you write the prose. Two of the
fifteen shipped missions were redesigned outright because the physics said the
story did not work.

## Setting up

Aphelion targets **Godot 4.7.x**. Nothing else is needed to run it.

```sh
godot .                       # or open project.godot
./tools/fetch_gut.sh          # the test framework, not vendored
```

Run the tests before you open a pull request:

```sh
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
python3 tools/refsim/validate_physics.py
python3 tools/refsim/author_missions.py
```

The Python side has no dependencies and takes seconds; run it first.

## The rules that are not negotiable

### 1. Determinism

The same ship, program and seed must produce the identical trajectory on every
platform. [docs/DETERMINISM.md](docs/DETERMINISM.md) has the full rule set. The
two that catch people:

- **Never call `sin`, `cos`, `exp`, `log`, `pow`, `atan`, `atan2`, `acos`,
  `asin` or `fmod` inside `scripts/physics/`, `scripts/controller_vm/` or
  `scripts/sim/`.** Use `DetMath`. Platform libms disagree in the last ULP, and
  that compounds into a different orbit. Rendering code may use whatever it
  likes.
- **Never accumulate time.** `t = tick * DT_BASE`, not `t += dt`.

CI runs all fifteen reference flights on Windows, macOS and Linux and compares
the results field by field, so a mistake here is caught rather than shipped.

### 2. `scripts/physics/` and `tools/refsim/` change together

`tools/refsim/` is a line-by-line Python port of the shipped GDScript. It exists
so that mission balance can be tuned in a fast feedback loop, and so that golden
fixtures can prove the two have not drifted.

If you change one, change the other, and regenerate the fixtures **in the same
commit**:

```sh
python3 tools/refsim/generate_fixtures.py
```

CI regenerates them too and fails if what you committed is stale, so forgetting
is impossible rather than merely discouraged.

### 3. Accessibility is structural

- Anything reachable by mouse must be reachable by keyboard. New screen actions
  go in that screen's `palette_commands()`.
- Colour is never the only signal. A new trajectory role needs a line style and
  a label as well as a hue, and there is a test that checks it.
- New colours must clear WCAG AA. `test_scoring.gd` asserts the ratios; add
  yours to the list.
- New animations go through `Tokens.duration()` so reduced motion reaches them.

### 4. Error messages teach

The assembler does not say "syntax error on line 12". It says which token, what
is wrong with it, and what to write instead — with an edit-distance suggestion
where one is close enough to be worth guessing. Ship validation does not say
"invalid ship"; it says which part is missing and what it would do for you.

If you add a failure path, give it the same treatment. There is a test that
every ship-validation finding carries a hint.

## Style

- GDScript, tabs, `gdformat` clean. CI checks it; `gdlint` runs advisory,
  because a style opinion should not block a physics fix.
- `snake_case` for functions and variables, `PascalCase` for classes.
- **Comment the why, not the what.** `# add one to i` is noise. `# The period is
  not a whole number of ticks, so the ship necessarily stops half a tick short`
  is the reason a reader is here.
- British spelling in prose; code identifiers follow whatever Godot uses.

## Commits and pull requests

[Conventional commits](https://www.conventionalcommits.org/): `feat(physics):`,
`fix(vm):`, `docs:`, `test:`, `chore:`.

Say *why* in the body. A commit that explains the constraint that forced a
design is worth ten that restate the diff.

Pull requests should say what you changed, what you measured, and what you are
unsure about. "I am not sure this is the right tolerance" is a useful sentence
and will get you a better review than silence.

## Reporting a bug

The most useful bug report for this project includes the **solution file** —
Results → Export. It carries the mission, the ship, the program, the seed and
the numbers the run produced, so anyone can replay exactly what you saw. If the
replay disagrees with what you got, that is itself the bug and we would very
much like to know.

## What we will say no to

- Anything that makes the simulation non-deterministic.
- Telemetry, analytics, update checks, crash reporting, or any network call the
  player did not ask for.
- Assets whose provenance cannot be stated. See [ASSETS-LICENSE.md](ASSETS-LICENSE.md).
- Making Mission Control helpful. It is supposed to be literal; that is the
  feature. If it is unclear *why* it did something, that is a bug worth fixing —
  but "it should have guessed what I meant" is not.

## Code of conduct

Be decent. Assume the other person is trying. If someone is not, tell a
maintainer rather than the thread.
