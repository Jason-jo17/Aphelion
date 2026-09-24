# Authors

## Aphelion was made by

**Jason Joseph** — <https://github.com/Jason-jo17>

Aphelion is his: the idea, the design brief, the constraints it is built to, and
the decisions at every fork. It exists because he decided it should, and it is
the shape it is because of the calls he made about what this game is for.

## Written with

**Claude Opus 5** (Anthropic) wrote code, tests and documentation under that
direction, and is recorded as `Co-Authored-By` on every commit.

This is stated plainly rather than left implicit, for two reasons. Anyone
reading the commit log will see it anyway, and a project whose headline promise
is *reproducibility* has no business being vague about its own provenance. It
also sets the expectation for anyone forking: the determinism rules, the
parity fixtures and the reference simulation are there so that a change can be
checked by a machine rather than vouched for by whoever wrote it — which is the
only way code from any author, human or otherwise, is safe to trust here.

## Contributors

Nobody yet, and the door is open. [CONTRIBUTING.md](CONTRIBUTING.md) says where
to start — a mission is the easiest and most valuable thing to add, and needs
no GDScript.

If you land a change, add yourself here in the same pull request. Name, and
optionally a link. No hierarchy, no "core team", ordered by when you arrived.

## Standing on

The people whose work Aphelion is built on, and who are owed the mention even
though they have never heard of it:

- **The Godot Engine contributors**, for an engine that is genuinely free and
  does not mind being told to stop doing the physics.
- **Butch Wesley** and GUT's contributors, for the test framework the whole
  determinism claim is proved with.
- **Sun Microsystems' fdlibm authors**, whose polynomial coefficients are the
  reason `DetMath` can be accurate and identical everywhere instead of picking
  one.

Licences for all three are in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
