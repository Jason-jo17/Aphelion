---
name: orbital-mechanics-cheatsheet
description: Orbital mechanics formulas and the Aphelion system's numbers — vis-viva, Hohmann transfers, transfer windows, phasing, capture and landing budgets. Load when designing or debugging a mission, or when a manoeuvre is not doing what you expected.
---

# Orbital mechanics, and Aphelion's numbers

## The system

| | Halcyon | Lyra |
| --- | --- | --- |
| μ | 3.6864e12 m³/s² | 6.5e10 |
| radius | 640 km | 200 km |
| surface g | 9.000 m/s² | 1.625 |
| escape (surface) | 3394 m/s | 806 |
| day | 6 h (equator 186 m/s) | 37.787 h, locked |
| atmosphere | 70 km, ρ₀ 0.8, H 6 km | none |
| orbit about Halcyon | — | 12 000 km, 554 m/s, 37.79 h, SOI 2386 km |

Halcyon orbits:

| alt | radius | v_circ | period |
| --- | --- | --- | --- |
| 70 km | 710 km | 2279 m/s | 32.6 min |
| 100 km | 740 km | 2232 m/s | 34.7 min |
| 150 km | 790 km | 2160 m/s | 38.3 min |
| 300 km | 940 km | 1980 m/s | 49.7 min |
| 1000 km | 1640 km | 1499 m/s | 114.5 min |

## Formulas

```
v_circ  = sqrt(mu / r)
v_esc   = sqrt(2 mu / r)
vis-viva: v = sqrt(mu (2/r - 1/a))
a       = (r_p + r_a) / 2
e       = (r_a - r_p) / (r_a + r_p)
T       = 2 pi sqrt(a^3 / mu)
dv      = Isp * 9.80665 * ln(m0 / m1)          Tsiolkovsky
```

**Hohmann**, r1 → r2:
```
a_t  = (r1 + r2) / 2
dv1  = sqrt(mu(2/r1 - 1/a_t)) - sqrt(mu/r1)
dv2  = sqrt(mu/r2) - sqrt(mu(2/r2 - 1/a_t))
tof  = pi sqrt(a_t^3 / mu)
```

**Transfer window.** The target must be where you are going, not where it is.
Lead angle = 180° − (target's angular rate × time of flight). For Halcyon 150 km
→ Lyra: tof 26 461 s, Lyra moves 70°, so leave when it is **110° ahead**.
Windows recur every synodic period, 2π/(n_ship − n_target) = 2337 s ≈ 39 min.

**Phasing.** To gain angle on something in your orbit, drop into a shorter one
and wait. Gain per lap = 2π(1 − T₁/T₀). Laps are coarse — one is worth hundreds
of kilometres — so finish with a small computed lap:

```
periapsis drop ≈ k × gap        k ≈ 0.19 at 300 km, ≈ 0.21 at 200 km
```

Derive k from `dr_p = 2a·ΔT/(1.5·T)` with `ΔT = −s/v`.

## Delta-v budget (measured, not estimated)

| leg | cost |
| --- | --- |
| Halcyon surface → 100 km orbit | ~3270 m/s (ideal 2046 + ~1220 losses) |
| 100 → 150 km | ~90 m/s |
| 150 km → Lyra injection | ~800 m/s |
| Lyra capture, 50 km orbit | ~280 m/s |
| Lyra orbit → surface | ~580 m/s |
| Lyra escape from 100 km | ~190 m/s |
| 12 Mm apoapsis → 44 km periapsis | ~30 m/s |

## Manoeuvres that surprise people

- **To catch something ahead of you, burn retrograde.** Lower orbits are faster.
  Burning toward it raises your orbit and you fall further behind.
- **Burn at apoapsis to raise periapsis**, and vice versa. You cannot raise
  periapsis from periapsis — it is the one place that will not work, and it is
  how the aerobraking mission goes wrong if you check at the wrong moment.
- **Capture at periapsis.** Fastest point, so a burn there buys the most change
  in energy per kilogram (Oberth).
- **Aerobraking collapses suddenly.** Once apoapsis drops into the atmosphere
  the orbit comes apart within one pass. Leave early.
- **One deep aerocapture pass** at 44 km periapsis takes 12 000 km off the far
  side for 30 m/s. At 50 km it barely touches you; at 48 km with Lyra's
  perturbation it can be fatal.

## Tools

```sh
python3 tools/refsim/universe.py          # system summary
python3 tools/refsim/ships.py             # stock ships, inertia, slew times
python3 tools/refsim/validate_physics.py  # conservation and accuracy
python3 tools/refsim/tune_missions.py     # fly variants, trace a flight
```

When a manoeuvre surprises you, **trace the flight before changing the code**.
Twice during the original build a "bug" turned out to be the physics being right
and the mission design being wrong.
