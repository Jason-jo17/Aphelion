# The Aphelion flight computer

Your ship does not fly itself and you do not fly it by hand. You write a program,
the program runs on a deterministic virtual machine bolted to the physics clock,
and whatever it does is what happens.

There are two ways to write that program — a text assembly language and a visual
node graph. They are not two systems. **The node graph compiles to the assembly
language**, and only the assembly language executes, so a node graph and its
text form always behave identically and you can move between them freely.

---

## Execution model

The VM runs once at the start of every physics step, before the integrator moves
the ship. It executes instructions until one of three things happens:

1. it reaches a **blocking** instruction (`BURN`, `WAIT`, `ORIENT`, `HALT`);
2. it has executed `max_instructions_per_tick` (default **64**) without
   blocking, in which case it **yields** to the next tick and resumes where it
   left off;
3. it faults.

Yielding rather than faulting is deliberate: a polling loop like

```
loop:   SENSE R0, VVEL
        IF R0 < -5
        BURN 0.5
        JMP loop
```

is a perfectly reasonable way to fly a landing, and it should not be punished for
not using `WAIT UNTIL`. It simply runs at tick rate.

Runaway programs are still bounded and still surfaced. A run ends with a fault
if the program executes more than `max_total_instructions` (default **5 000 000**),
and the results screen calls out a program that spent most of its ticks hitting
the per-tick budget, because that is nearly always an unintended loop.

### Control outputs

The VM owns exactly two outputs: **throttle** and **torque**. Both are held
constant for the whole step (see `docs/DETERMINISM.md`).

**Thrust is applied only during `BURN`.** `THROTTLE` sets the level a subsequent
`BURN` will use; it does not by itself light the engine. `WAIT` always coasts.
This makes a program's thrust profile readable from the instruction list alone,
with no hidden state.

**Attitude is held continuously.** `ORIENT` and `POINT` both set the same
attitude goal, and the reaction wheels chase that goal on every tick regardless
of what else the program is doing. The difference is only that `ORIENT` blocks
until the goal is reached and `POINT` returns immediately. A goal of `PROGRADE`
keeps tracking prograde as prograde moves.

---

## Values

Three kinds of operand appear anywhere a value is expected:

| kind | syntax | notes |
| --- | --- | --- |
| literal | `120`, `-3.5`, `1e4` | plain doubles |
| register | `R0` … `R7` | read/write, start at 0 |
| sensor | `ALT`, `APO`, `PRO`, … | read-only, sampled live |

**Every angle in the ISA is in degrees.** Headings run 0–360 measured
counter-clockwise from the +X axis; relative angles like `PITCH` run −180…180.
The VM converts to radians internally, so you never write π.

Distances are metres, speeds m/s, masses kg, times seconds.

### Sensors

| sensor | unit | meaning |
| --- | --- | --- |
| `ALT` | m | altitude above the surface of the body you are bound to |
| `VEL` | m/s | speed relative to that body |
| `VVEL` | m/s | vertical speed; positive is climbing |
| `HVEL` | m/s | horizontal speed |
| `APO` | m | apoapsis **altitude**; `INF` on an escape trajectory |
| `PERI` | m | periapsis altitude; goes negative when your orbit hits the ground |
| `ECC` | — | eccentricity; 0 is a circle |
| `SMA` | m | semi-major axis (a radius, not an altitude) |
| `TAPO` | s | seconds until apoapsis |
| `TPERI` | s | seconds until periapsis |
| `HDG` | deg | where the ship is pointing |
| `PRO` / `RETRO` | deg | prograde / retrograde heading |
| `RAD` / `ANTIRAD` | deg | straight up / straight down |
| `PITCH` | deg | signed angle from `HDG` to `PRO` |
| `FUEL` | kg | propellant remaining |
| `MASS` | kg | current total mass |
| `DV` | m/s | delta-v remaining |
| `TWR` | — | current thrust-to-weight against local gravity |
| `THR` | — | current throttle setting, 0–1 |
| `GRAV` | m/s² | local gravitational acceleration |
| `DENS` | kg/m³ | atmospheric density here |
| `Q` | Pa | dynamic pressure |
| `T` | s | mission elapsed time |
| `SOI` | — | 0 for the primary, 1+ for a moon |
| `LANDED` | — | 1 when on the surface, else 0 |
| `TGTD` | m | distance to the active target |
| `TGTV` | m/s | speed relative to the target |
| `TGTA` | deg | heading toward the target |

`INF` is a writable literal and compares the way you would expect, so
`IF APO < INF` is a usable "am I still on a closed orbit?" test.

---

## Instructions

Comments run from `;` to end of line. Labels are `name:` on their own or before
an instruction. Everything is case-insensitive. Blank lines and labels cost
nothing.

### Data

```
SET   Rd, value        ; Rd = value
ADD   Rd, value        ; Rd += value
SUB   Rd, value
MUL   Rd, value
DIV   Rd, value        ; division by zero faults
MOD   Rd, value
MIN   Rd, value
MAX   Rd, value
ABS   Rd
NEG   Rd
SENSE Rd, SENSOR       ; Rd = sensor. Identical to SET, and named for clarity.
```

### Flow

```
label:
JMP   label
IF    a <op> b         ; if false, skip the next instruction
HALT                   ; stop the program; the flight continues
NOP
```

`<op>` is one of `<  <=  >  >=  ==  !=`.

`IF` as a conditional *skip* rather than a conditional jump keeps the language
small — one comparison form covers branching, looping and guarding, and the
common case reads as two lines:

```
IF  ALT > 70000
JMP in_space
```

### Attitude

```
ORIENT target           ; block until pointing there, default tolerance 0.5 deg
ORIENT target, tol      ; explicit tolerance in degrees
POINT  target           ; set the goal and carry on
```

`target` is `PROGRADE`, `RETROGRADE`, `RADIAL`, `ANTIRADIAL`, `TARGET`, a
register, a sensor, or an absolute heading in degrees.

### Thrust

```
THROTTLE value          ; 0..1, clamped. Defaults to 1.
BURN  seconds           ; block, engine lit, for this long
BURN  UNTIL a <op> b    ; block, engine lit, until the condition holds
WAIT  seconds           ; block, coasting
WAIT  UNTIL a <op> b    ; block, coasting, until the condition holds
```

`BURN` also ends when the tanks run dry. A `BURN UNTIL` whose condition never
becomes true will therefore end at empty rather than hanging.

### Output

```
LOG value               ; append to the flight log, shown on the results screen
```

---

## Worked example: orbital insertion

```
; Sparrow, launch pad to a 100 km circular orbit.

        THROTTLE 1
        POINT   RAD                ; straight up
        BURN    UNTIL ALT > 800    ; clear the tower before pitching

pitch:  SENSE   R0, ALT            ; gravity turn: pitch over with altitude
        DIV     R0, 24000          ; fully horizontal by 24 km
        MIN     R0, 1
        MUL     R0, 90
        SET     R1, RAD
        SUB     R1, R0
        POINT   R1
        BURN    0.5
        IF      APO < 100000
        JMP     pitch

        THROTTLE 0
        ORIENT  PROGRADE
        WAIT    UNTIL TAPO < 20     ; coast to apoapsis

        THROTTLE 1
        BURN    UNTIL PERI > 97000  ; circularise
        HALT
```

Twenty-two instructions. The fuel-optimal solution is shorter and the
instruction-optimal solution is slower; that tension is the game.

---

## Faults

A fault ends the run and is reported with the line that caused it.

| fault | cause |
| --- | --- |
| `divide_by_zero` | `DIV` or `MOD` by zero |
| `bad_register` | write to something that is not `R0`–`R7` |
| `instruction_cap` | more than `max_total_instructions` executed |
| `no_program` | the program is empty |

Assembly errors are reported before the flight starts, with a line number, the
offending text and a specific message — never just "syntax error".
