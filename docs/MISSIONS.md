# Missions

A mission is one JSON file in `missions/`. It describes a world, a starting
state, what counts as winning, what counts as losing, and what a three-star
solution looks like.

Adding one is the best first contribution to Aphelion, and it needs no GDScript.

## Where the star thresholds come from

They are not guesses. Every mission ships with a **reference solution** — a real
flight-computer program that solves it — and the thresholds are set from what
that program actually achieved, plus 2%:

```sh
python3 tools/refsim/author_missions.py           # fly them all, report
python3 tools/refsim/author_missions.py --write   # regenerate missions/*.json
```

So a three-star solution is known to exist for every mission in the game. CI
re-flies all fifteen on every push (`tests/integration/`), which means a change
to the physics that quietly makes a mission unwinnable fails the build rather
than reaching a player.

The reference solution is stored in each mission file under `reference`, along
with the fuel, time and instruction count it achieved and the hash of its final
state. It is the answer key: read it only when you want to be spoiled.

## The current fifteen

| # | mission | teaches |
| --- | --- | --- |
| 1 | First Light | THROTTLE, BURN, HALT |
| 2 | Thin Air | coasting — an engine you switched off costs nothing |
| 3 | Sideways | ORIENT and POINT; orbit is a sideways problem |
| 4 | Insertion | raise apoapsis, then circularise at it |
| 5 | Circular Reasoning | eccentricity; holding a shape, not hitting a number |
| 6 | Higher Ground | the Hohmann transfer |
| 7 | Thick Air | aerobraking; spending atmosphere instead of propellant |
| 8 | Station Keeping | to catch something ahead of you, go *down* |
| 9 | The Long Way Round | phasing; waiting is a manoeuvre |
| 10 | Slip the Leash | escape velocity and what eccentricity 1 means |
| 11 | Reaching Lyra | transfer windows |
| 12 | Tightening the Knot | capture burns at periapsis |
| 13 | Touchdown | powered descent with no atmosphere |
| 14 | Homeward | aerocapture |
| 15 | The Whole Job | all of it, in one program, hands off |

## File format

```jsonc
{
  "id": "insertion",              // unique; the filename is 'NN_id.json'
  "order": 4,                     // play order
  "title": "Insertion",
  "teaches": "the two-part ascent",
  "brief": "Markdown-ish prose shown on the briefing screen.",
  "hints": ["Shown one at a time, on request."],

  "primary": "halcyon",           // the body everything orbits
  "bodies": ["halcyon", "lyra"],  // which bodies exist in this mission

  "ship": {
    "policy": "stock",            // "stock" hands them a ship; "custom" opens the editor
    "id": "sparrow",              // which stock ship (data/ships.json)
    "fuel_fraction": 1.0          // start with partly empty tanks
  },

  "start": { /* see below */ },
  "targets": [ /* optional rendezvous markers */ ],
  "active_target": "anchor",      // which one the TGT* sensors read

  "time_limit": 3600,             // mission seconds before the run fails

  "success": { /* predicate */ },
  "failure": [ { "when": { /* predicate */ }, "message": "..." } ],

  "stars": { "fuel": 4463.0, "time": 364.0, "instructions": 17 }
}
```

### Starting states

**`surface`** — on the ground, already turning with the body.

```json
{ "kind": "surface", "body": "halcyon", "surface_angle": 0 }
```

**`orbit`** — a conic, given by its apsides and where along it you are.

```json
{ "kind": "orbit", "body": "halcyon",
  "periapsis": 100000, "apoapsis": 400000,
  "true_anomaly": 0,      // degrees from periapsis, in the direction of travel
  "argument": 0,          // degrees; where periapsis points
  "direction": 1 }        // 1 prograde, -1 retrograde
```

`altitude` is shorthand for a circular orbit.

**`state`** — raw numbers, for trajectories no conic describes (a hyperbolic
approach, say). Derive them reproducibly rather than by hand; see how
`tools/refsim/author_missions.py` builds the one for Tightening the Knot.

```json
{ "kind": "state", "px": 11627722.772, "py": -1556087.936,
  "vx": 245.3259, "vy": 887.5207, "angle": 0.0 }
```

### Predicates

Predicates describe themselves — the objectives panel renders the predicate, so
what the player is told and what the game checks cannot drift apart. Write the
condition and the text follows.

```jsonc
{ "sensor": "APO", "op": ">=", "value": 100000 }     // any ISA sensor, any of < <= > >= == !=
{ "sensor": "APO", "between": [95000, 105000] }
{ "flag": "landed" }                                  // landed crashed out_of_fuel program_done escaped
{ "all": [ ... ] }  { "any": [ ... ] }  { "not": { ... } }
{ "sustain": 30.0, "of": { ... } }                    // must hold continuously
```

`"value": "inf"` works, since JSON has no infinity.

A `sustain` window also caps how far the simulation may fast-forward, so a
"hold this for thirty seconds" objective can never be satisfied by one large
step.

### Targets

Rendezvous targets ride prescribed circular orbits rather than being integrated,
so they cannot drift out from under a solution that used to work.

```json
{ "id": "anchor", "name": "Anchor Station", "body": "halcyon",
  "orbit_radius": 840000.0, "orbit_phase0": 0.00714, "orbit_direction": 1 }
```

A target with `orbit_radius: 0` sits at the centre of its parent, which makes
`TGTA` a bearing to that body — how *Homeward* lets a program work out which way
is "backwards along Lyra's orbit".

## Designing one that is worth playing

- **Teach one thing.** Every mission above has a single line in its `teaches`
  field. If you cannot write that line, the mission is doing too much.
- **Make the wrong answer instructive.** *Thin Air* can be solved by burning all
  the way up — it just arrives with 0.8 t instead of 2.2 t, and the fuel gate
  turns that into a lesson rather than a shrug.
- **Leave margin at first, then take it away.** The Sparrow reaches orbit with
  about 670 m/s to spare. Early missions should survive a clumsy solution; the
  stars are where precision gets rewarded.
- **Check the numbers before you write the prose.** `tools/refsim/` will fly
  anything you give it in a fraction of a second. Every mission above went
  through several rounds of that, and two of them were redesigned outright
  because the physics said the story did not work.

## Contributing one

1. Add it to `MISSIONS` in `tools/refsim/author_missions.py`, with a reference
   solution.
2. Run the tool. Iterate until it flies.
3. Run it with `--write` to regenerate `missions/`.
4. Commit the mission file *and* the authoring entry together.

`good first issue` on this repository is nearly always a new mission.
