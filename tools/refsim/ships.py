"""Port of scripts/editor/{part_def,part_catalog,ship}.gd.

Loads the real data/parts.json and data/ships.json so that balance work uses
exactly the ships the game ships with, including the true moment of inertia.
"""

import json
import math
import os

import sim

_HERE = os.path.dirname(os.path.abspath(__file__))
_DATA = os.path.normpath(os.path.join(_HERE, "..", "..", "data"))

DRAG_COEFFICIENT = 0.35
HULL_DEPTH = 1.0


def _load(name):
    with open(os.path.join(_DATA, name)) as f:
        return json.load(f)


class Catalog:
    def __init__(self):
        raw = _load("parts.json")
        self.grid = raw["grid"]
        self.parts = {p["id"]: p for p in raw["parts"]}

    def get(self, pid):
        return self.parts[pid]


class ShipDesign:
    def __init__(self, placements, catalog, name="Untitled"):
        self.placements = placements
        self.catalog = catalog
        self.display_name = name

    def frontal_width(self):
        if not self.placements:
            return 0.0
        lo = min(p["x"] for p in self.placements)
        hi = max(p["x"] + self.catalog.get(p["part_id"])["size"][0] for p in self.placements)
        return max(0.0, (hi - lo) * self.catalog.grid["cell_size"])

    def centre_of_mass(self):
        cell = self.catalog.grid["cell_size"]
        total = cx = cy = 0.0
        for p in self.placements:
            d = self.catalog.get(p["part_id"])
            m = d["mass"] + d.get("fuel_capacity", 0.0)
            if m <= 0.0:
                continue
            w, h = d["size"]
            cx += m * (p["x"] + w * 0.5) * cell
            cy += m * (p["y"] + h * 0.5) * cell
            total += m
        if total <= 0.0:
            return (0.0, 0.0)
        return (cx / total, cy / total)

    def moment_of_inertia(self):
        cell = self.catalog.grid["cell_size"]
        comx, comy = self.centre_of_mass()
        total = 0.0
        for p in self.placements:
            d = self.catalog.get(p["part_id"])
            m = d["mass"] + d.get("fuel_capacity", 0.0)
            if m <= 0.0:
                continue
            wc, hc = d["size"]
            w = wc * cell
            h = hc * cell
            px = (p["x"] + wc * 0.5) * cell
            py = (p["y"] + hc * 0.5) * cell
            own = m * (w * w + h * h) / 12.0
            dx = px - comx
            dy = py - comy
            total += own + m * (dx * dx + dy * dy)
        return total

    def to_profile(self):
        dry = fuel = thrust = flow = torque = extra = landing = 0.0
        for p in self.placements:
            d = self.catalog.get(p["part_id"])
            dry += d["mass"]
            fuel += d.get("fuel_capacity", 0.0)
            if d.get("thrust", 0.0) > 0.0 and d.get("isp", 0.0) > 0.0:
                thrust += d["thrust"]
                flow += d["thrust"] / d["isp"]
            torque += d.get("torque", 0.0)
            extra += d.get("extra_drag_area", 0.0)
            landing = max(landing, d.get("max_landing_speed", 0.0))
        return sim.ShipProfile(
            dry_mass=dry, fuel_capacity=fuel, max_thrust=thrust,
            isp=(thrust / flow) if flow > 0.0 else 0.0,
            max_torque=torque,
            inertia=max(1.0, self.moment_of_inertia()),
            drag_coefficient=DRAG_COEFFICIENT,
            drag_area=max(0.5, self.frontal_width() * HULL_DEPTH + extra),
            max_landing_speed=landing,
            display_name=self.display_name)


_catalog = None
_stock = None


def catalog():
    global _catalog
    if _catalog is None:
        _catalog = Catalog()
    return _catalog


def stock(ship_id):
    global _stock
    if _stock is None:
        _stock = {s["id"]: s for s in _load("ships.json")["ships"]}
    s = _stock[ship_id]
    return ShipDesign(s["placements"], catalog(), s["name"])


def stock_ids():
    global _stock
    if _stock is None:
        _stock = {s["id"]: s for s in _load("ships.json")["ships"]}
    return list(_stock.keys())


def slew_time(profile, angle_rad):
    """Seconds to rotate `angle_rad` with a bang-bang torque profile, which is
    what the flight computer's ORIENT does."""
    if profile.max_torque <= 0.0 or profile.inertia <= 0.0:
        return math.inf
    alpha = profile.max_torque / profile.inertia
    return 2.0 * math.sqrt(abs(angle_rad) / alpha)


if __name__ == "__main__":
    print(f"{'ship':11} {'wet kg':>7} {'dv m/s':>7} {'TWR-H':>6} {'I kg m2':>9} "
          f"{'alpha':>7} {'90deg':>6} {'area':>5} {'burn s':>7}")
    print("-" * 82)
    for sid in stock_ids():
        d = stock(sid)
        pr = d.to_profile()
        a = pr.max_torque / pr.inertia
        print(f"{sid:11} {pr.dry_mass+pr.fuel_capacity:7.0f} {pr.delta_v():7.0f} "
              f"{pr.twr(9.0):6.2f} {pr.inertia:9.0f} {a:7.3f} "
              f"{slew_time(pr, math.pi/2):6.1f} {pr.drag_area:5.1f} {pr.burn_time():7.0f}")
