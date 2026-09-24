"""Authors missions/*.json, with star thresholds derived from solutions that
were actually flown.

Every mission here carries a reference solution. The tool flies it, checks it
succeeds, and sets the three thresholds from what that flight achieved. So a
three-star solution is known to exist for every mission in the game, and CI
re-flies all of them on every push (tests/integration/) to keep it that way.

Usage:
    python3 tools/refsim/author_missions.py            # report only
    python3 tools/refsim/author_missions.py --write    # regenerate missions/*.json
"""

import json
import math
import os
import sys

import det_math as dm
import runner
import ships
import sim
import vm as vmod

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.normpath(os.path.join(_HERE, "..", ".."))
MISSIONS_DIR = os.path.join(_ROOT, "missions")

# Thresholds are set a hair above what the reference achieved, so a player who
# matches the reference is not defeated by the last decimal place.
FUEL_MARGIN = 1.02
TIME_MARGIN = 1.02

MISSIONS = []


def mission(spec, solution, note=""):
    MISSIONS.append(dict(spec=spec, solution=solution, note=note))


# =============================================================================
# 1. First Light
# =============================================================================
mission(
    dict(
        id="first_light", order=1, title="First Light",
        teaches="THROTTLE, BURN, HALT",
        brief=(
            "Everything starts here. The Sparrow is on the pad, pointed at the sky, "
            "and the flight computer is empty.\n\n"
            "Open the throttle, light the engine, and keep it lit until you are "
            "ten kilometres up. Three instructions will do it."),
        primary="halcyon", bodies=["halcyon"],
        ship=dict(policy="stock", id="sparrow"),
        start=dict(kind="surface", body="halcyon", surface_angle=0),
        time_limit=600,
        success={"sensor": "ALT", "op": ">=", "value": 10000},
        failure=[{"when": {"flag": "crashed"}, "message": "The Sparrow did not survive."}],
        hints=[
            "THROTTLE 1 opens the throttle all the way. It does not light the engine.",
            "BURN is what lights it. `BURN UNTIL ALT > 10000` burns until you are there.",
            "Finish with HALT so the flight computer knows it is done.",
        ],
    ),
    """
; First Light — straight up, ten kilometres.
        THROTTLE 1
        BURN    UNTIL ALT > 10000
        HALT
""")

# =============================================================================
# 2. Thin Air
# =============================================================================
mission(
    dict(
        id="thin_air", order=2, title="Thin Air",
        teaches="coasting — an engine you have switched off is not costing you anything",
        brief=(
            "Halcyon's atmosphere gives out at seventy kilometres. Get above it, and "
            "arrive with at least 2 tonnes still in the tanks.\n\n"
            "You could hold the engine lit the whole way up. It would work, and it "
            "would cost you nearly everything you have. A ship on a ballistic arc is "
            "still climbing with the engine off — so burn until the *apoapsis* is "
            "where you want it, then stop and let go."),
        primary="halcyon", bodies=["halcyon"],
        ship=dict(policy="stock", id="sparrow"),
        start=dict(kind="surface", body="halcyon", surface_angle=0),
        time_limit=900,
        success={"all": [
            {"sensor": "ALT", "op": ">=", "value": 75000},
            {"sensor": "FUEL", "op": ">=", "value": 2000},
        ]},
        failure=[{"when": {"flag": "crashed"}, "message": "The Sparrow did not survive."}],
        hints=[
            "APO is where you *will* end up, not where you are. Burn until it reads "
            "high enough and you have already won; the rest is falling upward.",
            "Burning all the way up to 75 km leaves 0.8 t in the tanks. Burning to a "
            "78 km apoapsis and coasting leaves 2.2 t. Same altitude.",
            "The Q sensor reads dynamic pressure. Watching it teaches you where the "
            "air actually hurts.",
        ],
    ),
    """
; Thin Air — burn until the apoapsis clears the air, then stop and coast.
        THROTTLE 1
        BURN    UNTIL APO > 78000
        HALT
""")

# =============================================================================
# 3. Sideways
# =============================================================================
mission(
    dict(
        id="sideways", order=3, title="Sideways",
        teaches="ORIENT and POINT, and that orbit is a sideways problem",
        brief=(
            "Going up is easy. Going up is also not orbit.\n\n"
            "What keeps a ship in orbit is horizontal speed — enough that the ground "
            "curves away as fast as you fall toward it. Get above fifty kilometres "
            "with at least 1200 m/s of horizontal speed.\n\n"
            "POINT aims the ship without waiting. ORIENT aims it and waits until you "
            "are there."),
        primary="halcyon", bodies=["halcyon"],
        ship=dict(policy="stock", id="sparrow"),
        start=dict(kind="surface", body="halcyon", surface_angle=0),
        time_limit=900,
        success={"all": [
            {"sensor": "ALT", "op": ">=", "value": 50000},
            {"sensor": "HVEL", "op": ">=", "value": 1200},
        ]},
        failure=[{"when": {"flag": "crashed"}, "message": "The Sparrow did not survive."}],
        hints=[
            "RAD is the heading straight up. Subtracting from it tilts you over.",
            "Tilting too early fights the atmosphere; too late wastes the climb.",
            "A gravity turn pitches over gradually as you gain altitude.",
        ],
    ),
    """
; Sideways — climb, then tip over into a gravity turn.
        THROTTLE 1
        POINT   RAD
        BURN    UNTIL ALT > 1200
turn:   SENSE   R0, ALT
        DIV     R0, 30000
        MIN     R0, 1
        MUL     R0, 80
        SET     R1, RAD
        SUB     R1, R0
        POINT   R1
        BURN    0.25
        IF      HVEL < 1250
        JMP     turn
        HALT
""")

# =============================================================================
# 4. Insertion
# =============================================================================
mission(
    dict(
        id="insertion", order=4, title="Insertion",
        teaches="the two-part ascent: raise apoapsis, then circularise at it",
        brief=(
            "A real orbit. Both ends of it have to clear the atmosphere, or the air "
            "will drag you back down within a few hours.\n\n"
            "Get periapsis above ninety kilometres.\n\n"
            "The shape of it: burn to raise your apoapsis where you want the orbit "
            "to be, coast up to that apoapsis with the engine off, and burn again "
            "there to raise the other side to match. TAPO tells you how long until "
            "apoapsis."),
        primary="halcyon", bodies=["halcyon"],
        ship=dict(policy="stock", id="sparrow"),
        start=dict(kind="surface", body="halcyon", surface_angle=0),
        time_limit=3600,
        success={"all": [
            {"sensor": "PERI", "op": ">=", "value": 90000},
            {"sensor": "APO", "op": "<=", "value": 400000},
        ]},
        failure=[{"when": {"flag": "crashed"}, "message": "The Sparrow did not survive."}],
        hints=[
            "Stop the ascent burn once APO is where you want it — more is wasted.",
            "`WAIT UNTIL TAPO < 20` coasts you to just before apoapsis.",
            "Burn prograde at apoapsis and watch PERI climb to meet it.",
        ],
    ),
    """
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
""")

# =============================================================================
# 5. Circular Reasoning
# =============================================================================
mission(
    dict(
        id="circular_reasoning", order=5, title="Circular Reasoning",
        teaches="eccentricity, and holding a shape rather than hitting a number",
        brief=(
            "An orbit is not just a height, it is a shape. Eccentricity measures how "
            "far from circular it is: zero is a perfect circle.\n\n"
            "Put yourself in a circular orbit at 150 km — eccentricity below 0.01, "
            "both apsides within five kilometres of 150 — and hold it for a minute.\n\n"
            "You start already in orbit, so this is about precision, not power."),
        primary="halcyon", bodies=["halcyon"],
        ship=dict(policy="stock", id="wren"),
        start=dict(kind="orbit", body="halcyon", periapsis=100000, apoapsis=220000,
                   true_anomaly=0),
        time_limit=7200,
        success={"sustain": 60.0, "of": {"all": [
            {"sensor": "ECC", "op": "<=", "value": 0.01},
            {"sensor": "APO", "between": [145000, 155000]},
            {"sensor": "PERI", "between": [145000, 155000]},
        ]}},
        failure=[{"when": {"flag": "crashed"}, "message": "The Wren did not survive."}],
        hints=[
            "Two burns: raise the low side at apoapsis, then trim the high side at periapsis.",
            "A burn prograde at apoapsis raises periapsis. Retrograde at periapsis lowers apoapsis.",
            "Small corrections are cheap. Overshooting and coming back is not.",
        ],
    ),
    """
; Circular Reasoning — raise periapsis at apoapsis, then trim apoapsis.
        ORIENT  PROGRADE
        WAIT    UNTIL TAPO < 6
        THROTTLE 0.35
        BURN    UNTIL PERI > 149500
        THROTTLE 0
        ORIENT  RETROGRADE
        WAIT    UNTIL TPERI < 6
        THROTTLE 0.35
        BURN    UNTIL APO < 150500
        HALT
""")


# =============================================================================
# 6. Higher Ground
# =============================================================================
mission(
    dict(
        id="higher_ground", order=6, title="Higher Ground",
        teaches="the Hohmann transfer — two burns, half an orbit apart",
        brief=(
            "Moving between two circular orbits takes exactly two burns.\n\n"
            "The first raises your apoapsis to the height you want. Then you coast "
            "half an orbit, doing nothing, all the way up to that apoapsis. The "
            "second burn, there, raises the other side to match.\n\n"
            "You are in a 150 km circular orbit. Be in a 500 km circular one, "
            "eccentricity under 0.02, and hold it for half a minute.\n\n"
            "It is the cheapest way to move between two orbits, and the slowest. "
            "Both of those facts are on the scoreboard."),
        primary="halcyon", bodies=["halcyon"],
        ship=dict(policy="stock", id="wren"),
        start=dict(kind="orbit", body="halcyon", altitude=150000, true_anomaly=0),
        time_limit=14400,
        success={"sustain": 30.0, "of": {"all": [
            {"sensor": "APO", "between": [490000, 512000]},
            {"sensor": "PERI", "between": [488000, 510000]},
            {"sensor": "ECC", "op": "<=", "value": 0.02},
        ]}},
        failure=[{"when": {"flag": "crashed"}, "message": "The Wren did not survive."}],
        hints=[
            "Burn prograde until APO reads 500 km. Then stop — really stop.",
            "WAIT UNTIL TAPO < 10 will take you to the top of the transfer.",
            "The second burn is prograde again, and raises PERI to meet APO.",
        ],
    ),
    """
; Higher Ground — raise apoapsis, coast to it, raise periapsis to match.
        ORIENT  PROGRADE
        THROTTLE 1
        BURN    UNTIL APO > 500000
        THROTTLE 0
        WAIT    UNTIL TAPO < 8
        THROTTLE 0.5
        BURN    UNTIL PERI > 498000
        HALT
""")

# =============================================================================
# 7. Thick Air
# =============================================================================
mission(
    dict(
        id="aerobrake", order=7, title="Thick Air",
        teaches="aerobraking — spending atmosphere instead of propellant",
        brief=(
            "The Petrel carries an ablative shield and almost no propellant. Its "
            "orbit dips to 62 km on every pass, which is inside the atmosphere.\n\n"
            "Every pass through the air takes energy out of the orbit, and the air "
            "is free. Ride it down until apoapsis is under 215 km, then raise "
            "periapsis back above 72 km so the decay stops, and hold that.\n\n"
            "Decide at apoapsis. Periapsis is the one place you cannot raise "
            "periapsis from, and an orbit that has collapsed into the air comes "
            "apart very quickly indeed.\n\n"
            "Point the shield into the airflow. That means retrograde."),
        primary="halcyon", bodies=["halcyon"],
        ship=dict(policy="stock", id="petrel", fuel_fraction=0.4),
        start=dict(kind="orbit", body="halcyon", periapsis=60000, apoapsis=800000,
                   true_anomaly=180),
        time_limit=60000,
        success={"sustain": 30.0, "of": {"all": [
            {"sensor": "APO", "op": "<=", "value": 215000},
            {"sensor": "PERI", "op": ">=", "value": 72000},
        ]}},
        failure=[
            {"when": {"flag": "crashed"}, "message": "The Petrel came apart in the atmosphere."},
            {"when": {"flag": "out_of_fuel"}, "message": "Out of propellant with the orbit still decaying."},
        ],
        hints=[
            "ORIENT RETROGRADE once, at the start. The shield only works facing the airflow.",
            "Check your apoapsis *at* apoapsis, not whenever. Loop: coast to apoapsis, "
            "look, and either go round again or burn.",
            "When apoapsis is low enough, burn prograde there to lift periapsis clear "
            "of the air — otherwise you keep braking until you hit the ground.",
            "Once apoapsis drops into the atmosphere too, the orbit collapses inside "
            "one pass and periapsis can no longer be raised. Leave early.",
        ],
    ),
    """
; Thick Air — brake on the shield, decide at apoapsis, then lift clear.
        ORIENT  RETROGRADE
check:  WAIT    UNTIL TAPO < 6
        IF      APO > 200000
        JMP     again
        JMP     lift
again:  WAIT    120
        JMP     check
lift:   ORIENT  PROGRADE
        THROTTLE 1
        BURN    UNTIL PERI > 74000
        HALT
""")

# =============================================================================
# 8. Station Keeping
# =============================================================================
mission(
    dict(
        id="station_keeping", order=8, title="Station Keeping",
        teaches="that to catch something ahead of you, you go down",
        brief=(
            "Anchor Station is in the same 200 km orbit you are, about six "
            "kilometres ahead. Get within 500 metres of it with less than 5 m/s "
            "between you, and stay there for ten seconds.\n\n"
            "The obvious move is to burn toward it. The obvious move is wrong: "
            "thrusting prograde raises your orbit, which slows you down, which makes "
            "you fall further behind.\n\n"
            "To catch something ahead, drop below it. Lower orbits move faster."),
        primary="halcyon", bodies=["halcyon"],
        ship=dict(policy="stock", id="wren"),
        start=dict(kind="orbit", body="halcyon", altitude=200000, true_anomaly=0),
        targets=[dict(id="anchor", name="Anchor Station", body="halcyon",
                      orbit_radius=840000.0, orbit_phase0=0.00714, orbit_direction=1)],
        active_target="anchor",
        time_limit=21600,
        success={"sustain": 10.0, "of": {"all": [
            {"sensor": "TGTD", "op": "<=", "value": 500},
            {"sensor": "TGTV", "op": "<=", "value": 5},
        ]}},
        failure=[{"when": {"flag": "crashed"}, "message": "The Wren did not survive."}],
        hints=[
            "TGTD is the distance to the station; TGTV is how fast you are moving "
            "relative to it. Both have to be small at the same time.",
            "A short retrograde burn drops you into a slightly lower, faster orbit. "
            "You will start gaining on the station.",
            "A lower orbit is a shorter one. Drop periapsis, coast exactly one lap, "
            "and you return to the same place having gained on the station.",
            "Re-circularise where you first burned, with the mirror image of that "
            "burn. `BURN UNTIL ECC < 0.0005` finds the moment precisely.",
        ],
    ),
    """
; Station Keeping — drop periapsis, coast one lap, re-circularise there.
        ORIENT  RETROGRADE
        THROTTLE 0.05
        BURN    UNTIL PERI < 198700
        THROTTLE 0
        ORIENT  PROGRADE
        WAIT    UNTIL TAPO < 4
        THROTTLE 0.05
        BURN    UNTIL ECC < 0.0005
        HALT
""")

# =============================================================================
# 9. The Long Way Round
# =============================================================================
mission(
    dict(
        id="long_way_round", order=9, title="The Long Way Round",
        teaches="phasing — waiting is a manoeuvre",
        brief=(
            "Relay Six is in your orbit, but a third of the way around it. You "
            "cannot simply fly there; you have to change how fast you go round.\n\n"
            "Drop into a lower, faster orbit, let it carry you around until the relay "
            "is close, then climb back up to meet it. The waiting is not wasted time, "
            "it is the manoeuvre.\n\n"
            "Within a kilometre, under 5 m/s, held for ten seconds."),
        primary="halcyon", bodies=["halcyon"],
        ship=dict(policy="stock", id="wren"),
        start=dict(kind="orbit", body="halcyon", altitude=300000, true_anomaly=0),
        targets=[dict(id="relay6", name="Relay Six", body="halcyon",
                      orbit_radius=940000.0, orbit_phase0=2.0944, orbit_direction=1)],
        active_target="relay6",
        time_limit=43200,
        success={"sustain": 10.0, "of": {"all": [
            {"sensor": "TGTD", "op": "<=", "value": 1000},
            {"sensor": "TGTV", "op": "<=", "value": 5},
        ]}},
        failure=[{"when": {"flag": "crashed"}, "message": "The Wren did not survive."}],
        hints=[
            "Each lap of a lower orbit gains a fixed slice of angle. Three laps with "
            "periapsis at 165 km is about a third of the way round.",
            "Laps are coarse — one is worth hundreds of kilometres. You will not land "
            "on the relay by counting them.",
            "So finish with a second, much smaller phasing lap, and let the flight "
            "computer size it. To gain s metres in one lap from a 300 km orbit, drop "
            "periapsis by about 0.19*s. SENSE the gap, do the arithmetic, and "
            "BURN UNTIL PERI reaches the register you worked out.",
        ],
    ),
    """
; The Long Way Round — three coarse laps, then one the computer sizes itself.
        ORIENT  RETROGRADE
        THROTTLE 1
        BURN    UNTIL PERI < 165000
        THROTTLE 0
        ORIENT  PROGRADE
        SET     R0, 3
lap:    WAIT    30
        WAIT    UNTIL TAPO < 6
        SUB     R0, 1
        IF      R0 > 0
        JMP     lap
        THROTTLE 0.4
        BURN    UNTIL ECC < 0.0008
        THROTTLE 0
; whatever gap is left, size the final phasing lap from it
        SENSE   R1, TGTD
        MUL     R1, 0.19
        SET     R2, PERI
        SUB     R2, R1
        ORIENT  RETROGRADE
        THROTTLE 0.2
        BURN    UNTIL PERI < R2
        THROTTLE 0
        ORIENT  PROGRADE
        WAIT    30
        WAIT    UNTIL TAPO < 4
        THROTTLE 0.2
        BURN    UNTIL ECC < 0.0005
        HALT
""")

# =============================================================================
# 10. Slip the Leash
# =============================================================================
mission(
    dict(
        id="slip_the_leash", order=10, title="Slip the Leash",
        teaches="escape velocity, and what eccentricity 1 means",
        brief=(
            "Every closed orbit has an eccentricity below 1. At exactly 1 the orbit "
            "stops being closed — the apoapsis runs off to infinity and you never "
            "come back.\n\n"
            "From a 150 km orbit, that takes about 900 m/s. Go and get it.\n\n"
            "Watch APO as you burn. It climbs, then it climbs faster, and then there "
            "is no number left for it to show."),
        primary="halcyon", bodies=["halcyon"],
        ship=dict(policy="stock", id="wren"),
        start=dict(kind="orbit", body="halcyon", altitude=150000, true_anomaly=0),
        time_limit=7200,
        success={"sensor": "ECC", "op": ">=", "value": 1.0},
        failure=[{"when": {"flag": "crashed"}, "message": "The Wren did not survive."}],
        hints=[
            "Prograde, at full throttle, is the whole answer. The interesting part "
            "is knowing when to stop.",
            "`BURN UNTIL ECC >= 1` stops at exactly the right moment.",
            "INF is a value you can compare against: `IF APO == INF` works.",
        ],
    ),
    """
; Slip the Leash — burn prograde until the orbit stops being an orbit.
        ORIENT  PROGRADE
        THROTTLE 1
        BURN    UNTIL ECC >= 1
        HALT
""")

# =============================================================================
# 11. Reaching Lyra
# =============================================================================
mission(
    dict(
        id="reaching_lyra", order=11, title="Reaching Lyra",
        teaches="transfer windows — the target has to be somewhere else when you leave",
        brief=(
            "Lyra is twelve thousand kilometres out and takes nearly thirty-eight "
            "hours to go round. A transfer from your orbit takes seven and a "
            "quarter hours, during which Lyra moves seventy degrees.\n\n"
            "So you do not aim at Lyra. You aim at where Lyra will be — which means "
            "leaving when it is about 110 degrees ahead of you, and not a moment "
            "else. Windows come round every thirty-nine minutes.\n\n"
            "Get inside Lyra's sphere of influence. The SOI sensor will read 1 when "
            "you are."),
        primary="halcyon", bodies=["halcyon", "lyra"],
        ship=dict(policy="stock", id="wren"),
        start=dict(kind="orbit", body="halcyon", altitude=150000, true_anomaly=0),
        targets=[dict(id="lyra_marker", name="Lyra", body="halcyon",
                      orbit_radius=12000000.0, orbit_phase0=0.0, orbit_direction=1)],
        active_target="lyra_marker",
        time_limit=200000,
        success={"sensor": "SOI", "op": ">=", "value": 1},
        failure=[{"when": {"flag": "crashed"}, "message": "The Wren did not survive."}],
        hints=[
            "TGTA is the heading toward Lyra. RAD is the heading straight up, which "
            "is also where you are in your own orbit. The difference between them is "
            "the phase angle.",
            "Wait until that difference is about 110 degrees, then burn prograde "
            "until APO reaches Lyra's orbit — 12 000 km.",
            "Put a WAIT inside your polling loop. It costs nothing and lets the "
            "simulation skip ahead between checks.",
        ],
    ),
    """
; Reaching Lyra — wait for the window, then one long prograde burn.
        ORIENT  PROGRADE
window: WAIT    2
        SET     R0, TGTA
        SUB     R0, RAD
        IF      R0 < 0
        ADD     R0, 360
        IF      R0 > 112
        JMP     window
        IF      R0 < 108
        JMP     window
        THROTTLE 1
        BURN    UNTIL APO > 11900000
        THROTTLE 0
        WAIT    UNTIL SOI >= 1
        HALT
""")

# =============================================================================
# 12. Tightening the Knot
# =============================================================================
mission(
    dict(
        id="lyra_capture", order=12, title="Tightening the Knot",
        teaches="capture — you arrive too fast by definition, and have one good place to fix it",
        brief=(
            "You are falling toward Lyra at 370 m/s, sixteen hundred kilometres out, "
            "on a hyperbola. Left alone it will whip you past and throw you away.\n\n"
            "There is exactly one efficient place to fix that: periapsis, where you "
            "are moving fastest. A burn there buys more change in orbital energy per "
            "kilogram than the same burn anywhere else.\n\n"
            "End up in a Lyra orbit: periapsis between 20 and 200 km, eccentricity "
            "under 0.4, held for a minute."),
        primary="halcyon", bodies=["halcyon", "lyra"],
        ship=dict(policy="stock", id="wren"),
        start=dict(kind="state", px=11627722.772, py=-1556087.936,
                   vx=245.3259, vy=887.5207, angle=0.0),
        time_limit=60000,
        success={"sustain": 60.0, "of": {"all": [
            {"sensor": "SOI", "op": ">=", "value": 1},
            {"sensor": "PERI", "between": [20000, 260000]},
            {"sensor": "ECC", "op": "<=", "value": 0.4},
        ]}},
        failure=[
            {"when": {"flag": "crashed"}, "message": "The Wren hit Lyra."},
            {"when": {"all": [{"sensor": "SOI", "op": "<", "value": 1},
                              {"sensor": "T", "op": ">", "value": 20000}]},
             "message": "Lyra threw you back out. Nothing to burn against now."},
        ],
        hints=[
            "Your sensors already report your orbit about Lyra, not about Halcyon — "
            "SOI reads 1 and APO, PERI and TPERI are all Lyra-relative.",
            "TPERI counts down to periapsis. Coast to it before you do anything.",
            "Retrograde at periapsis. Stop when ECC comes under 0.4 — burning past "
            "that just costs propellant.",
        ],
    ),
    """
; Tightening the Knot — coast to periapsis, then brake there.
        ORIENT  RETROGRADE
        WAIT    UNTIL TPERI < 25
        THROTTLE 1
        BURN    UNTIL ECC < 0.25
        THROTTLE 0
        HALT
""")

# =============================================================================
# 13. Touchdown
# =============================================================================
mission(
    dict(
        id="touchdown", order=13, title="Touchdown",
        teaches="powered descent — no air, no parachutes, nothing but the engine",
        brief=(
            "Lyra has no atmosphere. There is nothing to slow you down but the thing "
            "you brought with you.\n\n"
            "You are in a 50 km circular orbit in the Heron, whose legs are rated for "
            "12 m/s. Put it on the ground under that.\n\n"
            "The orbit is worth 544 m/s of sideways motion. All of it has to go."),
        primary="halcyon", bodies=["halcyon", "lyra"],
        ship=dict(policy="stock", id="heron"),
        start=dict(kind="orbit", body="lyra", altitude=50000, true_anomaly=0),
        time_limit=14400,
        success={"flag": "landed"},
        failure=[{"when": {"flag": "crashed"}, "message": "The Heron did not survive the landing."}],
        hints=[
            "Kill the orbital velocity first, retrograde, then deal with falling.",
            "Below a kilometre, point RADIAL — straight up — so all your thrust "
            "fights gravity instead of half of it.",
            "A descent loop that keeps VVEL proportional to ALT lands softly and "
            "wastes very little: fast when high, slow when low.",
            "Do not bang the throttle between 0 and 1 — compute it. What you need is "
            "GRAV plus a correction for the speed error, divided by TWR*GRAV, which "
            "is the most acceleration this ship has.",
            "Lyra is tidally locked but not still: its surface moves at about 9 m/s. "
            "You are landing on something that is already going somewhere.",
        ],
    ),
    """
; Touchdown — cancel the orbit, then fly a computed throttle all the way down.
        ORIENT  RETROGRADE
        THROTTLE 1
        BURN    UNTIL VEL < 8
        THROTTLE 0
        POINT   RADIAL
        WAIT    UNTIL ALT < 15000
descend:
        SENSE   R0, ALT
        MUL     R0, 0.09          ; descend at 9% of your altitude per second
        MIN     R0, 55
        MAX     R0, 3
        NEG     R0                ; ...downward
        SUB     R0, VVEL          ; error
        MUL     R0, 0.6           ; gain
        ADD     R0, GRAV          ; plus enough to hover
        SET     R1, TWR
        MUL     R1, GRAV          ; the most acceleration this ship has
        DIV     R0, R1            ; -> throttle
        MAX     R0, 0
        MIN     R0, 1
        THROTTLE R0
        BURN    0.1
        IF      ALT > 3
        JMP     descend
        THROTTLE 0
        WAIT    UNTIL LANDED == 1
        HALT
""")

# =============================================================================
# 14. Homeward
# =============================================================================
mission(
    dict(
        id="homeward", order=14, title="Homeward",
        teaches="aerocapture — arriving too fast to stop, and stopping anyway",
        brief=(
            "You have left Lyra. You are twelve thousand kilometres up, falling "
            "home, and there is nowhere near enough propellant left to brake into "
            "orbit with the engine.\n\n"
            "So you will not use the engine. A thirty-metre-per-second nudge here at "
            "apoapsis is enough to drag your periapsis down into the atmosphere, and "
            "one pass through it will take twelve thousand kilometres off the far "
            "side of your orbit for free.\n\n"
            "Too shallow and it barely touches you. Too deep and the Petrel does not "
            "come out the other side. Finish with apoapsis under 1000 km and "
            "periapsis back above 72 km, held for half a minute."),
        primary="halcyon", bodies=["halcyon", "lyra"],
        ship=dict(policy="stock", id="petrel", fuel_fraction=0.85),
        start=dict(kind="orbit", body="halcyon", periapsis=300000, apoapsis=12000000,
                   true_anomaly=180),
        time_limit=120000,
        success={"sustain": 30.0, "of": {"all": [
            {"sensor": "SOI", "op": "==", "value": 0},
            {"sensor": "APO", "op": "<=", "value": 1000000},
            {"sensor": "PERI", "op": ">=", "value": 72000},
        ]}},
        failure=[
            {"when": {"flag": "crashed"}, "message": "The Petrel came apart on the way down."},
        ],
        hints=[
            "You are at apoapsis now. That is the cheapest place in the whole orbit "
            "to move the *other* end of it, and moving the other end is the job.",
            "Aim for a periapsis around 44 km. Lyra tugs on you during the long fall "
            "and will deepen it a little, so leave yourself some room.",
            "Point retrograde before you get there and stay that way. The shield only "
            "works facing the airflow, and there is no second attempt.",
            "Check at apoapsis, not whenever — and once apoapsis is low enough, burn "
            "prograde there to lift periapsis clear of the air.",
        ],
    ),
    """
; Homeward — aim the shield at the air and let Halcyon catch you.
        ORIENT  RETROGRADE
        THROTTLE 0.2
        BURN    UNTIL PERI < 44000
        THROTTLE 0
        WAIT    600
brake:  WAIT    UNTIL TAPO < 8
        IF      APO > 900000
        JMP     again
        JMP     lift
again:  WAIT    120
        JMP     brake
lift:   ORIENT  PROGRADE
        THROTTLE 0.5
        BURN    UNTIL PERI > 74000
        HALT
""")

# =============================================================================
# 15. The Whole Job
# =============================================================================
mission(
    dict(
        id="the_whole_job", order=15, title="The Whole Job",
        teaches="everything, in one program, with no hands on the controls",
        brief=(
            "The Albatross is on the pad with nine and a half tonnes of propellant "
            "and two full tanks. Lyra is somewhere overhead.\n\n"
            "Write one program that launches it, puts it in orbit, waits for the "
            "window, and delivers it into Lyra's sphere of influence. You will not "
            "touch it again after you press run.\n\n"
            "Everything you have learned, in the order you learned it."),
        primary="halcyon", bodies=["halcyon", "lyra"],
        ship=dict(policy="stock", id="albatross"),
        start=dict(kind="surface", body="halcyon", surface_angle=0),
        targets=[dict(id="lyra_marker", name="Lyra", body="halcyon",
                      orbit_radius=12000000.0, orbit_phase0=0.0, orbit_direction=1)],
        active_target="lyra_marker",
        time_limit=250000,
        success={"sensor": "SOI", "op": ">=", "value": 1},
        failure=[{"when": {"flag": "crashed"}, "message": "The Albatross did not survive."}],
        hints=[
            "This is missions 4 and 11 joined end to end. Get the ascent working "
            "first, then paste the window logic underneath it.",
            "The Albatross is heavy and turns slowly. A gravity turn that worked for "
            "the Sparrow will pitch over too fast for this.",
            "Park in a round orbit before you start looking for the window. A "
            "phase angle measured from an elliptical orbit lies to you.",
        ],
    ),
    """
; The Whole Job — pad to Lyra, hands off.
        THROTTLE 1
        POINT   RAD
        BURN    UNTIL ALT > 900
turn:   SENSE   R0, ALT
        DIV     R0, 34000
        MIN     R0, 1
        MUL     R0, 86
        SET     R1, RAD
        SUB     R1, R0
        POINT   R1
        BURN    0.25
        IF      APO < 152000
        JMP     turn
        THROTTLE 0
        ORIENT  PROGRADE
        WAIT    UNTIL TAPO < 25
        THROTTLE 1
        BURN    UNTIL PERI > 148000
        THROTTLE 0
window: WAIT    2
        SET     R0, TGTA
        SUB     R0, RAD
        IF      R0 < 0
        ADD     R0, 360
        IF      R0 > 113
        JMP     window
        IF      R0 < 107
        JMP     window
        ORIENT  PROGRADE
        THROTTLE 1
        BURN    UNTIL APO > 11900000
        THROTTLE 0
        WAIT    UNTIL SOI >= 1
        HALT
""")



# =============================================================================
# driver
# =============================================================================


def fly_one(entry, universe):
    spec = entry["spec"]
    m = runner.Mission(spec)
    world = m.build_world(universe)
    design = ships.stock(m.stock_ship_id)
    profile = design.to_profile()
    prog = vmod.assemble(entry["solution"])
    r = runner.SimRunner()
    r.setup(m, world, profile, prog, seed=0)
    result = r.run()
    return m, prog, profile, result


def thresholds_for(result):
    return dict(
        fuel=round(math.ceil(result.fuel_used * FUEL_MARGIN), 1),
        time=round(math.ceil(result.elapsed * TIME_MARGIN), 1),
        instructions=result.instruction_count,
    )


def main(write=False):
    universe = runner.load_universe()
    print(f"{'#':>2} {'mission':22} {'ship':10} {'result':34} "
          f"{'fuel kg':>8} {'time':>9} {'instr':>6} {'exec':>8}")
    print("-" * 118)
    failures = 0
    written = []
    for entry in MISSIONS:
        spec = entry["spec"]
        m, prog, profile, res = fly_one(entry, universe)
        if prog.errors:
            print(f"{spec['order']:>2} {spec['id']:22} ASSEMBLY ERRORS")
            for e in prog.errors:
                print("      line %d: %s %s" % (e["line"], e["message"], e["hint"]))
            failures += 1
            continue
        if m.errors:
            print(f"{spec['order']:>2} {spec['id']:22} MISSION ERRORS: {m.errors}")
            failures += 1
            continue
        status = "ok" if res.success else "FAILED: " + res.outcome
        if not res.success:
            failures += 1
        print(f"{spec['order']:>2} {spec['id']:22} {m.stock_ship_id:10} {status:34} "
              f"{res.fuel_used:8.1f} {res.elapsed:9.1f} {res.instruction_count:6d} "
              f"{res.instructions_executed:8d}")
        if not res.success and res.outcome_detail:
            print(f"      {res.outcome_detail}")
        if res.success:
            spec = dict(spec)
            spec["stars"] = thresholds_for(res)
            spec["reference"] = dict(
                solution=entry["solution"].strip("\n"),
                # Seven decimals: the integration test compares these to a
                # live run within 1e-6, so three was too few — and full
                # precision was too many, because a 16-digit literal is read
                # differently by Godot's JSON parser than by Python's.
                fuel_used=round(res.fuel_used, 7),
                elapsed=round(res.elapsed, 7),
                ticks=res.ticks,
                instructions=res.instruction_count,
                state_hash=res.state_hash,
                program_hash=res.program_hash,
            )
            written.append(spec)

    print("-" * 118)
    print(f"{len(MISSIONS) - failures}/{len(MISSIONS)} reference solutions fly clean")

    if write and failures == 0:
        os.makedirs(MISSIONS_DIR, exist_ok=True)
        for spec in written:
            path = os.path.join(MISSIONS_DIR, "%02d_%s.json" % (spec["order"], spec["id"]))
            with open(path, "w") as f:
                json.dump(spec, f, indent=2)
                f.write("\n")
        print(f"wrote {len(written)} mission files to missions/")
    elif write:
        print("not writing: fix the failures first")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(write="--write" in sys.argv))
