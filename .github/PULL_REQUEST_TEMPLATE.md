## What this changes

<!-- One or two sentences. What is different after this lands? -->

## Why

<!-- The problem, not the patch. If it fixes an issue, "Fixes #123" here. -->

## How it was checked

<!-- Replace with what you actually ran. Delete the lines that do not apply. -->

- [ ] `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
- [ ] `python3 tools/refsim/validate_physics.py`
- [ ] `python3 tools/refsim/author_missions.py`
- [ ] `gdformat --check $(git ls-files '*.gd')`

<!--
GUT reports a test script that fails to *parse* as a yellow "Ignoring script"
warning and still exits zero. Check the `Scripts` count at the bottom matches
the number of tests/**/test_*.gd files — CI does, but it is easy to be fooled
locally.
-->

## If this touches the simulation

Delete this whole section if it does not. If it does, all four apply — see
[docs/DETERMINISM.md](https://github.com/Jason-jo17/Aphelion/blob/HEAD/docs/DETERMINISM.md):

- [ ] `scripts/physics/` and `tools/refsim/` changed together
- [ ] Fixtures and missions regenerated **in this commit**, missions first:
      `python3 tools/refsim/author_missions.py --write` then
      `python3 tools/refsim/generate_fixtures.py`
- [ ] No new decimal literal carries a precise value — derived, or written as an
      exact ratio, or short enough that `tests/unit/test_data_literals.gd` passes
- [ ] No call to the global `sin`/`cos`/`exp`/`log`/`pow`/`atan`/`atan2`/`acos`/
      `asin`/`fmod` outside rendering code — `DetMath` instead

## Anything else

<!-- Trade-offs you made, things you are unsure about, what you want reviewed
hardest. Saying "I am not sure this is the right place for it" is welcome and
saves a round trip. -->
