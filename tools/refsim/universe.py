"""The Aphelion system, shared by the reference sim and the shipped JSON.

Kept in one place so that tuning a constant here and regenerating
``missions/universe.json`` cannot leave the two out of step.
"""

import math

HALCYON = dict(
    id="halcyon",
    name="Halcyon",
    mu=3.6864e12,          # surface gravity 9.0 m/s^2 at r = 640 km
    radius=640_000.0,
    rotation_period=21_600.0,   # 6 hours
    atmosphere=dict(height=70_000.0, sea_level_density=0.8, scale_height=6_000.0),
    color="#3f6fa8",
)

LYRA = dict(
    id="lyra",
    name="Lyra",
    mu=6.5e10,
    radius=200_000.0,
    orbit_radius=12_000_000.0,
    orbit_phase0=0.0,
    rotation_period=136_000.0,
    color="#b9bec9",
)


def rotation_rate(period_s):
    return 2.0 * math.pi / period_s


def summary():
    mu, R = HALCYON["mu"], HALCYON["radius"]
    lines = []
    g = mu / (R * R)
    lines.append(f"Halcyon: R={R/1000:.0f} km  g0={g:.3f} m/s^2  "
                 f"v_circ_surface={math.sqrt(mu/R):.1f}  v_esc={math.sqrt(2*mu/R):.1f}")
    lines.append(f"  sidereal day {HALCYON['rotation_period']/3600:.1f} h -> "
                 f"equatorial surface speed {rotation_rate(HALCYON['rotation_period'])*R:.1f} m/s")
    for alt in (70_000, 100_000, 150_000, 300_000, 1_000_000):
        r = R + alt
        v = math.sqrt(mu / r)
        T = 2 * math.pi * r / v
        lines.append(f"  alt {alt/1000:6.0f} km -> r={r/1000:7.1f} km  "
                     f"v_circ={v:7.1f} m/s  T={T:8.1f} s ({T/60:.1f} min)")
    a = LYRA["orbit_radius"]
    n = math.sqrt(mu / a ** 3)
    soi = a * (LYRA["mu"] / mu) ** 0.4
    lines.append(f"Lyra: a={a/1e6:.1f} Mm  T={2*math.pi/n/3600:.2f} h  "
                 f"v={a*n:.1f} m/s  SOI={soi/1000:.0f} km  "
                 f"g_surf={LYRA['mu']/LYRA['radius']**2:.3f} m/s^2  "
                 f"v_circ_low={math.sqrt(LYRA['mu']/(LYRA['radius']+20000)):.1f} m/s")
    return "\n".join(lines)


if __name__ == "__main__":
    print(summary())
