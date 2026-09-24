# Third-party notices

Aphelion's own code is [MIT](LICENSE) and its own assets, missions and data are
[CC0](ASSETS-LICENSE.md). This file covers everything else: the work of other
people that Aphelion either builds on, ships alongside, or borrows numbers from.

Nothing here is vendored into the repository. Two of the four are nevertheless
present in a **released build**, because exporting a Godot game embeds the
engine and its default theme — so the notices below travel with the binaries,
and `.github/workflows/release.yml` packages this file with every download.

---

## Godot Engine

- **Licence:** MIT
- **In the repository:** no — you supply your own copy
- **In a release build:** yes, the export template is the engine
- **Upstream:** <https://godotengine.org/license/>

The MIT licence requires its copyright notice to travel with the software, and
the engine's full notice — including every third-party component Godot itself
bundles — is in `COPYRIGHT.txt` in the Godot source tree, reproduced in the
editor under *Help → About → Third-party Licenses*.

## The fonts in a release build

- **Licences:** SIL Open Font License 1.1 and Apache License 2.0, depending on
  the family
- **In the repository:** no
- **In a release build:** yes

Aphelion ships no fonts of its own — `assets/fonts/` is empty and the interface
uses Godot's default theme font. That font is **not** covered by the engine's
MIT licence: Godot bundles Open Sans and Noto Sans under their own terms, and
those terms are what apply. Godot's `COPYRIGHT.txt` names the exact files and
licences, which is why the paragraph above points at it.

If Aphelion ever ships a font of its own it goes in `assets/fonts/`, is listed
in `ASSETS-LICENSE.md` with its author, and is added here if it is not CC0.

## GUT — Godot Unit Test

- **Licence:** MIT
- **In the repository:** no — `tools/fetch_gut.sh` fetches it into `addons/gut/`,
  which is gitignored
- **In a release build:** no; it is a development dependency
- **Upstream:** <https://github.com/bitwes/Gut>

## fdlibm

- **Licence:** freely redistributable with the notice preserved (below)
- **In the repository:** the numeric constants in `scripts/core/det_math.gd`
  and `tools/refsim/det_math.py`
- **In a release build:** yes, as part of that code

`DetMath` exists because IEEE-754 guarantees correctly-rounded results for
`+ - * /` and `sqrt` and nothing at all for `sin`, `cos`, `exp`, `log`, `pow`
or `atan` — so each platform's libm disagrees in the last couple of ULPs, and a
1-ULP difference in the sine behind a thrust vector compounds over a
200 000-tick flight into a visibly different orbit. See
[docs/DETERMINISM.md](docs/DETERMINISM.md).

The implementation is ours. What is not ours are the **polynomial coefficients
and argument-reduction splits**, which are the classic ones from Sun's fdlibm:
minimax coefficients accurate to well under 1 ULP over the reduced ranges,
arrived at by numerical analysis nobody should repeat by hand. They are carried
in Aphelion as exact integer ratios rather than decimals, for reasons
[rule 9](docs/DETERMINISM.md) explains, but the values are fdlibm's.

Sun's notice requires only that it be preserved, so here it is, verbatim:

```
====================================================
Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.

Developed at SunSoft, a Sun Microsystems, Inc. business.
Permission to use, copy, modify, and distribute this
software is freely granted, provided that this notice
is preserved.
====================================================
```

---

## Adding a dependency

If you add one, add it here first, with all five of: what it is, its licence,
whether it lands in the repository, whether it lands in a release build, and a
link upstream. A dependency whose licence nobody wrote down is a dependency
nobody can safely fork around, and being forkable is most of the point of
shipping this under MIT.

Anything under a copyleft licence that would reach a release build needs a
conversation before the pull request, not after — not because copyleft is bad,
but because it changes what everyone downstream may do with the whole game.
