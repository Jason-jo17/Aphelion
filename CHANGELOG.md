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
- A `Makefile` — `make setup`, `make run`, `make test`, `make check` — so the
  headless invocations are not something to remember.
- `tools/capture_screens.gd`, which drives the real screens under a virtual
  display to produce the README images. A screenshot nobody can regenerate is a
  screenshot that goes stale unnoticed.
- A CI job that runs it and fails on any `SCRIPT ERROR`. Every test in the suite
  passes without a single frame ever being drawn, which is how three screens
  came to be broken with the build green; this is the job that notices.

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

### Fixed — visible in the interface

Found by rendering the game under a virtual display for the first time and
looking at the result. None of these had a test, and none of them showed up in a
headless run.

- The flight map labelled both apsis markers `%g km`. GDScript's `%` operator
  has no `g` conversion; it pushes an engine error and substitutes the literal
  text. `Fmt.distance_coarse()` now trims the trailing zero itself, and a test
  scans every format string in the project for a conversion GDScript does not
  have — the same mistake had already been made twice.
- The flight computer opened **empty on every mission**. `ProgramEditor.set_source()`
  wrote to a `CodeEdit` that `_ready()` had not created yet, silently losing the
  starter program that exists so nobody faces a blank page after a briefing.
- The results screen had no keyboard focus, because `grab_focus()` was called on
  a button that was not in the tree yet.
- "Instructions executed  3665.0" — a count formatted as a measurement. `Fmt.count()`
  now groups digits and never produces a decimal point.
- Objectives read "periapsis at least 90.00 km", which looks like a tolerance
  somebody measured rather than a number the mission author typed. Briefings and
  the in-flight objective list are coarse now; instruments still are not.

### Fixed — layout and framing

Found by capturing every screen at each theme, palette and interface scale and
looking at all of them.

- **The orbital map was zoomed three times too far out on every flight.** The
  zoom is derived from the control's size, and the size is zero until the layout
  pass has run — so framing from a screen's `_ready()` computed a scale from
  nothing. The planet was a small disc in a sea of black, which looked enough
  like a deliberate "you are a long way from home" choice to survive unnoticed.
  The view now re-applies its framing whenever it is resized, which also fixes
  the map staying wrongly zoomed after a window resize.
- **A flight now opens centred on the body it is orbiting**, sized to fit the
  orbit, rather than centred on the ship — which put the planet against one edge
  with half the map empty sky.
- **Three screens clipped their content and could not be scrolled to it.** The
  briefing lost 165 px at 130% and 428 px at 160%; the results screen 107 px at
  160%; the editor overflowed even at 100%, so the delta-v readout and the
  validation warnings — the two things most needed while building a ship — were
  off the bottom with no way to reach them. Every screen is a scrollable page
  now, and `follow_focus` means tabbing to something off-screen brings it into
  view instead of moving focus somewhere invisible.
- The editor screen was 14 px over the canvas at the default scale, so every
  player got a scrollbar to reveal fourteen pixels of nothing. It is a dense
  working screen and now uses tighter top and bottom margins than the reading
  screens.
- The campaign progress indicator drew **one glyph per star**, which is right
  for a mission's three and unreadable for the campaign's forty-five: the menu
  header was a row of forty-five tiny stars that read as corruption rather than
  progress. Past a handful, one star is an icon and the fraction does the work.
- The screenshot tool pinned neither theme nor interface scale, so the README
  images came out at whatever the last person to run the game had left in their
  settings file — which is how they were once captured at 160%.

CI now fails if any screen clips content it cannot scroll to, at 80%, 100%,
130% or 160%. The check was verified by reverting one of the fixes and watching
it fail.

### Fixed — the map was drawing a path through the planet

The predicted orbit was drawn as a complete conic regardless of where it went.
On an ascent the periapsis is usually hundreds of kilometres underground, so the
map showed a dashed ellipse sailing straight through the rock and out the other
side, with a labelled marker at the bottom of it reading "Pe -205.9 km" —
pointing at a place on the map that does not exist, for a spot the ship never
reaches because it hits the ground first.

The conic is now broken wherever it passes below the surface, and where it
first crosses from sky into ground it is marked **Impact**. The legend has
carried an "impact" entry since the first version of this map; this is the
thing it was describing. The underground periapsis marker is gone — the number
still matters and the instruments panel still shows it, because that negative
figure is exactly how much periapsis has to come up.

### Changed — parts look like the parts they are

Every part was the same rounded rectangle, so a crew capsule, a propellant
tank, an engine bell and a reaction wheel differed only by hue and two initials
— and the three structural parts (a strut, an ablative shield and a set of
landing legs) did not differ at all, since they share a category. A ship is
something you look at in order to understand it, so it has to look like the
thing it is.

Each part now carries a `shape`, defaulting from its category and named
explicitly in `data/parts.json` where the category cannot say enough. There are
eight: a tapered capsule with a window, a probe core under an antenna, a banded
tank, a flared engine bell, a gyro in its housing, a cross-braced strut, an
ablative dome, and legs braced out to a pair of feet.

The initials stay, because a silhouette is a non-colour signal but not one
anything can read aloud. They moved to the bottom edge on a dark backing plate
— centred, they landed on the capsule's window and the reaction wheel's gyro,
and two marks on top of each other read as neither — and a one-cell part gets
two letters rather than three, which is all that fits at a size worth drawing.

### Changed — what the map costs to draw

- The trail was drawing **one `draw_circle` per powered sample, every frame**.
  The trail is capped at 4096 samples, so a flight that spends most of its time
  under thrust was issuing thousands of draw calls per frame for what is
  conceptually a few line segments. Powered flight is now drawn as runs of
  connected path, which is both far cheaper and a better picture: a burn is a
  stretch of the trajectory, not a scatter of dots.
- The points array behind the trail is sized once instead of grown a point at a
  time, so it is no longer reallocated thousands of times a second.
- The pulsing ring around the ship marker has its own node. Animating it used
  to redraw the entire map — planet, atmosphere, trail, predicted conic and
  every label — sixty times a second for ever, including while paused. It now
  costs one arc, and the map redraws only when something on it has moved.
- `anti_aliasing/quality/msaa_2d` is gone from `project.godot`. The renderer is
  Compatibility, which does not implement 2D MSAA, so the setting logged
  "2D MSAA is not yet supported for GLES3" on every launch and changed nothing.
  The map asks for antialiasing on each draw call instead, which does work.

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
