# Balance

Every number in `data/parts.json`, `data/ships.json` and `data/universe.json` was
chosen by flying it, not by feel. The tools under `tools/refsim/` do the flying.

## The system

| | Halcyon | Lyra |
| --- | --- | --- |
| radius | 640 km | 200 km |
| surface gravity | 9.000 m/s² | 1.625 m/s² |
| μ | 3.6864e12 m³/s² | 6.5e10 m³/s² |
| escape speed (surface) | 3394 m/s | 806 m/s |
| sidereal day | 6 h | 37.787 h (tidally locked) |
| atmosphere | 70 km, ρ₀ 0.8, H 6 km | none |

Orbits about Halcyon:

| altitude | radius | circular speed | period |
| --- | --- | --- | --- |
| 70 km | 710 km | 2279 m/s | 32.6 min |
| 100 km | 740 km | 2232 m/s | 34.7 min |
| 150 km | 790 km | 2160 m/s | 38.3 min |
| 300 km | 940 km | 1980 m/s | 49.7 min |
| 1000 km | 1640 km | 1499 m/s | 114.5 min |

Lyra orbits at 12 Mm, 554 m/s, 37.79 hours, with a 2386 km sphere of influence.
Low Lyra orbit (20 km) is 544 m/s.

Launching eastward from Halcyon's equator is worth 186 m/s for free.

## Delta-v budget

Measured by flying a gravity turn in `tools/refsim/tune_ascent.py`, searching the
pitch programme for the cheapest ascent:

| leg | cost |
| --- | --- |
| Halcyon surface → 100 km orbit | ~3270 m/s |
| ...of which is the ideal (2232 − 186) | 2046 m/s |
| ...of which is gravity and drag losses | ~1220 m/s |
| 100 km → 150 km (Hohmann) | ~90 m/s |
| 100 km orbit → Lyra transfer injection | ~1000 m/s |
| Lyra capture into 50 km orbit | ~280 m/s |
| Lyra orbit → surface (powered descent) | ~580 m/s |

## Stock ships

| ship | wet | delta-v | TWR (Halcyon) | inertia | 90° slew | drag area | burn time |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Sparrow | 5420 kg | 3941 m/s | 2.46 | 21 418 kg·m² | 3.3 s | 2.0 m² | 98 s |
| Wren | 1650 kg | 3717 m/s | 2.69 | 4 821 kg·m² | 2.8 s | 1.0 m² | 93 s |
| Heron | 1770 kg | 3287 m/s | 2.51 | 6 264 kg·m² | 3.1 s | 3.0 m² | 93 s |
| Petrel | 2140 kg | 2441 m/s | 2.08 | 10 692 kg·m² | 4.1 s | 8.0 m² | 93 s |
| Albatross | 9840 kg | 4933 m/s | 1.36 | 86 603 kg·m² | 6.7 s | 4.0 m² | 196 s |

The Sparrow reaches a 100 km orbit with about **670 m/s to spare**. That margin is
the design target: wide enough that a first solution can be clumsy and still
succeed, narrow enough that fuel stays a real scoring axis.

## Drag

Aphelion is two-dimensional and has no nose cones, so per-part drag shapes would
be detail the player cannot see or act on. Instead:

- every hull uses the same blunt-body coefficient, **Cd = 0.35**;
- the reference **area is the ship's frontal width × 1 m**, so a wide ship
  genuinely catches more air than a narrow one;
- only parts whose whole purpose is drag carry `extra_drag_area` — currently just
  the Ablative Shield, at +6 m².

An early draft summed a per-part drag area, which gave the Sparrow 6.9 m² and cost
**2085 m/s of the 3455 m/s it had**. The ascent was unflyable and the cause was
invisible. The frontal-area model puts it at 2.0 m² and the loss where it belongs.

## Changing any of this

`data/*.json` and `tools/refsim/universe.py` describe the same system. Change
both, then:

```sh
python3 tools/refsim/validate_physics.py   # conservation and accuracy
python3 tools/refsim/ships.py              # stock ship summary table
python3 tools/refsim/tune_ascent.py        # is orbit still reachable?
```

If a mission's star thresholds were derived from a number you moved, regenerate
them too — see `docs/MISSIONS.md`.
