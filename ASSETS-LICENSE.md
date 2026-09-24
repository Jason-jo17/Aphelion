# Asset licensing

The **code** in this repository is MIT licensed — see `LICENSE`. Assets are
licensed separately, and more permissively, so that mission packs, videos,
screenshots and derivative games can use them without tracking attribution.

## Everything in `assets/`

Released under [CC0 1.0 Universal][cc0] (public domain dedication). Use it for
anything, commercial or not, with or without credit.

| file | what | author |
| --- | --- | --- |
| `assets/art/icon.svg` | application icon | Aphelion contributors, CC0 |

`assets/fonts/` and `assets/sfx/` are currently empty. The game uses Godot's
built-in font, which is licensed under the MIT terms of the engine itself.

## Mission and ship data

`missions/*.json`, `data/*.json` and the reference solutions inside them are
CC0 as well. A mission is a puzzle, and puzzles should be free to remix.

## Third-party

| what | licence | note |
| --- | --- | --- |
| Godot Engine | MIT | not vendored; see [godotengine.org][godot] |
| GUT (test framework) | MIT | not vendored; fetched by `tools/fetch_gut.sh` |
| fdlibm polynomial constants | Sun Microsystems freely-redistributable | the numeric constants in `scripts/core/det_math.gd`; the implementation is ours |

## Contributing assets

Anything added to `assets/` must be CC0 or public domain, and must be listed in
the table above with its author. Please do not contribute assets you did not
make yourself, or whose provenance you cannot state — a game that cannot say
where its art came from is a game nobody can safely fork.

[cc0]: https://creativecommons.org/publicdomain/zero/1.0/
[godot]: https://godotengine.org/license/
