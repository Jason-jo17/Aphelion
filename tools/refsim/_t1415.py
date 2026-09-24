import math, tune_missions as T

# ---- 14 homeward: escape Lyra, aerocapture at Halcyon --------------------
def spec14(frac, apo_ok, peri_ok):
    return dict(id="h", order=14, title="h", primary="halcyon", bodies=["halcyon","lyra"],
        ship=dict(policy="stock", id="petrel", fuel_fraction=frac),
        start=dict(kind="orbit", body="lyra", altitude=100000, true_anomaly=180),
        time_limit=250000,
        success={"sustain":30.0,"of":{"all":[
            {"sensor":"SOI","op":"==","value":0},
            {"sensor":"APO","op":"<=","value":apo_ok},
            {"sensor":"PERI","op":">=","value":peri_ok}]}},
        failure=[{"when":{"flag":"crashed"},"message":"came apart on the way down"}])

src14 = """
        ORIENT  PROGRADE
        WAIT    UNTIL TPERI < 20
        THROTTLE 1
        BURN    UNTIL ECC >= 1.05
        THROTTLE 0
        WAIT    UNTIL SOI == 0
        ORIENT  RETROGRADE
        WAIT    UNTIL TAPO < 60
        THROTTLE 1
        BURN    UNTIL PERI < {drop}
        THROTTLE 0
brake:  WAIT    UNTIL TAPO < 6
        IF      APO > {stop}
        JMP     again
        JMP     lift
again:  WAIT    120
        JMP     brake
lift:   ORIENT  PROGRADE
        THROTTLE 1
        BURN    UNTIL PERI > 74000
        HALT
"""
print("mission 14")
best14 = None
for drop in (58000, 62000, 65000):
    for stop in (250000, 350000):
        res, prog, prof, tr, m = T.fly(spec14(0.85, stop + 20000, 72000),
                                       src14.format(drop=drop, stop=stop))
        tag = "ok " if res.success else "XX "
        print(f"{tag}drop {drop} stop {stop}  {res.outcome[:30]:32} "
              f"fuel {res.fuel_used:7.1f} T+{res.elapsed:8.0f} instr {res.instruction_count}")
        if res.success and (best14 is None or res.fuel_used < best14[0]):
            best14 = (res.fuel_used, drop, stop, res.elapsed, res.instruction_count)
print("best14:", best14)

# ---- 15 the whole job: pad to Lyra, one program --------------------------
print()
spec15 = dict(id="w", order=15, title="w", primary="halcyon", bodies=["halcyon","lyra"],
    ship=dict(policy="stock", id="albatross"),
    start=dict(kind="surface", body="halcyon", surface_angle=0),
    targets=[dict(id="lyra_marker", name="Lyra", body="halcyon",
                  orbit_radius=12000000.0, orbit_phase0=0.0, orbit_direction=1)],
    active_target="lyra_marker", time_limit=250000,
    success={"sensor":"SOI","op":">=","value":1},
    failure=[{"when":{"flag":"crashed"},"message":"did not survive"}])
src15 = """
        THROTTLE 1
        POINT   RAD
        BURN    UNTIL ALT > {lift}
turn:   SENSE   R0, ALT
        DIV     R0, {scale}
        MIN     R0, 1
        MUL     R0, {pitch}
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
"""
best15 = None
for lift in (900, 2000):
    for scale in (26000, 34000, 42000):
        for pitch in (80, 86):
            res, prog, prof, tr, m = T.fly(spec15, src15.format(lift=lift, scale=scale,
                                                                pitch=pitch))
            tag = "ok " if res.success else "XX "
            left = prof.fuel_capacity - res.fuel_used
            print(f"{tag}lift {lift} scale {scale} pitch {pitch}  {res.outcome[:26]:28} "
                  f"fuel {res.fuel_used:7.0f} (left {left:6.0f}) T+{res.elapsed:8.0f}")
            if res.success and (best15 is None or res.fuel_used < best15[0]):
                best15 = (res.fuel_used, lift, scale, pitch, res.elapsed,
                          res.instruction_count)
print("best15:", best15)
