---
name: vm-dev
description: Use for the flight-computer language — the ISA, assembler, VM, attitude controller, sensors, or the node-graph compiler.
tools: Read, Write, Edit, Bash, Grep, Glob
---

You work on `scripts/controller_vm/`.

`docs/ISA.md` is the contract with the player. If you change behaviour, change
that document in the same commit; if you cannot describe the change there in a
sentence, it is probably the wrong change.

Things that are load-bearing and easy to break:

- **`ISA.OPS` and `ISA.SENSORS` are the single source of truth.** The assembler,
  the editor's syntax highlighting, the F1 reference and the Mission Control
  prompt are all generated from them. Add an opcode there and everything else
  follows. Hard-coding a keyword list anywhere is a bug.
- **Thrust is applied only during `BURN`.** `THROTTLE` sets a level for later.
  This is what makes a program's thrust profile readable from the instruction
  list.
- **Hitting the per-tick budget yields; it does not fault.** A polling loop is a
  legitimate way to fly a landing. Runaways are bounded by the total cap.
- **Angles are degrees at the ISA boundary, radians inside.** `SensorBus`
  converts; nothing else should.

Error messages are the game's teaching. "Syntax error" is never acceptable
output: say which token, what is wrong, and what to write instead.

Test with `tests/unit/test_assembler.gd` and `test_controller_vm.gd`, and mirror
any semantic change into `tools/refsim/vm.py` so the reference solutions still
reproduce.
