# Aphelion

[![ci](https://github.com/Jason-jo17/Aphelion/actions/workflows/ci.yml/badge.svg)](https://github.com/Jason-jo17/Aphelion/actions/workflows/ci.yml)
[![code: MIT](https://img.shields.io/badge/code-MIT-blue.svg)](LICENSE)
[![assets: CC0](https://img.shields.io/badge/assets-CC0-blue.svg)](ASSETS-LICENSE.md)
[![Godot 4.7](https://img.shields.io/badge/Godot-4.7-478cbf.svg)](https://godotengine.org/)

**Design a spacecraft, program its flight computer, and let real orbital
mechanics decide what happens next.**

You do not fly the ship. You write a program, that program runs on a
deterministic virtual machine bolted to the physics clock, and whatever it does
is what happens. Fifteen missions take you from a three-instruction hop to a
hands-off flight from the launch pad to a moon.

Free, open source, offline by default, no telemetry, no account.

> **Status: pre-release.** The simulation, the language, all fifteen missions
> and the interface are built and tested — 176 tests, and every mission's
> three-star reference solution is re-flown on each push. There is no tagged
> release yet, so for now it is a build-from-source project.

```
; First Light — straight up, ten kilometres.
        THROTTLE 1
        BURN    UNTIL ALT > 10000
        HALT
```

```
; Insertion — gravity turn to a 100 km apoapsis, coast, circularise.
        THROTTLE 1
        POINT   RAD
        BURN    UNTIL ALT > 600
turn:   SENSE   R0, ALT
        DIV     R0, 20000
        MIN     R0, 1
        MUL     R0, 84
        SET     R1, RAD
        SUB     R1, R0
        POINT   R1
        BURN    0.25
        IF      APO < 105000
        JMP     turn
        ORIENT  PROGRADE
        WAIT    UNTIL TAPO < 22
        BURN    UNTIL PERI > 95000
        HALT
```

---

## What makes it different

**The physics is real, and it is the same everywhere.** Fixed-step RK4 in
doubles, patched-conic element maths, an exponential co-rotating atmosphere, and
a moon whose gravity you feel. Energy holds to two parts in 10¹³ over ten orbits.
The same ship, program and seed produce the *identical* trajectory on Windows,
macOS and Linux — verified on every push by running all fifteen reference
flights on all three and comparing hashes. See [docs/DETERMINISM.md](docs/DETERMINISM.md)
for how, and why that required writing our own sine.

**You program it, in two views that cannot disagree.** A text assembly language
with thirty live sensors, and a visual node graph — where the graph *compiles to
the text*, so only one thing ever executes and you can move between them freely.
[docs/ISA.md](docs/ISA.md) is the language reference.

**Three scores that fight each other.** Fuel, time, and program size. The
cheapest ascent is slow, the fastest burns hard, and the shortest program does
neither well. Every mission ships with a reference solution that earns all three
stars, so you know the target is reachable — CI re-flies them to keep it true.

**An optional co-pilot that is allowed to be wrong.** Bring your own API key and
you can radio Mission Control in English. It is instructed to translate what you
*said*, not what you meant, and to declare every assumption it had to make. Say
"make the orbit round" and you get three assumptions and a burn at the wrong
apsis. Say "circularise at apoapsis at 100 km, quarter throttle" and you get
three instructions that work. That gap is the lesson.
[docs/MISSION_CONTROL.md](docs/MISSION_CONTROL.md).

---

## Running it

### Play

Builds appear under [Releases](../../releases) once a version is tagged; there
is none yet. When there is, verify the download with
`sha256sum -c SHA256SUMS.txt`.

On macOS the build is ad-hoc signed rather than notarised, so Gatekeeper will
stop it the first time: right-click → Open. [docs/PACKAGING.md](docs/PACKAGING.md)
explains why and how to add real signing.

### From source

Aphelion targets **Godot 4.7.x** and needs nothing else to run.

```sh
git clone https://github.com/Jason-jo17/Aphelion
cd Aphelion
godot .                       # or open project.godot in the editor
```

### Tests

```sh
./tools/fetch_gut.sh          # fetch the test framework (not vendored)
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

And the reference simulation, which is plain Python with no dependencies and
runs in seconds:

```sh
python3 tools/refsim/validate_physics.py     # 13 numerical checks
python3 tools/refsim/author_missions.py      # fly all fifteen reference solutions
python3 tools/refsim/ships.py                # stock ship balance table
```

---

## The system

| | Halcyon | Lyra |
| --- | --- | --- |
| radius | 640 km | 200 km |
| surface gravity | 9.000 m/s² | 1.625 m/s² |
| escape speed | 3394 m/s | 806 m/s |
| day | 6 h | 37.787 h, tidally locked |
| atmosphere | 70 km | none |

Low orbit is about 100 km and 2232 m/s. Lyra is 12 000 km out; the transfer
takes 7¼ hours, during which Lyra moves 70°, so you leave when it is 110° ahead
and not a moment else. Full numbers in [docs/BALANCE.md](docs/BALANCE.md).

## The missions

| # | mission | teaches |
| --- | --- | --- |
| 1 | First Light | `THROTTLE`, `BURN`, `HALT` |
| 2 | Thin Air | coasting — an engine you switched off costs nothing |
| 3 | Sideways | `ORIENT` and `POINT`; orbit is a sideways problem |
| 4 | Insertion | raise apoapsis, then circularise at it |
| 5 | Circular Reasoning | eccentricity; holding a shape, not hitting a number |
| 6 | Higher Ground | the Hohmann transfer |
| 7 | Thick Air | aerobraking; spending atmosphere instead of propellant |
| 8 | Station Keeping | to catch something ahead of you, go *down* |
| 9 | The Long Way Round | phasing; waiting is a manoeuvre |
| 10 | Slip the Leash | escape velocity, and what eccentricity 1 means |
| 11 | Reaching Lyra | transfer windows |
| 12 | Tightening the Knot | capture burns at periapsis |
| 13 | Touchdown | powered descent with no atmosphere |
| 14 | Homeward | aerocapture |
| 15 | The Whole Job | all of it, in one program, hands off |

Writing a sixteenth needs no GDScript — see [docs/MISSIONS.md](docs/MISSIONS.md).
It is the best first contribution, and `good first issue` on this repository is
nearly always exactly that.

---

## Privacy

Aphelion makes **no** network requests of any kind unless you configure Mission
Control and press Ask. There is no telemetry, no analytics, no update check, no
crash reporting, and no account. Progress and solutions are plain JSON in your
user directory.

If you do configure a co-pilot, the key is yours, the bill is yours, and the
request goes to the provider you chose and nowhere else. The key never enters a
save file, a solution file or a log line. [docs/MISSION_CONTROL.md](docs/MISSION_CONTROL.md)
sets out exactly where it is kept.

## Accessibility

Not a settings page bolted on at the end:

- **Full keyboard control.** Ctrl+K opens a command palette that every screen
  contributes to, so nothing is mouse-only — including the assembly bay.
- **Colour is never the only signal.** Every trajectory carries a hue, a line
  style *and* a text label, so the map reads the same in greyscale. There is a
  second palette built for deuteranopia and protanopia.
- **WCAG AA contrast**, in both themes, checked by a test rather than by eye.
- **Reduced motion** that reaches every animation, because they all go through
  one function.
- **Interface scale** from 80% to 160%.

## Layout

```
scripts/core/        determinism-critical maths, settings, progress, solution files
scripts/physics/     the integrator, bodies, orbital elements — no engine physics
scripts/controller_vm/  the ISA, assembler, VM, attitude control, node compiler
scripts/editor/      parts and ship assembly
scripts/missions/    missions, predicates, scoring
scripts/sim/         the runner that ties it together
scripts/ai/          the optional BYOK co-pilot
scripts/ui/          screens and widgets, built in code from design tokens
data/                the universe, the part catalogue, the stock ships
missions/            fifteen missions, each with its reference solution
tests/               GUT unit and integration tests, golden fixtures
tools/refsim/        a Python mirror of the physics — the parity reference
docs/                ISA, missions, determinism, balance, packaging, Mission Control
```

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md). The short version: missions are the easiest
and most valuable thing to add, `scripts/physics/` and `tools/refsim/` must
change together, and if you touch anything the simulation depends on, regenerate
the fixtures in the same commit.

## Licence

Code is [MIT](LICENSE). Assets, missions and data are [CC0](ASSETS-LICENSE.md) —
a puzzle should be free to remix.

Aphelion vendors nothing, but a released build embeds the Godot engine and its
default theme fonts, which carry their own terms.
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) sets out all four third-party
components, whether each reaches the repository or only the binaries, and
carries the fdlibm notice that the constants in `DetMath` come with.

## Also here

- [CONTRIBUTING.md](CONTRIBUTING.md) — how to add a mission, and the rules that
  are not negotiable
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) — be decent, and what happens if
  someone is not
- [SECURITY.md](SECURITY.md) — what the attack surface actually is, and how to
  report something privately
- [CHANGELOG.md](CHANGELOG.md) — what changed, and when
