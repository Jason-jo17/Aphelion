# Changelog

Notable changes, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[semantic versioning](https://semver.org/) once there is one to follow.

Two kinds of change get called out specially wherever they happen, because both
invalidate work people have already done:

- **Trajectory-changing** — anything that makes the same ship and program fly
  differently. Recorded solutions and leaderboard times from before the change
  no longer compare.
- **Format** — anything that changes how a solution file, save or mission file
  is written or read.

## [Unreleased]

Everything so far. There is no tagged release yet.

### Added

- The simulation: fixed-step RK4 in doubles with deterministic adaptive
  stepping, patched-conic element maths, an exponential co-rotating atmosphere,
  and a moon on a prescribed analytic orbit whose gravity the ship feels.
- `DetMath` — sine, cosine, exp, log, atan and pow built from correctly-rounded
  primitives, because IEEE-754 guarantees nothing about the platform's libm and
  a 1-ULP difference compounds into a different orbit.
- The flight computer: an assembly language with thirty live sensors, an
  assembler that suggests a fix for every error, a VM with a per-tick budget and
  a hard total cap, and a bang-bang attitude controller with rate nulling.
- A visual node graph that compiles to the same text, so only one thing ever
  executes.
- The ship editor: a parts catalogue, derived mass, thrust, moment of inertia
  and frontal-area drag, live delta-v, and validation that refuses an
  unflyable ship with a reason rather than a shrug.
- Fifteen missions, each with a reference solution that earns three stars and is
  re-flown by CI on every push.
- Scoring on fuel, time and program size, with a local leaderboard.
- Solution files that export and re-import and reproduce the run.
- An optional bring-your-own-key Mission Control that translates what you said
  rather than what you meant, and declares its assumptions.
- The interface: five screens, a command palette on Ctrl+K that every screen
  contributes to, design tokens, WCAG AA in both themes, a colourblind-safe
  palette, labelled trajectories, reduced motion and 80–160% interface scale.
- `tools/refsim/` — a Python mirror of the physics used to tune balance without
  a Godot install, and to prove the two implementations agree bit for bit.
- CI: the reference simulation, unit and integration tests, a three-OS
  determinism matrix, and a cross-platform comparison of the results.

### Fixed — trajectory-changing

- **Godot's float parser is not correctly rounded.** A cos kernel coefficient
  read 4 ULP from the nearest double, and Halcyon's rotation rate 29 ULP. The
  second was costing four missions their recorded state hash while every other
  test passed. Constants are now derived (a rotation *period*, not a rate) or
  written as exact integer-over-power-of-two ratios; `data/` and `missions/` are
  pinned by a fixture that fails if the two languages ever disagree again.
- `Ship.centre_of_mass()` returned a `Vector2`, which is single-precision. It
  feeds the moment of inertia, so this put 32-bit rounding straight into the
  trajectory.
- Drag summed each part's area instead of using the ship's frontal width, which
  cost about 2 km/s of delta-v on ascent.
- `TPERI` returned infinity on a hyperbola instead of solving the hyperbolic
  Kepler equation.

### Fixed

- `NodeGraph` emitted a `HALT` landing pad nothing jumped to, so every
  node-graph program scored one instruction worse than the same program typed
  by hand.
- Two test files were being skipped in silence: both called `assert_le()`, which
  GUT spells `assert_lte()`, and a script that fails to parse is a warning that
  still exits zero. 131 tests became 176. CI now fails on that warning.
- The cross-platform determinism report recorded the literal string `"%.17g"`
  as every mission's fuel — GDScript's `%` has no `g` conversion — so the
  comparator was diffing a constant and could never have reported a difference.
  It compares raw IEEE-754 bytes now.
- Malformed JSON is reported rather than pushed to the engine log, in the three
  places where the input is arbitrary by nature: a solution file a player picked
  from disk, and an LLM reply.

### Documentation

- `docs/DETERMINISM.md` — nine rules, each with the reasoning and the
  measurement behind it.
- `docs/ISA.md`, `docs/MISSIONS.md`, `docs/BALANCE.md`, `docs/PACKAGING.md`,
  `docs/MISSION_CONTROL.md`.
- `THIRD-PARTY-NOTICES.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, issue forms and
  a pull-request template.

[Unreleased]: https://github.com/Jason-jo17/Aphelion/commits/HEAD
